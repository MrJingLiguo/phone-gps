import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../focus_bus.dart';
import '../models/parcel.dart';
import '../models/place.dart';
import '../services/geo_utils.dart';
import '../services/gcj02.dart';
import '../services/location_service.dart';
import '../services/nav.dart';
import '../services/share_service.dart';
import 'field_detail_screen.dart';
import 'place_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  final MapController _map = MapController();
  final GlobalKey _mapKey = GlobalKey(); // 地图截图分享用
  StreamSubscription<Position>? _sub;

  Position? _me;
  bool _firstFixDone = false;
  String? _locError;

  // 轨迹录制
  bool _recTrack = false;
  final List<LatLng> _livePts = [];
  DateTime? _trackStart;

  // 地块边界采集
  bool _boundaryMode = false;
  final List<LatLng> _bPts = [];

  // 底图：默认卫星图（对齐地块形状直观），可切街道图
  bool _satellite = true;

  /// 底图瓦片（高德，国内直连）。注意高德是 GCJ-02，所有画上去的点都要经 Gcj.of 转换。
  List<Widget> _baseLayers() {
    const sub = ['1', '2', '3', '4'];
    if (_satellite) {
      return [
        TileLayer(
          urlTemplate:
              'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
          subdomains: sub,
          maxNativeZoom: 18,
          userAgentPackageName: 'com.jing.fieldmap',
        ),
        // 路网+注记透明图层
        TileLayer(
          urlTemplate:
              'https://webst0{s}.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}',
          subdomains: sub,
          maxNativeZoom: 18,
          userAgentPackageName: 'com.jing.fieldmap',
        ),
      ];
    }
    return [
      TileLayer(
        urlTemplate:
            'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',
        subdomains: sub,
        maxNativeZoom: 18,
        userAgentPackageName: 'com.jing.fieldmap',
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    FocusBus.req.addListener(_onFocusReq);
    _startLocation();
  }

  @override
  void dispose() {
    FocusBus.req.removeListener(_onFocusReq);
    _sub?.cancel();
    super.dispose();
  }

  void _onFocusReq() {
    final r = FocusBus.req.value;
    if (r == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyFocus(r));
  }

  void _applyFocus(MapFocusRequest r) {
    if (r.trackId != null) {
      final t = context.read<AppState>().tracks;
      final tr = t.where((x) => x.id == r.trackId).firstOrNull;
      if (tr != null && tr.points.isNotEmpty) {
        _fitPoints(tr.points);
      }
      return;
    }
    if (r.parcelId != null) {
      final p = context
          .read<AppState>()
          .parcels
          .where((x) => x.id == r.parcelId)
          .firstOrNull;
      if (p != null && p.boundary.isNotEmpty) {
        _fitPoints(p.boundary);
      }
      return;
    }
    if (r.placeId != null) {
      final pl = context
          .read<AppState>()
          .places
          .where((x) => x.id == r.placeId)
          .firstOrNull;
      if (pl != null) {
        _map.move(Gcj.of(pl.position), 17);
      }
      return;
    }
    if (r.fitAll) {
      final all = <LatLng>[
        for (final p in context.read<AppState>().parcels) ...p.boundary,
      ];
      if (all.isNotEmpty) _fitPoints(all);
      return;
    }
    if (r.center != null) {
      _map.move(Gcj.of(r.center!), 17);
    }
  }

  void _fitPoints(List<LatLng> pts) {
    if (pts.isEmpty) return;
    final b = LatLngBounds.fromPoints(Gcj.path(pts));
    _map.fitCamera(
      CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(60)),
    );
  }

  Future<void> _startLocation() async {
    final err = await LocationService.ensureReady();
    if (err != null) {
      setState(() => _locError = err);
      return;
    }
    _sub = LocationService.stream.listen(
      (pos) {
        if (!mounted) return;
        setState(() => _me = pos);
        if (!_firstFixDone) {
          _firstFixDone = true;
          _map.move(Gcj.of(LatLng(pos.latitude, pos.longitude)), 17);
        }
        final ll = LocationService.toLatLng(pos);
        if (_recTrack) setState(() => _livePts.add(ll));
        if (_boundaryMode && _shouldAcceptBoundaryPoint(ll)) {
          setState(() => _bPts.add(ll));
        }
      },
      onError: (e) {
        if (mounted) setState(() => _locError = '定位失败：$e');
      },
    );
  }

  /// 边界采点：与上一点距离 >2m 才收，避免原地堆点
  bool _shouldAcceptBoundaryPoint(LatLng ll) {
    if (_bPts.isEmpty) return true;
    return GeoUtils.distance(_bPts.last, ll) > 2;
  }

  // ---------- 动作 ----------

  Future<void> _toggleTrack() async {
    if (!_recTrack) {
      final err = await LocationService.ensureReady();
      if (err != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        return;
      }
      setState(() {
        _recTrack = true;
        _livePts.clear();
        _trackStart = DateTime.now();
      });
      return;
    }
    // 停止并询问保存
    setState(() => _recTrack = false);
    final pts = List.of(_livePts);
    final start = _trackStart ?? DateTime.now();
    final end = DateTime.now();
    if (pts.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('轨迹点太少（至少2个点），已放弃')));
      }
      return;
    }
    if (!mounted) return;
    final dist = GeoUtils.pathLength(pts);
    final dur = GeoUtils.fmtDuration(end.difference(start));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存轨迹？'),
        content: Text('共 ${pts.length} 个点\n距离 ${GeoUtils.fmtDist(dist)}\n时长 $dur'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('放弃')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true && mounted) {
      final app = context.read<AppState>();
      await app.addTrack(
          points: pts,
          start: start,
          end: end,
          parcelId: app.nearestParcelId(pts),
          placeId: app.nearestPlaceId(pts));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('轨迹已保存')));
      }
    }
  }

  Future<void> _toggleBoundary() async {
    if (!_boundaryMode) {
      final err = await LocationService.ensureReady();
      if (err != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        return;
      }
      setState(() {
        _boundaryMode = true;
        _bPts.clear();
      });
      return;
    }
    setState(() => _boundaryMode = false);
    if (_bPts.length >= 3 && mounted) {
      await _finishBoundaryDialog();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少需要 3 个边界点')));
    }
  }

  // ---------- 地点 ----------

  Future<void> _addPlaceAt(LatLng wgs) async {
    final nameCtl = TextEditingController();
    final catCtl = TextEditingController();
    final noteCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存地点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名称 *')),
            TextField(
                controller: catCtl,
                decoration: const InputDecoration(
                    labelText: '类别（厂家/亲戚家/朋友家/收藏点…）')),
            TextField(
                controller: noteCtl,
                decoration: const InputDecoration(labelText: '备注')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () =>
                nameCtl.text.trim().isEmpty ? null : Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().addPlace(
            name: nameCtl.text.trim(),
            position: wgs,
            category: catCtl.text.trim(),
            notes: noteCtl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('地点「${nameCtl.text.trim()}」已保存')));
      }
    }
  }

  void _showAddPlaceMenu(LatLng wgs) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.add_location_alt,
              color: Colors.deepPurple),
          title: const Text('在此处添加地点'),
          onTap: () {
            Navigator.pop(ctx);
            _addPlaceAt(wgs);
          },
        ),
      ),
    );
  }

  void _showPlaceSheet(Place p) {
    final app = context.read<AppState>();
    final me = _me == null ? null : LocationService.toLatLng(_me!);
    String distStr = '';
    if (me != null) {
      final d = GeoUtils.distance(me, p.position);
      final b = GeoUtils.bearing(me, p.position);
      distStr = ' · ${GeoUtils.bearingName(b)} ${GeoUtils.fmtDist(d)}';
    }
    final routes =
        app.tracks.where((t) => t.placeId == p.id).toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${p.name}$distStr',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${p.category.isEmpty ? "未分类" : p.category} · '
                '${p.photos.length}张照片 · ${routes.length}条路线',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.navigation),
                    label: const Text('导航去'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      openNavigation(context, p.name, p.position);
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.info_outline),
                    label: const Text('详情'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PlaceDetailScreen(place: p)),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  if (routes.isNotEmpty)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.route),
                      label: const Text('看路线'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        FocusBus.focusTrack(routes.first.id);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finishBoundaryDialog() async {
    final nameCtl = TextEditingController();
    final cropCtl = TextEditingController();
    final noteCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('保存地块（${_bPts.length} 点）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(labelText: '地块名称 *')),
            TextField(
                controller: cropCtl,
                decoration:
                    const InputDecoration(labelText: '作物（如：玉米、水稻）')),
            TextField(
                controller: noteCtl,
                decoration: const InputDecoration(labelText: '备注')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '面积 ${GeoUtils.fmtArea(GeoUtils.polygonArea(_bPts))}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () =>
                nameCtl.text.trim().isEmpty ? null : Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final app = context.read<AppState>();
      await app.addParcel(
        name: nameCtl.text.trim(),
        crop: cropCtl.text.trim(),
        notes: noteCtl.text.trim(),
        boundary: _bPts,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('地块「${nameCtl.text.trim()}」已保存')));
      }
    }
  }

  void _showParcelSheet(Parcel p) {
    final me = _me == null ? null : LocationService.toLatLng(_me!);
    String distStr = '';
    if (me != null && p.boundary.isNotEmpty) {
      final d = GeoUtils.distance(me, p.centroid);
      final b = GeoUtils.bearing(me, p.centroid);
      distStr = ' · ${GeoUtils.bearingName(b)} ${GeoUtils.fmtDist(d)}';
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${p.name}$distStr',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${p.crop.isEmpty ? '未填作物' : p.crop} · '
                '${GeoUtils.fmtArea(p.areaM2)} · ${p.photos.length}张照片',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.navigation),
                    label: const Text('导航去'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      openNavigation(context, p.name, p.centroid);
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.info_outline),
                    label: const Text('详情'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => FieldDetailScreen(parcel: p)),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.near_me),
                    label: const Text('居中'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _fitPoints(p.boundary);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final liveDist = GeoUtils.pathLength(_livePts);
    return Scaffold(
      appBar: AppBar(
        title: Text(_boundaryMode ? '采集地块边界' : '地块管家'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享当前地图',
            onPressed: () async {
              String text = '【地块管家】我的地图';
              if (_me != null) {
                final me = LocationService.toLatLng(_me!);
                text = '【地块管家】📍 我现在的位置\n'
                    '👉 用高德地图打开：'
                    '${ShareService.amapLink(me, '我的位置')}';
              }
              await ShareService.shareMapImage(_mapKey, text);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          RepaintBoundary(
            key: _mapKey,
            child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _me == null
                  ? const LatLng(35.0, 110.0)
                  : Gcj.of(LocationService.toLatLng(_me!)),
              initialZoom: _me == null ? 4.5 : 17,
              onTap: (_, ll) {
                // 地图事件是 GCJ-02 坐标，入库转回 WGS-84
                final wgs = Gcj.toWgs(ll);
                if (_boundaryMode) {
                  setState(() => _bPts.add(wgs));
                  return;
                }
                // flutter_map v7 多边形无 onTap：用点内检测选中地块
                for (final p in app.parcels) {
                  if (p.boundary.length >= 3 &&
                      GeoUtils.pointInPolygon(wgs, p.boundary)) {
                    _showParcelSheet(p);
                    break;
                  }
                }
              },
              onLongPress: (_, ll) {
                if (_boundaryMode) {
                  setState(() => _bPts.add(Gcj.toWgs(ll)));
                  return;
                }
                _showAddPlaceMenu(Gcj.toWgs(ll));
              },
            ),
            children: [
              ..._baseLayers(),
              // 地块多边形
              PolygonLayer(
                polygons: [
                  for (final p in app.parcels)
                    if (p.boundary.length >= 3)
                      Polygon(
                        points: Gcj.path(p.boundary),
                        color: parcelColor(p).withValues(alpha: 0.25),
                        borderColor: parcelColor(p),
                        borderStrokeWidth: 2.5,
                      ),
                ],
              ),
              // 轨迹
              PolylineLayer(
                polylines: [
                  for (final t in app.tracks)
                    if (t.points.length >= 2)
                      Polyline(
                        points: Gcj.path(t.points),
                        strokeWidth: 4,
                        color: Colors.deepOrange.withValues(alpha: 0.8),
                      ),
                  if (_livePts.length >= 2)
                    Polyline(
                        points: Gcj.path(_livePts),
                        strokeWidth: 5,
                        color: Colors.redAccent),
                ],
              ),
              // 边界草稿
              if (_boundaryMode && _bPts.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    if (_bPts.length >= 3)
                      Polygon(
                        points: Gcj.path(_bPts),
                        color: Colors.amber.withValues(alpha: 0.3),
                        borderColor: Colors.orange,
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
              // 点位标注
              MarkerLayer(
                markers: [
                  if (_boundaryMode)
                    for (final pt in _bPts)
                      Marker(
                        point: Gcj.of(pt),
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  // 地点标记（紫罗兰色，区别于地块）
                  for (final pl in app.places)
                    Marker(
                      point: Gcj.of(pl.position),
                      width: 120,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showPlaceSheet(pl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.place,
                                color: Colors.deepPurple, size: 22),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(6),
                                border:
                                    Border.all(color: Colors.deepPurple),
                              ),
                              child: Text(
                                pl.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.deepPurple,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 地块名称标签
                  for (final p in app.parcels)
                    if (p.boundary.isNotEmpty)
                      Marker(
                        point: Gcj.of(p.centroid),
                        width: 120,
                        height: 28,
                        child: GestureDetector(
                          onTap: () => _showParcelSheet(p),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: parcelColor(p)),
                              ),
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: parcelColor(p),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  if (_me != null)
                    Marker(
                      point: Gcj.of(LocationService.toLatLng(_me!)),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                spreadRadius: 2),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
            ),
          ),
          // 定位错误提示
          if (_locError != null)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Card(
                color: Colors.orange.shade100,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(_locError!,
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
          // 右侧按钮列
          Positioned(
            right: 12,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapFab(
                  tooltip: '切换底图(卫星/街道)',
                  icon: _satellite ? Icons.satellite_alt : Icons.map_outlined,
                  onTap: () => setState(() => _satellite = !_satellite),
                ),
                const SizedBox(height: 10),
                _MapFab(
                  tooltip: '我的位置',
                  icon: Icons.my_location,
                  onTap: () {
                    if (_me != null) {
                      _map.move(
                          Gcj.of(LocationService.toLatLng(_me!)), 17);
                    } else {
                      _startLocation();
                    }
                  },
                ),
                const SizedBox(height: 10),
                _MapFab(
                  tooltip: '显示全部地块',
                  icon: Icons.crop_free,
                  onTap: () => _applyFocus(const MapFocusRequest(fitAll: true)),
                ),
                const SizedBox(height: 10),
                _MapFab(
                  tooltip: '存地点(当前位置)',
                  icon: Icons.add_location_alt,
                  onTap: () {
                    if (_me != null) {
                      _addPlaceAt(LocationService.toLatLng(_me!));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('还没有定位，等 GPS 就绪或长按地图选点')));
                    }
                  },
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'track',
                  onPressed: _toggleTrack,
                  backgroundColor:
                      _recTrack ? Colors.redAccent : Colors.white,
                  child: Icon(
                    _recTrack ? Icons.stop : Icons.route,
                    color: _recTrack ? Colors.white : Colors.deepOrange,
                  ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'boundary',
                  onPressed: _toggleBoundary,
                  backgroundColor:
                      _boundaryMode ? Colors.orange : Colors.white,
                  icon: Icon(_boundaryMode ? Icons.check : Icons.draw,
                      color: _boundaryMode ? Colors.white : Colors.green),
                  label: Text(
                    _boundaryMode ? '完成' : '采集地块',
                    style: TextStyle(
                        color: _boundaryMode ? Colors.white : Colors.green),
                  ),
                ),
              ],
            ),
          ),
          // 轨迹录制信息条
          if (_recTrack)
            Positioned(
              left: 12,
              bottom: 16,
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, color: Colors.red, size: 10),
                          const SizedBox(width: 6),
                          Text(
                            '录制中 ${GeoUtils.fmtDist(liveDist)}'
                            ' · ${_livePts.length}点',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      if (_me != null)
                        Text(
                          '${LocationService.speedKmh(_me!).toStringAsFixed(1)} km/h',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          // 边界采集提示条
          if (_boundaryMode)
            Positioned(
              left: 12,
              bottom: 16,
              child: Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '绕地块走一圈自动采点（${_bPts.length}点）\n也可点击/长按地图手动加点',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _MapFab(
      {required this.tooltip, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: tooltip,
      tooltip: tooltip,
      backgroundColor: Colors.white,
      onPressed: onTap,
      child: Icon(icon, color: Colors.black87),
    );
  }
}
