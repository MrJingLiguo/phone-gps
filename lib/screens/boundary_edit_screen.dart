import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/parcel.dart';
import '../services/geo_utils.dart';
import '../services/gcj02.dart';
import '../services/location_service.dart';

enum _EditMode { move, straighten }

/// 边界精修：卫星图上 移动/插点/删点/直线矫正/去野点，可撤销。
/// 与卫星影像对齐可到 1~2m（影像本身为正射校正）。
class BoundaryEditScreen extends StatefulWidget {
  final Parcel parcel;
  const BoundaryEditScreen({super.key, required this.parcel});

  @override
  State<BoundaryEditScreen> createState() => _BoundaryEditScreenState();
}

class _BoundaryEditScreenState extends State<BoundaryEditScreen> {
  late final List<LatLng> _pts = List.of(widget.parcel.boundary);
  _EditMode _mode = _EditMode.move;
  int? _selected; // 移动模式：选中顶点
  int? _straightA; // 直线矫正：起点顶点
  bool _dirty = false;
  final List<List<LatLng>> _undoStack = [];
  Position? _me; // 当前定位（靠近地块时显示，便于对照修正）
  StreamSubscription<Position>? _sub;

  static const double _pickRadiusM = 15; // 点选顶点的判定半径（米）
  static const double _spikeM = 8; // 野点判定：偏离邻边弦超 8m
  static const double _showMeRangeM = 200; // 距地块该范围内显示定位点

  @override
  void initState() {
    super.initState();
    _watchLocation();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _watchLocation() async {
    final err = await LocationService.ensureReady();
    if (err != null) return; // 静默失败：不定位也不影响编辑
    _sub = LocationService.stream.listen((pos) {
      if (mounted) setState(() => _me = pos);
    });
  }

  /// 距任一顶点 200m 内才显示定位点
  bool get _meNear {
    if (_me == null || _pts.isEmpty) return false;
    final me = LocationService.toLatLng(_me!);
    for (final p in _pts) {
      if (GeoUtils.distance(me, p) <= _showMeRangeM) return true;
    }
    return false;
  }

  void _pushUndo() {
    _undoStack.add(List.of(_pts));
    if (_undoStack.length > 25) _undoStack.removeAt(0);
    _dirty = true;
  }

  void _undo() {
    if (_undoStack.isEmpty || _pts.isEmpty) return;
    setState(() {
      _pts
        ..clear()
        ..addAll(_undoStack.removeLast());
      _selected = null;
      _straightA = null;
    });
  }

  Future<void> _save() async {
    if (_pts.length < 3) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少需要 3 个顶点')));
      return;
    }
    widget.parcel.boundary = List.of(_pts);
    await context.read<AppState>().updateParcel(widget.parcel);
    if (mounted) Navigator.pop(context);
  }

  void _trySelect(LatLng wgs) {
    int? best;
    double bestD = _pickRadiusM;
    for (int i = 0; i < _pts.length; i++) {
      final d = GeoUtils.distance(wgs, _pts[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return _setSel(best);
  }

  void _setSel(int? i) => setState(() => _selected = i);

  void _onMapTap(LatLng wgs) {
    if (_mode == _EditMode.move) {
      if (_selected != null) {
        _pushUndo();
        setState(() {
          _pts[_selected!] = wgs;
        });
      } else {
        _trySelect(wgs);
      }
      return;
    }
    // 直线矫正模式：选起点→选终点→拉直
    final pick = _nearestVertex(wgs);
    if (pick == null) {
      setState(() => _straightA = null);
      return;
    }
    if (_straightA == null) {
      setState(() => _straightA = pick);
      return;
    }
    if (pick == _straightA) {
      setState(() => _straightA = null);
      return;
    }
    _pushUndo();
    _straighten(_straightA!, pick);
    setState(() {
      _straightA = null;
      _selected = null;
    });
  }

  int? _nearestVertex(LatLng wgs) {
    int? best;
    double bestD = _pickRadiusM;
    for (int i = 0; i < _pts.length; i++) {
      final d = GeoUtils.distance(wgs, _pts[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// 把 a..b 之间的顶点投影到 a-b 直线上（地边矫正成直线）
  void _straighten(int a, int b) {
    final lo = math.min(a, b);
    final hi = math.max(a, b);
    if (hi - lo < 2) return;
    final p1 = _pts[lo];
    final p2 = _pts[hi];
    final lat0 = p1.latitude;
    final cos0 = math.cos(lat0 * math.pi / 180.0);
    double px(LatLng p) => p.longitude * 111320.0 * cos0;
    double py(LatLng p) => p.latitude * 110540.0;
    final ax = px(p1), ay = py(p1), bx = px(p2), by = py(p2);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return;
    for (int k = lo + 1; k < hi; k++) {
      final q = _pts[k];
      double t = ((px(q) - ax) * dx + (py(q) - ay) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      _pts[k] = LatLng(
        (ay + t * dy) / 110540.0,
        (ax + t * dx) / (111320.0 * cos0),
      );
    }
  }

  /// 去野点：顶点偏离相邻两顶点连线弦超过 8m、且超出量大于自身两邻边长者视为毛刺
  void _despike() {
    if (_pts.length < 4) return;
    _pushUndo();
    final lat0 = _pts.first.latitude;
    final cos0 = math.cos(lat0 * math.pi / 180.0);
    double px(LatLng p) => p.longitude * 111320.0 * cos0;
    double py(LatLng p) => p.latitude * 110540.0;

    double distToSeg(LatLng q, LatLng a, LatLng b) {
      final ax = px(a), ay = py(a), bx = px(b), by = py(b);
      final qx = px(q), qy = py(q);
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      double t = len2 == 0 ? 0 : ((qx - ax) * dx + (qy - ay) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      return math.sqrt((qx - cx) * (qx - cx) + (qy - cy) * (qy - cy));
    }

    final toRemove = <int>[];
    for (int k = 0; k < _pts.length; k++) {
      final prev = _pts[(k - 1 + _pts.length) % _pts.length];
      final next = _pts[(k + 1) % _pts.length];
      final dev = distToSeg(_pts[k], prev, next);
      final e1 = GeoUtils.distance(_pts[k], prev);
      final e2 = GeoUtils.distance(_pts[k], next);
      if (dev > _spikeM && dev > math.min(e1, e2)) {
        toRemove.add(k);
      }
    }
    if (toRemove.isEmpty) {
      _undoStack.removeLast();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没发现明显野点（偏离 >8m 的点）')));
      return;
    }
    setState(() {
      for (final k in toRemove.reversed) {
        _pts.removeAt(k);
      }
      _selected = null;
      _straightA = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已去除 ${toRemove.length} 个野点（可撤销）')));
  }

  void _onMapLongPress(LatLng wgs) {
    _pushUndo();
    _insertOnEdge(wgs);
  }

  /// 长按：把新点插入到距离最近的边上
  void _insertOnEdge(LatLng wgs) {
    if (_pts.length < 2) {
      setState(() {
        _pts.add(wgs);
        _selected = _pts.length - 1;
        _dirty = true;
      });
      return;
    }
    final lat0 = _pts.first.latitude;
    final cos0 = math.cos(lat0 * math.pi / 180.0);
    double px(LatLng p) => p.longitude * 111320.0 * cos0;
    double py(LatLng p) => p.latitude * 110540.0;

    int bestEdge = 0;
    double bestD = double.infinity;
    for (int i = 0; i < _pts.length; i++) {
      final a = _pts[i];
      final b = _pts[(i + 1) % _pts.length];
      final ax = px(a), ay = py(a), bx = px(b), by = py(b);
      final qx = px(wgs), qy = py(wgs);
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      double t = len2 == 0 ? 0 : ((qx - ax) * dx + (qy - ay) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      final d = math.sqrt((qx - cx) * (qx - cx) + (qy - cy) * (qy - cy));
      if (d < bestD) {
        bestD = d;
        bestEdge = i;
      }
    }
    setState(() {
      _pts.insert(bestEdge + 1, wgs);
      _selected = bestEdge + 1;
      _straightA = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final area = GeoUtils.polygonArea(_pts);
    final hint = _mode == _EditMode.move
        ? (_selected == null
            ? '点顶点选中 → 再点新位置移动；长按边上插点'
            : '已选中顶点 ${_selected! + 1}：点击地图移动它')
        : (_straightA == null
            ? '直线矫正：点起点顶点，再点终点顶点，中间点自动拉直'
            : '起点 ${_straightA! + 1} 已选：点终点顶点完成矫正');
    return Scaffold(
      appBar: AppBar(
        title: Text('编辑边界 · ${widget.parcel.name}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: Gcj.of(
                  _pts.isNotEmpty ? _pts.first : const LatLng(35, 110)),
              initialZoom: 18,
              onTap: (_, ll) => _onMapTap(Gcj.toWgs(ll)),
              onLongPress: (_, ll) => _onMapLongPress(Gcj.toWgs(ll)),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                maxNativeZoom: 18,
                userAgentPackageName: 'com.jing.fieldmap',
              ),
              TileLayer(
                urlTemplate:
                    'https://webst0{s}.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                maxNativeZoom: 18,
                userAgentPackageName: 'com.jing.fieldmap',
              ),
              if (_pts.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: Gcj.path(_pts),
                      color: Colors.amber.withValues(alpha: 0.25),
                      borderColor: Colors.orange,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_meNear)
                    Marker(
                      point: Gcj.of(LocationService.toLatLng(_me!)),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                spreadRadius: 1),
                          ],
                        ),
                      ),
                    ),
                  for (int i = 0; i < _pts.length; i++)
                    Marker(
                      point: Gcj.of(_pts[i]),
                      width: _vertexSize(i),
                      height: _vertexSize(i),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _vertexColor(i),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Card(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: SegmentedButton<_EditMode>(
                              segments: const [
                                ButtonSegment(
                                    value: _EditMode.move,
                                    label: Text('移动',
                                        style: TextStyle(fontSize: 12)),
                                    icon: Icon(Icons.open_with, size: 14)),
                                ButtonSegment(
                                    value: _EditMode.straighten,
                                    label: Text('直线矫正',
                                        style: TextStyle(fontSize: 12)),
                                    icon:
                                        Icon(Icons.straighten, size: 14)),
                              ],
                              selected: {_mode},
                              showSelectedIcon: false,
                              onSelectionChanged: (s) => setState(() {
                                _mode = s.first;
                                _selected = null;
                                _straightA = null;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '一键去野点(偏离>8m)',
                          icon: const Icon(Icons.auto_fix_high,
                              size: 20, color: Colors.orangeAccent),
                          onPressed: _despike,
                        ),
                        IconButton(
                          tooltip: '撤销上一步',
                          icon: Icon(Icons.undo,
                              size: 20,
                              color: _undoStack.isEmpty
                                  ? Colors.white30
                                  : Colors.white),
                          onPressed:
                              _undoStack.isEmpty ? null : _undo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(hint,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      '${_pts.length}个顶点 · ${GeoUtils.fmtArea(area)}'
                      '${_meNear ? " · 蓝点=你当前的位置" : ""}',
                      style: const TextStyle(
                          color: Colors.orange, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _selected == null
                              ? null
                              : () {
                                  _pushUndo();
                                  setState(() {
                                    _pts.removeAt(_selected!);
                                    _selected = null;
                                  });
                                },
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: Colors.redAccent),
                          label: const Text('删除选中',
                              style: TextStyle(color: Colors.redAccent)),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.check,
                              size: 18, color: Colors.white),
                          label: const Text('完成',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _vertexSize(int i) {
    if (_mode == _EditMode.straighten && i == _straightA) return 32;
    return i == _selected ? 30 : 22;
  }

  Color _vertexColor(int i) {
    if (_mode == _EditMode.straighten && i == _straightA) {
      return Colors.lightBlue;
    }
    return i == _selected ? Colors.red : Colors.orange;
  }
}
