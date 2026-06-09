/// HTTP client wrapper for the Kolichka public API.
///
/// All endpoints are public and do not require authentication.
/// This service handles request building, error parsing, and retry logic.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/category.dart';
import '../models/store.dart';
import '../models/geocode_result.dart';
import '../models/compare_result.dart';
import '../models/basket_result.dart';
import '../models/promotion_result.dart';

/// Exceptions thrown by [ApiService].
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException[$statusCode]: $message';
}

class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// GET request with JSON parsing and error handling.
  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? params}) async {
    final uri = Uri.parse('${Config.apiBaseUrl}$path').replace(queryParameters: params);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 500) {
        throw ApiException('Server error (${response.statusCode})', statusCode: response.statusCode);
      }
      if (response.statusCode == 429) {
        throw const ApiException('Rate limited. Please wait and try again.');
      }
      if (response.statusCode != 200) {
        throw ApiException('Unexpected status ${response.statusCode}');
      }
      if (response.body.isEmpty) return {};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw ApiException('Invalid JSON response');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  /// GET request that returns a list at the top level.
  Future<List<dynamic>> _getList(String path, {Map<String, String>? params}) async {
    final uri = Uri.parse('${Config.apiBaseUrl}$path').replace(queryParameters: params);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 500) {
        throw ApiException('Server error (${response.statusCode})', statusCode: response.statusCode);
      }
      if (response.statusCode == 429) {
        throw const ApiException('Rate limited. Please wait and try again.');
      }
      if (response.statusCode != 200) {
        throw ApiException('Unexpected status ${response.statusCode}');
      }
      if (response.body.isEmpty) return [];
      final decoded = jsonDecode(response.body);
      if (decoded is List) return decoded;
      throw ApiException('Invalid JSON response');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  // ---- Public endpoints ----

  /// GET /api/categories
  Future<List<Category>> getCategories() async {
    final list = await _getList('/api/categories');
    return list.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/geocode?q=...
  Future<List<GeocodeResult>> geocode(String query) async {
    final list = await _getList('/api/geocode', params: {'q': query});
    return list.map((e) => GeocodeResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/stores/nearby?lat=&lng=&radius_km=
  Future<List<Store>> getNearbyStores(double lat, double lng, {double radiusKm = 3.0}) async {
    final body = await _get('/api/stores/nearby', params: {
      'lat': _coord(lat),
      'lng': _coord(lng),
      'radius_km': _coord(radiusKm),
    });
    final storesJson = body['stores'] as List<dynamic>? ?? [];
    return storesJson.map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/compare?q=&lat=&lng=&radius_km=...
  Future<CompareResponse> compare({
    required String query,
    required double lat,
    required double lng,
    double radiusKm = 3.0,
    int minChains = 2,
    int limit = 50,
  }) async {
    final body = await _get('/api/compare', params: {
      'q': query,
      'lat': _coord(lat),
      'lng': _coord(lng),
      'radius_km': _coord(radiusKm),
      'min_chains': minChains.toString(),
      'limit': limit.toString(),
    });
    return CompareResponse.fromJson(body);
  }

  /// GET /api/basket?items=&lat=&lng=&radius_km=
  Future<BasketResponse> basket({
    required List<String> items,
    required double lat,
    required double lng,
    double radiusKm = 3.0,
  }) async {
    final body = await _get('/api/basket', params: {
      'items': items.join(','),
      'lat': _coord(lat),
      'lng': _coord(lng),
      'radius_km': _coord(radiusKm),
    });
    return BasketResponse.fromJson(body);
  }

  /// GET /api/promotions?lat=&lng=&radius_km=...
  Future<PromotionsResponse> promotions({
    required double lat,
    required double lng,
    double radiusKm = 3.0,
    int perChain = 15,
    String? categories,
    String? q,
    int maxStaleDays = 2,
  }) async {
    final params = {
      'lat': _coord(lat),
      'lng': _coord(lng),
      'radius_km': _coord(radiusKm),
      'per_chain': perChain.toString(),
      'max_stale_days': maxStaleDays.toString(),
    };
    if (categories != null && categories.isNotEmpty) params['categories'] = categories;
    if (q != null && q.isNotEmpty) params['q'] = q;
    final body = await _get('/api/promotions', params: params);
    return PromotionsResponse.fromJson(body);
  }

  /// GET /api/canonical/:id?lat=&lng=&radius_km=
  Future<Map<String, dynamic>> canonicalProduct(int id, {
    double lat = 0,
    double lng = 0,
    double radiusKm = 1.0,
  }) async {
    return await _get('/api/canonical/$id', params: {
      'lat': _coord(lat),
      'lng': _coord(lng),
      'radius_km': _coord(radiusKm),
    });
  }

  /// GET /api/nearest?q=&lat=&lng=
  Future<Map<String, dynamic>> nearest({
    required String query,
    required double lat,
    required double lng,
  }) async {
    return await _get('/api/nearest', params: {
      'q': query,
      'lat': _coord(lat),
      'lng': _coord(lng),
    });
  }

  /// GET /api/stats
  Future<Map<String, dynamic>> stats() async {
    return await _get('/api/stats');
  }

  /// POST /api/feedback
  Future<void> submitFeedback({
    required String category,
    int? rating,
    String? subject,
    String? comment,
    String? url,
    Map<String, dynamic>? context,
  }) async {
    final uri = Uri.parse('${Config.apiBaseUrl}/api/feedback');
    final body = <String, dynamic>{'category': category};
    if (rating != null) body['rating'] = rating;
    if (subject != null) body['subject'] = subject;
    if (comment != null) body['comment'] = comment;
    if (url != null) body['url'] = url;
    if (context != null) body['context'] = context;

    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw ApiException('Feedback submission failed (${response.statusCode})');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to submit feedback: $e');
    }
  }

  String _coord(double value) => value.toStringAsFixed(6);

  void close() {
    _client.close();
  }
}
