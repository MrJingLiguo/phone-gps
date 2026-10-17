import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../models/parcel.dart';
import '../services/geo_utils.dart';
import '../services/gcj02.dart';
import '../services/storage.dart';
import 'photo_viewer_screen.dart';

class FieldDetailScreen extends StatelessWidget {
  final Parcel parcel;
  const FieldDetailScreen({super.key, required this.parcel});

  Future<void> _edit(BuildContext context) async {
    final app = context.read<AppState>();
    final nameCtl = TextEditingController(text: parcel.name);
    final cropCtl = TextEditingController(text: parcel.crop);
    final noteCtl = TextEditingController(text: parcel.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑地块'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: '名称')),
            TextField(
                controller: cropCtl,
                decoration: const InputDecoration(labelText: '作物')),
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
      parcel.name = nameCtl.text.trim();
      parcel.crop = cropCtl.text.trim();
      parcel.notes = noteCtl.text.trim();
      await app.updateParcel(parcel);
    }
  }

  Future<void> _pickPhoto(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 2048,
    );
    if (xfile == null) return;
    if (!context.mounted) return;
    await context.read<AppState>().addPhoto(parcel, xfile.path);
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除地块？'),
        content: Text('「${parcel.name}」及其照片将被删除，轨迹保留但解除关联。'),
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
      await context.read<AppState>().deleteParcel(parcel);
      if (context.mounted) Navigator.pop(context);
    }
  }

  Future<void> _navigate(BuildContext context) async {
    if (parcel.boundary.isEmpty) return;
    // 导航给高德等地图 app 用 GCJ-02 坐标
    final c = Gcj.of(parcel.centroid);
    final uri = Uri.parse(
        'geo:${c.latitude.toStringAsFixed(6)},${c.longitude.toStringAsFixed(6)}'
        '?q=${c.latitude.toStringAsFixed(6)},${c.longitude.toStringAsFixed(6)}'
        '(${Uri.encodeComponent(parcel.name)})');
    final ok = await canLaunchUrl(uri);
    if (!context.mounted) return;
    if (ok) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到地图应用，无法导航')));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>(); // 数据变化时刷新
    final tracks = context
        .read<AppState>()
        .tracks
        .where((t) => t.parcelId == parcel.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(parcel.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(context)),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 概要信息
          Row(
            children: [
              _Stat(label: '面积', value: GeoUtils.fmtArea(parcel.areaM2)),
              _Stat(label: '周长', value: GeoUtils.fmtDist(parcel.perimeterM)),
              _Stat(label: '边界点', value: '${parcel.boundary.length}'),
              _Stat(label: '作物', value: parcel.crop.isEmpty ? '未填' : parcel.crop),
            ],
          ),
          if (parcel.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(parcel.notes, style: const TextStyle(color: Colors.grey)),
            ),
          const SizedBox(height: 12),
          // 迷你地图
          if (parcel.boundary.isNotEmpty)
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: Gcj.of(parcel.centroid),
                    initialZoom: 16,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',
                      maxNativeZoom: 18,
                      userAgentPackageName: 'com.jing.fieldmap',
                    ),
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: Gcj.path(parcel.boundary),
                          color: parcelColor(parcel).withValues(alpha: 0.3),
                          borderColor: parcelColor(parcel),
                          borderStrokeWidth: 3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          // 操作按钮
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.navigation),
                  label: const Text('导航去'),
                  onPressed: () => _navigate(context),
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
          // 照片
          Text('照片 (${parcel.photos.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (parcel.photos.isEmpty)
            const Text('还没有照片，点上方「拍照」记录地块现状',
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
              itemCount: parcel.photos.length,
              itemBuilder: (ctx, i) {
                final name = parcel.photos[i];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoViewerScreen(parcel: parcel, index: i),
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
                          .removePhoto(parcel, name);
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
          const Divider(height: 24),
          // 关联轨迹
          Text('关联轨迹 (${tracks.length})',
              style: Theme.of(context).textTheme.titleMedium),
          ...tracks.map((t) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.route),
                title: Text(t.name),
                subtitle: Text(
                    '${GeoUtils.fmtDist(t.distanceM)} · ${GeoUtils.fmtDuration(t.duration)}'),
              )),
          if (tracks.isEmpty)
            const Text('录制轨迹时若途经本地块（200m 内）会自动关联',
                style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
