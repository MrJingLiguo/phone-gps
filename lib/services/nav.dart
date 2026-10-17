import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'gcj02.dart';

/// 打开外部地图导航。国产 ROM 常见坑：
/// 1) Android 11+ 包可见性限制 —— manifest 需声明 <queries>，否则 canLaunchUrl 误报 false
/// 2) 很多国产手机没有 geo: scheme 处理器 —— 高德要用自家 amapuri:// scheme
/// 按优先级尝试：高德导航 → 高德查看 → geo: → 高德网页版（浏览器兜底）
Future<void> openNavigation(
    BuildContext context, String name, LatLng wgs) async {
  final c = Gcj.of(wgs);
  final lat = c.latitude.toStringAsFixed(6);
  final lng = c.longitude.toStringAsFixed(6);
  final n = Uri.encodeComponent(name);

  final targets = <Uri>[
    Uri.parse(
        'amapuri://route/plan/?dlat=$lat&dlon=$lng&dname=$n&dev=0&t=0'),
    Uri.parse(
        'androidamap://viewMap?sourceApplication=fieldmap&poiname=$n&lat=$lat&lon=$lng&dev=0'),
    Uri.parse('geo:$lat,$lng?q=$lat,$lng($n)'),
    Uri.parse('https://uri.amap.com/marker?position=$lng,$lat&name=$n'),
  ];

  for (final u in targets) {
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // 换下一个
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开地图应用，请确认已安装高德地图')));
  }
}
