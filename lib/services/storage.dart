import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/parcel.dart';
import '../models/track.dart';

/// 本地持久化：单个 JSON 文件 + photos/ 目录
class Storage {
  static late final Directory _baseDir;
  static late final File _dataFile;
  static late final Directory _photoDir;

  static Future<void> init() async {
    _baseDir = await getApplicationDocumentsDirectory();
    _dataFile = File('${_baseDir.path}/fieldmap_data.json');
    _photoDir = Directory('${_baseDir.path}/photos');
    if (!_photoDir.existsSync()) _photoDir.createSync(recursive: true);
  }

  static int _seq = 0;

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_seq++).toRadixString(36)}';

  static Future<(List<Parcel>, List<Track>)> loadAll() async {
    final parcels = <Parcel>[];
    final tracks = <Track>[];
    if (_dataFile.existsSync()) {
      try {
        final j = jsonDecode(_dataFile.readAsStringSync());
        parcels.addAll((j['parcels'] as List? ?? [])
            .map((e) => Parcel.fromJson(e as Map<String, dynamic>)));
        tracks.addAll((j['tracks'] as List? ?? [])
            .map((e) => Track.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // 数据损坏时不崩溃，从空开始
      }
    }
    return (parcels, tracks);
  }

  static Future<void> saveAll(List<Parcel> parcels, List<Track> tracks) async {
    final j = jsonEncode({
      'parcels': parcels.map((p) => p.toJson()).toList(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
    });
    await _dataFile.writeAsString(j, flush: true);
  }

  /// 把拍摄/选择的图片复制进 photos/ 目录，返回文件名
  static Future<String> importPhoto(String srcPath) async {
    final name =
        '${newId()}.${srcPath.split('.').last.toLowerCase()}';
    await File(srcPath).copy('${_photoDir.path}/$name');
    return name;
  }

  static File photoFile(String name) => File('${_photoDir.path}/$name');

  static void deletePhoto(String name) {
    final f = photoFile(name);
    if (f.existsSync()) f.deleteSync();
  }
}
