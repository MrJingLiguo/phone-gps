import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/parcel.dart';
import '../services/geo_utils.dart';
import '../services/gcj02.dart';

/// 边界精修：卫星图上 点顶点选中→点新位置移动；长按边上插点；删点。
/// 与卫星影像对齐可到 1~2m（影像本身为正射校正）。
class BoundaryEditScreen extends StatefulWidget {
  final Parcel parcel;
  const BoundaryEditScreen({super.key, required this.parcel});

  @override
  State<BoundaryEditScreen> createState() => _BoundaryEditScreenState();
}

class _BoundaryEditScreenState extends State<BoundaryEditScreen> {
  late final List<LatLng> _pts = List.of(widget.parcel.boundary);
  int? _selected; // 选中顶点索引
  bool _dirty = false;

  static const double _pickRadiusM = 15; // 点选顶点的判定半径（米）

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

  /// 选中点击位置附近的顶点（换算成米距离判定）
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
    setState(() => _selected = best);
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
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final area = GeoUtils.polygonArea(_pts);
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
              onTap: (_, ll) {
                final wgs = Gcj.toWgs(ll);
                if (_selected != null) {
                  setState(() {
                    _pts[_selected!] = wgs;
                    _dirty = true;
                  });
                } else {
                  _trySelect(wgs);
                }
              },
              onLongPress: (_, ll) => _insertOnEdge(Gcj.toWgs(ll)),
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
                  for (int i = 0; i < _pts.length; i++)
                    Marker(
                      point: Gcj.of(_pts[i]),
                      width: i == _selected ? 30.0 : 22.0,
                      height: i == _selected ? 30.0 : 22.0,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              i == _selected ? Colors.red : Colors.orange,
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
                    horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selected == null
                          ? '点顶点选中 → 再点新位置移动；长按边上插点'
                          : '已选中顶点 ${_selected! + 1}：点击地图移动它',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_pts.length}个顶点 · ${GeoUtils.fmtArea(area)}',
                      style: const TextStyle(
                          color: Colors.orange, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _selected == null
                              ? null
                              : () => setState(() {
                                    _pts.removeAt(_selected!);
                                    _selected = null;
                                    _dirty = true;
                                  }),
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
}
