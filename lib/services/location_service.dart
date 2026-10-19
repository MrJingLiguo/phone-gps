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

  /// 高精度定位流：1Hz 连续输出，由调用方按 accuracy 过滤（适合边界采集）
  static Stream<Position> get stream => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      );

  /// 定位质量门槛（米，越小越好）：Position.accuracy 是 68% 置信半径
  static const double maxBoundaryAccuracy = 6.0;
  static const double maxTrackAccuracy = 10.0;

  static LatLng toLatLng(Position p) => LatLng(p.latitude, p.longitude);

  static double speedKmh(Position p) => (p.speed < 0 ? 0 : p.speed) * 3.6;
}
