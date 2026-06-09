/// Store model.
/// Corresponds to items in GET /api/stores/nearby response.
class Store {
  final int id;
  final String address;
  final String chainSlug;
  final String chainName;
  final double lat;
  final double lng;
  final int? distM;

  const Store({
    required this.id,
    required this.address,
    required this.chainSlug,
    required this.chainName,
    required this.lat,
    required this.lng,
    this.distM,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: (json['id'] as num?)?.toInt() ?? 0,
      address: json['address'] as String? ?? '',
      chainSlug: json['chain_slug'] as String? ?? '',
      chainName: json['chain_name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      distM: json['dist_m'] != null ? (json['dist_m'] as num).toInt() : null,
    );
  }

  /// Distance formatted as human-readable string.
  String? get distanceText {
    if (distM == null) return null;
    if (distM! < 1000) {
      return '${distM} m';
    }
    return '${(distM! / 1000).toStringAsFixed(1)} km';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Store && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
