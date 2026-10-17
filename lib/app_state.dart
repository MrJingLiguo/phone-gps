import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'models/parcel.dart';
import 'models/track.dart';
import 'services/geo_utils.dart';
import 'services/storage.dart';

/// 全局数据状态：地块 + 轨迹，统一持久化
class AppState extends ChangeNotifier {
  List<Parcel> parcels = [];
  List<Track> tracks = [];
  bool loaded = false;

  Future<void> init() async {
    await Storage.init();
    final (p, t) = await Storage.loadAll();
    parcels = p;
    tracks = t;
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() => Storage.saveAll(parcels, tracks);

  // ---------- 地块 ----------

  Future<Parcel> addParcel({
    required String name,
    required List<LatLng> boundary,
    String crop = '',
    String notes = '',
  }) async {
    final parcel = Parcel(
      id: Storage.newId(),
      name: name,
      crop: crop,
      notes: notes,
      boundary: List.of(boundary),
      colorIdx: parcels.length % parcelColors.length,
    );
    parcels.add(parcel);
    await _persist();
    notifyListeners();
    return parcel;
  }

  Future<void> updateParcel(Parcel parcel) async {
    await _persist();
    notifyListeners();
  }

  Future<void> deleteParcel(Parcel parcel) async {
    parcels.removeWhere((p) => p.id == parcel.id);
    for (final t in tracks) {
      if (t.parcelId == parcel.id) t.parcelId = null;
    }
    for (final name in List.of(parcel.photos)) {
      Storage.deletePhoto(name);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> addPhoto(Parcel parcel, String srcPath) async {
    final name = await Storage.importPhoto(srcPath);
    parcel.photos.add(name);
    await _persist();
    notifyListeners();
  }

  Future<void> removePhoto(Parcel parcel, String name) async {
    parcel.photos.remove(name);
    Storage.deletePhoto(name);
    await _persist();
    notifyListeners();
  }

  // ---------- 轨迹 ----------

  Future<Track> addTrack({
    required List<LatLng> points,
    required DateTime start,
    required DateTime end,
    String? parcelId,
  }) async {
    final hh = start.hour.toString().padLeft(2, '0');
    final mm = start.minute.toString().padLeft(2, '0');
    final track = Track(
      id: Storage.newId(),
      name: '轨迹 ${start.month}月${start.day}日 $hh:$mm',
      parcelId: parcelId,
      points: List.of(points),
      startTime: start,
      endTime: end,
      distanceM: GeoUtils.pathLength(points),
    );
    tracks.insert(0, track);
    await _persist();
    notifyListeners();
    return track;
  }

  Future<void> deleteTrack(Track track) async {
    tracks.removeWhere((t) => t.id == track.id);
    await _persist();
    notifyListeners();
  }

  /// 保存轨迹时关联最近的、距其中点 <200m 的地块
  String? nearestParcelId(List<LatLng> points) {
    if (points.isEmpty || parcels.isEmpty) return null;
    final mid = points[points.length ~/ 2];
    String? bestId;
    double bestD = double.infinity;
    for (final p in parcels) {
      if (p.boundary.isEmpty) continue;
      final d = GeoUtils.distance(mid, p.centroid);
      if (d < bestD) {
        bestD = d;
        bestId = p.id;
      }
    }
    return bestD <= 200 ? bestId : null;
  }
}

/// 地块配色（按 colorIdx 循环取）
const List<Color> parcelColors = [
  Color(0xFF2E7D32),
  Color(0xFF1565C0),
  Color(0xFFEF6C00),
  Color(0xFF6A1B9A),
  Color(0xFFC62828),
  Color(0xFF00838F),
];

Color parcelColor(Parcel p) => parcelColors[p.colorIdx % parcelColors.length];
