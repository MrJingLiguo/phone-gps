import 'package:latlong2/latlong.dart';

/// GPS 轨迹
class Track {
  final String id;
  String name;
  String? parcelId; // 可关联到地块
  String? placeId; // 可关联到地点（第一次去的路线）
  List<LatLng> points;
  DateTime startTime;
  DateTime endTime;
  double distanceM;

  Track({
    required this.id,
    required this.name,
    this.parcelId,
    this.placeId,
    required this.points,
    required this.startTime,
    required this.endTime,
    required this.distanceM,
  });

  Duration get duration => endTime.difference(startTime);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parcelId': parcelId,
        'placeId': placeId,
        'points': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'distanceM': distanceM,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        parcelId: j['parcelId'] as String?,
        placeId: j['placeId'] as String?,
        points: (j['points'] as List? ?? [])
            .map((e) =>
                LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
            .toList(),
        startTime:
            DateTime.tryParse((j['startTime'] ?? '') as String) ?? DateTime.now(),
        endTime:
            DateTime.tryParse((j['endTime'] ?? '') as String) ?? DateTime.now(),
        distanceM: ((j['distanceM'] ?? 0) as num).toDouble(),
      );
}
