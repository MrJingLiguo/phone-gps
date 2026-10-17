import '../models/track.dart';

/// 轨迹导出 GPX 1.1（WGS-84 标准格式，奥维/两步路/六只脚等可导入）
String trackToGpx(Track t) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  sb.writeln(
      '<gpx version="1.1" creator="地块管家" xmlns="http://www.topografix.com/GPX/1/1">');
  sb.writeln('  <metadata>');
  sb.writeln('    <name>${esc(t.name)}</name>');
  sb.writeln(
      '    <time>${t.startTime.toUtc().toIso8601String()}</time>');
  sb.writeln('  </metadata>');
  sb.writeln('  <trk>');
  sb.writeln('    <name>${esc(t.name)}</name>');
  sb.writeln('    <trkseg>');
  for (final p in t.points) {
    sb.writeln(
        '      <trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>');
  }
  sb.writeln('    </trkseg>');
  sb.writeln('  </trk>');
  sb.writeln('</gpx>');
  return sb.toString();
}
