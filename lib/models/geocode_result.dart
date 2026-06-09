/// Models for the /api/geocode endpoint response.

class GeocodeResult {
  final double lat;
  final double lng;
  final String display;

  const GeocodeResult({
    required this.lat,
    required this.lng,
    required this.display,
  });

  factory GeocodeResult.fromJson(Map<String, dynamic> json) {
    return GeocodeResult(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      display: json['display'] as String? ?? '',
    );
  }
}
