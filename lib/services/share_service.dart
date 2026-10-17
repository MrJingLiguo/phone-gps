import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';
import '../models/parcel.dart';
import '../models/place.dart';
import '../models/track.dart';
import 'gcj02.dart';
import 'geo_utils.dart';
import 'gpx.dart';

/// 分享功能：系统分享面板 → 微信/QQ/短信等，接收方点链接可用高德地图打开
class ShareService {
  /// 高德网页标记链接：微信里可直接看，浏览器/手机上可跳高德 App
  static String amapLink(LatLng wgs, String name) {
    final c = Gcj.of(wgs);
    final lng = c.longitude.toStringAsFixed(6);
    final lat = c.latitude.toStringAsFixed(6);
    return 'https://uri.amap.com/marker?position=$lng,$lat'
        '&name=${Uri.encodeComponent(name)}&src=fieldmap';
  }

  static Future<void> shareParcel(Parcel p) async {
    final text = '【地块管家】📍 ${p.name}\n'
        '${p.crop.isEmpty ? '' : '作物：${p.crop}\n'}'
        '面积：${GeoUtils.fmtArea(p.areaM2)}'
        '${p.notes.isEmpty ? '' : '\n备注：${p.notes}'}\n'
        '👉 用高德地图打开：${amapLink(p.centroid, p.name)}';
    await Share.share(text);
  }

  static Future<void> sharePlace(Place p) async {
    final text = '【地块管家】📍 ${p.name}'
        '${p.category.isEmpty ? '' : '（${p.category}）'}\n'
        '${p.notes.isEmpty ? '' : '${p.notes}\n'}'
        '👉 用高德地图打开：${amapLink(p.position, p.name)}';
    await Share.share(text);
  }

  /// 轨迹：GPX 文件 + 起点高德链接
  static Future<void> shareTrack(Track t) async {
    if (t.points.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final safe = t.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final f = File('${dir.path}/$safe.gpx');
    await f.writeAsString(trackToGpx(t));
    final text = '【地块管家】🛣️ ${t.name}\n'
        '距离 ${GeoUtils.fmtDist(t.distanceM)} · '
        '时长 ${GeoUtils.fmtDuration(t.duration)}\n'
        '起点👉 用高德地图打开：${amapLink(t.points.first, t.name)}\n'
        '（附件 GPX 文件可用奥维互动地图、两步路等导入查看完整轨迹）';
    await Share.shareXFiles([XFile(f.path)], text: text);
  }

  /// 地图截图分享：把 RepaintBoundary 里的地图存成 PNG 发出去
  static Future<void> shareMapImage(
      GlobalKey boundaryKey, String text) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final dir = await getTemporaryDirectory();
    final f = File(
        '${dir.path}/map_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(byteData.buffer.asUint8List());
    await Share.shareXFiles([XFile(f.path)], text: text);
  }
}
