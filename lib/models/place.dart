import 'package:latlong2/latlong.dart';

/// 地点：厂家、亲戚朋友家、收藏点等 —— 一个坐标点 + 照片 + 到访路线
class Place {
  final String id;
  String name;
  String category; // 厂家 / 亲戚家 / 朋友家 / 收藏点 …（自由填写）
  String notes;
  LatLng position; // WGS-84
  List<String> photos;
  DateTime createdAt;

  Place({
    required this.id,
    required this.name,
    this.category = '',
    this.notes = '',
    required this.position,
    List<String>? photos,
    DateTime? createdAt,
  })  : photos = photos ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'notes': notes,
        'lat': position.latitude,
        'lng': position.longitude,
        'photos': photos,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        category: (j['category'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
        position: LatLng((j['lat'] as num).toDouble(),
            (j['lng'] as num).toDouble()),
        photos: (j['photos'] as List? ?? []).cast<String>(),
        createdAt:
            DateTime.tryParse((j['createdAt'] ?? '') as String) ??
                DateTime.now(),
      );
}
