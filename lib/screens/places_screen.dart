import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../focus_bus.dart';
import '../models/place.dart';
import '../services/geo_utils.dart';
import '../services/location_service.dart';
import '../services/storage.dart';
import 'place_detail_screen.dart';

/// 地点列表：厂家、亲戚朋友家、收藏点
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
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

  (double dist, String dir) _distTo(Place p) {
    if (_me == null) return (-1, '');
    final me = LocationService.toLatLng(_me!);
    final d = GeoUtils.distance(me, p.position);
    final b = GeoUtils.bearingName(GeoUtils.bearing(me, p.position));
    return (d, b);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    var list = app.places.where((p) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.notes.toLowerCase().contains(q);
    }).toList();

    if (_sortByDist) {
      list.sort((a, b) => _distTo(a).$1.compareTo(_distTo(b).$1));
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('地点'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜索名称 / 类别 / 备注',
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
                onSelected: (_) => setState(() => _sortByDist = !_sortByDist),
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
                ? _EmptyHint(hasPlaces: app.places.isNotEmpty)
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (ctx, i) =>
                        _PlaceCard(place: list[i], dist: _distTo(list[i])),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final Place place;
  final (double, String) dist;

  const _PlaceCard({required this.place, required this.dist});

  @override
  Widget build(BuildContext context) {
    final (d, dir) = dist;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: place)),
        ),
        leading: place.photos.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  Storage.photoFile(place.photos.first),
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.place,
                      color: Colors.deepPurple, size: 32),
                ),
              )
            : const Icon(Icons.place, color: Colors.deepPurple, size: 36),
        title: Text(place.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${place.category.isEmpty ? "未分类" : place.category}\n'
          '${place.photos.length}张照片 · ${place.notes.isEmpty ? "无备注" : place.notes}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
              onPressed: () => FocusBus.focusPlace(place.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final bool hasPlaces;
  const _EmptyHint({required this.hasPlaces});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(hasPlaces ? Icons.search_off : Icons.place,
              size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(hasPlaces ? '没有匹配的地点' : '还没有地点',
              style: const TextStyle(fontSize: 17)),
          if (!hasPlaces) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '去「地图」页：长按地图任意位置、或点右侧 ⊕ 存地点按钮，'
                '把厂家、亲戚朋友家、常去的地方存下来',
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
