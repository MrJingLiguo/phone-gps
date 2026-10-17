import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// 地理计算：距离、面积（亩）、周长、中心点、方位
class GeoUtils {
  static const double _earthR = 6371000.0;

  /// 两点球面距离（米）
  static double distance(LatLng a, LatLng b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthR * math.asin(math.sqrt(s));
  }

  /// 折线总长（米）
  static double pathLength(List<LatLng> pts) {
    double total = 0;
    for (int i = 1; i < pts.length; i++) {
      total += distance(pts[i - 1], pts[i]);
    }
    return total;
  }

  /// 多边形面积（平方米），等距圆柱近似投影后鞋带公式
  static double polygonArea(List<LatLng> pts) {
    if (pts.length < 3) return 0;
    final lat0 = pts.first.latitude;
    final cos0 = math.cos(_rad(lat0));
    final xy = pts
        .map((p) => math.Point(
              p.longitude * 111320.0 * cos0,
              p.latitude * 110540.0,
            ))
        .toList();
    double sum = 0;
    for (int i = 0; i < xy.length; i++) {
      final a = xy[i];
      final b = xy[(i + 1) % xy.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return (sum / 2).abs();
  }

  /// 多边形周长（米）
  static double perimeter(List<LatLng> pts) {
    if (pts.length < 3) return pathLength(pts);
    return pathLength([...pts, pts.first]);
  }

  /// 中心点（各顶点平均，足够用于显示与测距）
  static LatLng centroid(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(0, 0);
    final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(lat, lng);
  }

  /// 从 from 指向 to 的方位角（0-360，北为 0，顺时针）
  static double bearing(LatLng from, LatLng to) {
    final lat1 = _rad(from.latitude);
    final lat2 = _rad(to.latitude);
    final dLng = _rad(to.longitude - from.longitude);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// 射线法：点是否在多边形内（用于点击选中地块）
  static bool pointInPolygon(LatLng pt, List<LatLng> poly) {
    if (poly.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i];
      final b = poly[j];
      if ((a.latitude > pt.latitude) != (b.latitude > pt.latitude) &&
          pt.longitude <
              (b.longitude - a.longitude) *
                      (pt.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// 方位角转中文八方描述
  static String bearingName(double deg) {
    const names = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    final idx = ((deg + 22.5) % 360) ~/ 45;
    return names[idx % 8];
  }

  /// 坐标文本（保留原始 WGS-84，方便抄给别人）
  static String coordText(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';

  /// 距离格式化：m / km
  static String fmtDist(double m) {
    if (m < 1000) return '${m.round()}m';
    return '${(m / 1000).toStringAsFixed(m < 10000 ? 2 : 1)}km';
  }

  /// 面积格式化：平方米 + 亩（1 亩 = 666.67 m²）
  static String fmtArea(double m2) {
    if (m2 < 1) return '0 亩';
    final mu = m2 / 666.6667;
    final muStr = mu >= 100 ? mu.round().toString() : mu.toStringAsFixed(1);
    if (m2 < 100) return '${m2.round()}m² (${muStr}亩)';
    return '$muStr 亩';
  }

  /// 时长格式化
  static String fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}时$m分';
    return '$m分${s.toString().padLeft(2, '0')}秒';
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
