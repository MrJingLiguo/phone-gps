import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../focus_bus.dart';
import '../services/geo_utils.dart';

/// 轨迹历史列表
class TracksScreen extends StatelessWidget {
  const TracksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('轨迹'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: app.tracks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('还没有轨迹',
                      style: TextStyle(fontSize: 17)),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      '去「地图」页点右侧 ⛳ 轨迹按钮开始记录，巡田、走边界都能记',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: app.tracks.length,
              itemBuilder: (ctx, i) {
                final t = app.tracks[i];
                final parcel = app.parcels
                    .where((p) => p.id == t.parcelId)
                    .firstOrNull;
                final place = app.places
                    .where((p) => p.id == t.placeId)
                    .firstOrNull;
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: ListTile(
                    leading: Icon(
                      place != null
                          ? Icons.place
                          : (parcel != null
                              ? Icons.grass
                              : Icons.route),
                      color: place != null
                          ? Colors.deepPurple
                          : Colors.deepOrange,
                    ),
                    title: Text(t.name),
                    subtitle: Text(
                      '${GeoUtils.fmtDist(t.distanceM)} · '
                      '${GeoUtils.fmtDuration(t.duration)} · '
                      '${t.points.length}点'
                      '${parcel != null ? ' · 地块:${parcel.name}' : ''}'
                      '${place != null ? ' · 地点:${place.name}' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.map_outlined),
                          tooltip: '在地图上查看',
                          onPressed: () => FocusBus.focusTrack(t.id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('删除这条轨迹？'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(c, false),
                                      child: const Text('取消')),
                                  FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      onPressed: () =>
                                          Navigator.pop(c, true),
                                      child: const Text('删除')),
                                ],
                              ),
                            );
                            if (ok == true && context.mounted) {
                              await app.deleteTrack(t);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
