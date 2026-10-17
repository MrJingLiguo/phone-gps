import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../focus_bus.dart';
import '../models/place.dart';
import '../services/geo_utils.dart';
import '../services/gcj02.dart';
import '../services/nav.dart';
import '../services/share_service.dart';
import '../services/storage.dart';
import 'photo_viewer_screen.dart';

/// 地点详情：照片、迷你地图、导航、到访路线
class PlaceDetailScreen extends StatelessWidget {
  final Place place;
  const PlaceDetailScreen({super.key, required this.place});

  Future<void> _edit(BuildContext context) async {
    final nameCtl = TextEditingController(text: place.name);
    final catCtl = TextEditingController(text: place.category);
    final noteCtl = TextEditingController(text: place.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑地点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: '名称')),
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
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok == true && nameCtl.text.trim().isNotEmpty) {
      place.name = nameCtl.text.trim();
      place.category = catCtl.text.trim();
      place.notes = noteCtl.text.trim();
      await context.read<AppState>().updatePlace(place);
    }
  }

  Future<void> _pickPhoto(BuildContext context, ImageSource source) async {
    final xfile = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 2048,
    );
    if (xfile == null) return;
    if (!context.mounted) return;
    await context.read<AppState>().addPlacePhoto(place, xfile.path);
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除地点？'),
        content: Text('「${place.name}」及其照片将被删除，轨迹保留但解除关联。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().deletePlace(place);
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>(); // 数据变化时刷新
    final routes = context
        .read<AppState>()
        .tracks
        .where((t) => t.placeId == place.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(place.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
              icon: const Icon(Icons.share),
              tooltip: '分享地点',
              onPressed: () => ShareService.sharePlace(place)),
          IconButton(
              icon: const Icon(Icons.edit), onPressed: () => _edit(context)),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Chip(
                avatar: const Icon(Icons.label, size: 16),
                label: Text(place.category.isEmpty ? '未分类' : place.category),
              ),
              const SizedBox(width: 8),
              Text(GeoUtils.coordText(place.position),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          if (place.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(place.notes,
                  style: const TextStyle(color: Colors.grey)),
            ),
          const SizedBox(height: 12),
          // 迷你地图
          SizedBox(
            height: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: Gcj.of(place.position),
                  initialZoom: 16,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',
                    maxNativeZoom: 18,
                    userAgentPackageName: 'com.jing.fieldmap',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: Gcj.of(place.position),
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.place,
                            color: Colors.deepPurple, size: 36),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.navigation),
                  label: const Text('导航去'),
                  onPressed: () => openNavigation(
                      context, place.name, place.position),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('拍照'),
                  onPressed: () => _pickPhoto(context, ImageSource.camera),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('相册'),
                  onPressed: () => _pickPhoto(context, ImageSource.gallery),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Text('到访路线 (${routes.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            '第一次去时录的轨迹会自动挂到这里，下次照着走就能找到',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          ...routes.map((t) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.route, color: Colors.deepPurple),
                title: Text(t.name),
                subtitle: Text(
                    '${GeoUtils.fmtDist(t.distanceM)} · ${GeoUtils.fmtDuration(t.duration)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.map_outlined),
                  tooltip: '在地图上查看',
                  onPressed: () => FocusBus.focusTrack(t.id),
                ),
              )),
          if (routes.isEmpty)
            const Text('录制轨迹时若到达本地点（200m 内）会自动关联',
                style: TextStyle(color: Colors.grey)),
          const Divider(height: 24),
          Text('照片 (${place.photos.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (place.photos.isEmpty)
            const Text('还没有照片，点上方「拍照」记录门头、路口等标识',
                style: TextStyle(color: Colors.grey))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: place.photos.length,
              itemBuilder: (ctx, i) {
                final name = place.photos[i];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoViewerScreen(parcel: null, place: place, index: i),
                    ),
                  ),
                  onLongPress: () async {
                    final ok = await showDialog<bool>(
                      context: ctx,
                      builder: (c) => AlertDialog(
                        title: const Text('删除这张照片？'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('删除')),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await context
                          .read<AppState>()
                          .removePlacePhoto(place, name);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      Storage.photoFile(name),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Colors.black12),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
