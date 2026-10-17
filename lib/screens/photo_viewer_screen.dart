import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/parcel.dart';
import '../models/place.dart';
import '../services/storage.dart';

/// 全屏看图（地块或地点的照片），左右滑动，长按/按钮删除
class PhotoViewerScreen extends StatefulWidget {
  final Parcel? parcel;
  final Place? place;
  final int index;
  const PhotoViewerScreen({
    super.key,
    this.parcel,
    this.place,
    required this.index,
  }) : assert(parcel != null || place != null);

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late int _idx = widget.index.clamp(0, _photos.length - 1);

  List<String> get _photos =>
      widget.parcel?.photos ?? widget.place?.photos ?? [];

  Future<void> _delete(String name) async {
    final app = context.read<AppState>();
    if (widget.parcel != null) {
      await app.removePhoto(widget.parcel!, name);
    } else if (widget.place != null) {
      await app.removePlacePhoto(widget.place!, name);
    }
  }

  Future<void> _confirmDelete() async {
    final name = _photos[_idx];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这张照片？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _delete(name);
    if (!mounted) return;
    if (_photos.isEmpty) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _idx = _idx.clamp(0, _photos.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title:
            Text(photos.isEmpty ? '照片' : '照片 ${_idx + 1}/${photos.length}'),
        actions: [
          if (photos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: photos.isEmpty
          ? const SizedBox.shrink()
          : PageView.builder(
              controller: PageController(initialPage: _idx),
              itemCount: photos.length,
              onPageChanged: (v) => setState(() => _idx = v),
              itemBuilder: (ctx, n) => InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: Image.file(
                    Storage.photoFile(photos[n]),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.white30,
                        size: 64),
                  ),
                ),
              ),
            ),
    );
  }
}
