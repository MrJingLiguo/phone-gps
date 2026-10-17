import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// GPS 定位封装：权限检查、定位流
class LocationService {
  /// 确保定位权限与服务可用，失败返回中文错误信息，成功返回 null
  static Future<String?> ensureReady() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return '定位服务未开启，请到系统设置打开 GPS';

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) return '定位权限被拒绝';
    if (perm == LocationPermission.deniedForever) {
      return '定位权限被永久拒绝，请到应用设置中手动开启';
    }
    return null;
  }

  /// 高精度定位流（移动 3 米才推一次，省电且适合绕地走）
  static Stream<Position> get stream => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      );

  static LatLng toLatLng(Position p) => LatLng(p.latitude, p.longitude);

  static double speedKmh(Position p) => (p.speed < 0 ? 0 : p.speed) * 3.6;
}
