import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// 跨页请求地图定位/缩放：地块页、轨迹页 → 地图页
class MapFocusRequest {
  final LatLng? center;
  final String? parcelId;
  final String? trackId;
  final bool fitAll;

  const MapFocusRequest(
      {this.center, this.parcelId, this.trackId, this.fitAll = false});
}

class FocusBus {
  static final ValueNotifier<MapFocusRequest?> req = ValueNotifier(null);

  static void focusParcel(String id) =>
      req.value = MapFocusRequest(parcelId: id);

  static void focusTrack(String id) =>
      req.value = MapFocusRequest(trackId: id);

  static void fitAllParcels() => req.value = const MapFocusRequest(fitAll: true);
}
