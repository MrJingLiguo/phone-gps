import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// WGS-84(GPS) ↔ GCJ-02(高德/火星坐标) 转换
///
/// 数据层统一存 WGS-84；仅在与高德瓦片交互（显示/点选/导航）时转换。
/// 标准偏移算法，国内偏差 <1m，迭代反算偏差 <0.1m。
class Gcj {
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;

  /// WGS-84 → GCJ-02（显示用）
  static LatLng of(LatLng p) {
    if (_outOfChina(p.latitude, p.longitude)) return p;
    final d = _delta(p.latitude, p.longitude);
    return LatLng(p.latitude + d.$1, p.longitude + d.$2);
  }

  /// GCJ-02 → WGS-84（点选地图入库用，迭代反算）
  static LatLng toWgs(LatLng p) {
    if (_outOfChina(p.latitude, p.longitude)) return p;
    var wgs = LatLng(p.latitude - _delta(p.latitude, p.longitude).$1,
        p.longitude - _delta(p.latitude, p.longitude).$2);
    for (int i = 0; i < 3; i++) {
      final d = _delta(wgs.latitude, wgs.longitude);
      final gcj = LatLng(wgs.latitude + d.$1, wgs.longitude + d.$2);
      wgs = LatLng(
        wgs.latitude - (gcj.latitude - p.latitude),
        wgs.longitude - (gcj.longitude - p.longitude),
      );
    }
    return wgs;
  }

  /// 整条折线/多边形转 GCJ-02
  static List<LatLng> path(List<LatLng> pts) => pts.map(of).toList();

  static (double, double) _delta(double lat, double lng) {
    double dLat = _tLat(lng - 105.0, lat - 35.0);
    double dLng = _tLng(lng - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * math.pi;
    double magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
    return (dLat, dLng);
  }

  static bool _outOfChina(double lat, double lng) =>
      lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;

  static double _tLat(double x, double y) {
    double ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (160.0 * math.sin(y / 12.0 * math.pi) +
            320 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  static double _tLng(double x, double y) {
    double ret = 300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (150.0 * math.sin(x / 12.0 * math.pi) +
            300.0 * math.sin(x / 30.0 * math.pi)) *
        2.0 /
        3.0;
    return ret;
  }
}
