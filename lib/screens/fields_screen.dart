import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../focus_bus.dart';
import '../models/parcel.dart';
import '../services/geo_utils.dart';
import '../services/location_service.dart';
import '../services/storage.dart';
import 'field_detail_screen.dart';

/// 地块列表：搜索、按距离排序、快速定位
class FieldsScreen extends StatefulWidget {
  const FieldsScreen({super.key});

  @override
  State<FieldsScreen> createState() => _FieldsScreenState();
}

class _FieldsScreenState extends State<FieldsScreen> {
  String _query = '';
  StreamSubscription<Position>? _sub;
  Position? _me;
  bool _sortByDist = true;

  @override
  void initState() {
    super.initState();
    _watchLocation();
  }

  Future<void> _watchLocation() async {
    final err = await LocationService.ensureReady();
    if (err != null) return;
    _sub = LocationService.stream.listen((pos) {
      if (mounted) setState(() => _me = pos);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  (double dist, String dir) _distTo(Parcel p) {
    if (_me == null || p.boundary.isEmpty) return (-1, '');
    final me = LocationService.toLatLng(_me!);
    final d = GeoUtils.distance(me, p.centroid);
    final b = GeoUtils.bearingName(GeoUtils.bearing(me, p.centroid));
    return (d, b);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    var list = app.parcels.where((p) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.crop.toLowerCase().contains(q) ||
          p.notes.toLowerCase().contains(q);
    }).toList();

    if (_sortByDist) {
      list.sort((a, b) => _distTo(a).$1.compareTo(_distTo(b).$1));
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('地块'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜索名称 / 作物 / 备注',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 12),
              FilterChip(
                label: Text(_sortByDist ? '按距离' : '按时间'),
                selected: true,
                onSelected: (_) =>
                    setState(() => _sortByDist = !_sortByDist),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => FocusBus.fitAllParcels(),
                icon: const Icon(Icons.map, size: 18),
                label: const Text('地图总览'),
              ),
            ],
          ),
          Expanded(
            child: list.isEmpty
                ? _EmptyHint(hasParcels: app.parcels.isNotEmpty)
                : RefreshIndicator(
                    onRefresh: () async {},
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) =>
                          _ParcelCard(parcel: list[i], dist: _distTo(list[i])),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ParcelCard extends StatelessWidget {
  final Parcel parcel;
  final (double, String) dist;

  const _ParcelCard({required this.parcel, required this.dist});

  @override
  Widget build(BuildContext context) {
    final (d, dir) = dist;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FieldDetailScreen(parcel: parcel)),
        ),
        leading: parcel.photos.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  Storage.photoFile(parcel.photos.first),
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.grass, color: parcelColor(parcel), size: 32),
                ),
              )
            : Icon(Icons.grass, color: parcelColor(parcel), size: 36),
        title: Text(parcel.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${parcel.crop.isEmpty ? "未填作物" : parcel.crop}\n'
          '${GeoUtils.fmtArea(parcel.areaM2)} · ${parcel.photos.length}张照片',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (d >= 0)
              Text('$dir ${GeoUtils.fmtDist(d)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.my_location),
              tooltip: '在地图上找到',
              onPressed: () => FocusBus.focusParcel(parcel.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final bool hasParcels;
  const _EmptyHint({required this.hasParcels});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(hasParcels ? Icons.search_off : Icons.grass,
              size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(hasParcels ? '没有匹配的地块' : '还没有地块',
              style: Theme.of(context).textTheme.titleMedium),
          if (!hasParcels) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '去「地图」页点右下角「采集地块」，绕着地走一圈，或点击地图打点圈出边界',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
