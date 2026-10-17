import 'package:latlong2/latlong.dart';
import '../services/geo_utils.dart';

/// 地块：名称、作物、边界多边形、照片列表
class Parcel {
  final String id;
  String name;
  String crop;
  String notes;
  List<LatLng> boundary;
  List<String> photos; // 相对 photos/ 目录的文件名
  int colorIdx;
  DateTime createdAt;

  Parcel({
    required this.id,
    required this.name,
    this.crop = '',
    this.notes = '',
    List<LatLng>? boundary,
    List<String>? photos,
    this.colorIdx = 0,
    DateTime? createdAt,
  })  : boundary = boundary ?? [],
        photos = photos ?? [],
        createdAt = createdAt ?? DateTime.now();

  double get areaM2 => GeoUtils.polygonArea(boundary);
  double get perimeterM => GeoUtils.perimeter(boundary);
  LatLng get centroid => GeoUtils.centroid(boundary);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'crop': crop,
        'notes': notes,
        'boundary': boundary
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'photos': photos,
        'colorIdx': colorIdx,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Parcel.fromJson(Map<String, dynamic> j) => Parcel(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        crop: (j['crop'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
        boundary: (j['boundary'] as List? ?? [])
            .map((e) =>
                LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
            .toList(),
        photos: (j['photos'] as List? ?? []).cast<String>(),
        colorIdx: (j['colorIdx'] ?? 0) as int,
        createdAt:
            DateTime.tryParse((j['createdAt'] ?? '') as String) ?? DateTime.now(),
      );
}
