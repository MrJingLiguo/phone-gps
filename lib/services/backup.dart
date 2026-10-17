import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../app_state.dart';
import '../models/parcel.dart';
import '../models/place.dart';
import '../models/track.dart';
import 'storage.dart';

/// 数据备份与恢复
///
/// 完整备份 = ZIP（fieldmap_data.json + photos/）
/// 轻量备份 = JSON（不含照片）
class Backup {
  static String _encode(AppState app) => jsonEncode({
        'app': 'fieldmap',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'parcels': app.parcels.map((p) => p.toJson()).toList(),
        'tracks': app.tracks.map((t) => t.toJson()).toList(),
        'places': app.places.map((p) => p.toJson()).toList(),
      });

  static String _stamp() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}'
        '_${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
  }

  /// 导出完整备份 ZIP，返回文件路径
  static Future<String> exportZip(AppState app) async {
    final dir = await getTemporaryDirectory();
    final archive = Archive();
    final jsonBytes = utf8.encode(_encode(app));
    archive.addFile(ArchiveFile(
        'fieldmap_data.json', jsonBytes.length, jsonBytes));
    final names = <String>{
      for (final p in app.parcels) ...p.photos,
      for (final p in app.places) ...p.photos,
    };
    for (final name in names) {
      final f = Storage.photoFile(name);
      if (f.existsSync()) {
        final bytes = await f.readAsBytes();
        archive.addFile(
            ArchiveFile('photos/$name', bytes.length, bytes));
      }
    }
    final zipBytes = ZipEncoder().encode(archive);
    final out = File('${dir.path}/地块管家备份_${_stamp()}.zip');
    await out.writeAsBytes(zipBytes!);
    return out.path;
  }

  /// 导出轻量 JSON（不含照片）
  static Future<String> exportJson(AppState app) async {
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/地块管家数据_${_stamp()}.json');
    await out.writeAsString(_encode(app), flush: true);
    return out.path;
  }

  /// 分享导出文件到微信/QQ/网盘等
  static Future<void> shareExport(String path, String text) async {
    await Share.shareXFiles([XFile(path)], text: text);
  }

  /// 选择备份文件并解析，返回 (数据, 照片字节表)；zip 或 json 均可
  static Future<BackupData?> pickAndParse() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return null;
    final f = File(path);
    if (!f.existsSync()) return null;
    final bytes = await f.readAsBytes();

    if (path.toLowerCase().endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? dataFile;
      final photos = <String, List<int>>{};
      for (final file in archive.files) {
        if (file.isFile) {
          if (file.name == 'fieldmap_data.json') {
            dataFile = file;
          } else if (file.name.startsWith('photos/')) {
            photos[file.name.substring('photos/'.length)] =
                file.content as List<int>;
          }
        }
      }
      if (dataFile == null) return null;
      final data = jsonDecode(utf8.decode(dataFile.content as List<int>))
          as Map<String, dynamic>;
      return BackupData(data: data, photos: photos);
    }

    // JSON（或任意文本按 JSON 解析）
    try {
      final data =
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return BackupData(data: data, photos: const {});
    } catch (_) {
      return null;
    }
  }

  /// 应用备份数据。replace=true 覆盖现有数据，否则合并(按 id 去重)。
  /// 返回摘要文本。
  static Future<String> apply(AppState app, BackupData b,
      {required bool replace}) async {
    final inParcels = (b.data['parcels'] as List? ?? [])
        .map((e) => Parcel.fromJson(e as Map<String, dynamic>))
        .toList();
    final inTracks = (b.data['tracks'] as List? ?? [])
        .map((e) => Track.fromJson(e as Map<String, dynamic>))
        .toList();
    final inPlaces = (b.data['places'] as List? ?? [])
        .map((e) => Place.fromJson(e as Map<String, dynamic>))
        .toList();

    int nP = 0, nT = 0, nPl = 0, nPhoto = 0;

    if (replace) {
      Storage.deleteAllPhotos();
      app.parcels.clear();
      app.tracks.clear();
      app.places.clear();
    }

    // 写入照片（合并模式跳过已存在的）
    for (final e in b.photos.entries) {
      if (!replace && Storage.photoExists(e.key)) continue;
      Storage.writePhotoBytes(e.key, e.value);
      nPhoto++;
    }

    final parcelIds = app.parcels.map((p) => p.id).toSet();
    for (final p in inParcels) {
      if (parcelIds.contains(p.id)) continue;
      app.parcels.add(p);
      parcelIds.add(p.id);
      nP++;
    }
    final trackIds = app.tracks.map((t) => t.id).toSet();
    for (final t in inTracks) {
      if (trackIds.contains(t.id)) continue;
      app.tracks.add(t);
      trackIds.add(t.id);
      nT++;
    }
    final placeIds = app.places.map((p) => p.id).toSet();
    for (final p in inPlaces) {
      if (placeIds.contains(p.id)) continue;
      app.places.add(p);
      placeIds.add(p.id);
      nPl++;
    }

    // 新导入的排前面（列表默认最新在前）
    await app.persist();
    return '地块 $nP · 地点 $nPl · 轨迹 $nT · 照片 $nPhoto';
  }
}

/// 解析后的备份数据
class BackupData {
  final Map<String, dynamic> data;
  final Map<String, List<int>> photos; // 文件名 → 字节
  BackupData({required this.data, required this.photos});
}
