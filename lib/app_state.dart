import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'models/parcel.dart';
import 'models/place.dart';
import 'models/track.dart';
import 'services/geo_utils.dart';
import 'services/storage.dart';

/// 全局数据状态：地块 + 轨迹，统一持久化
class AppState extends ChangeNotifier {
  List<Parcel> parcels = [];
  List<Track> tracks = [];
  List<Place> places = [];
  bool loaded = false;

  Future<void> init() async {
    await Storage.init();
    final (p, t, pl) = await Storage.loadAll();
    parcels = p;
    tracks = t;
    places = pl;
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() => Storage.saveAll(parcels, tracks, places);

  /// 备份导入后手动持久化
  Future<void> persist() => _persist();

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

  // ---------- 地点 ----------

  Future<Place> addPlace({
    required String name,
    required LatLng position,
    String category = '',
    String notes = '',
  }) async {
    final place = Place(
      id: Storage.newId(),
      name: name,
      category: category,
      notes: notes,
      position: position,
    );
    places.add(place);
    await _persist();
    notifyListeners();
    return place;
  }

  Future<void> updatePlace(Place place) async {
    await _persist();
    notifyListeners();
  }

  Future<void> deletePlace(Place place) async {
    places.removeWhere((p) => p.id == place.id);
    for (final t in tracks) {
      if (t.placeId == place.id) t.placeId = null;
    }
    for (final name in List.of(place.photos)) {
      Storage.deletePhoto(name);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> addPlacePhoto(Place place, String srcPath) async {
    final name = await Storage.importPhoto(srcPath);
    place.photos.add(name);
    await _persist();
    notifyListeners();
  }

  Future<void> removePlacePhoto(Place place, String name) async {
    place.photos.remove(name);
    Storage.deletePhoto(name);
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
    String? placeId,
  }) async {
    final hh = start.hour.toString().padLeft(2, '0');
    final mm = start.minute.toString().padLeft(2, '0');
    final track = Track(
      id: Storage.newId(),
      name: '轨迹 ${start.month}月${start.day}日 $hh:$mm',
      parcelId: parcelId,
      placeId: placeId,
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

  /// 轨迹自动关联地点：中点距地点 <200m
  String? nearestPlaceId(List<LatLng> points) {
    if (points.isEmpty || places.isEmpty) return null;
    final mid = points[points.length ~/ 2];
    String? bestId;
    double bestD = double.infinity;
    for (final p in places) {
      final d = GeoUtils.distance(mid, p.position);
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
