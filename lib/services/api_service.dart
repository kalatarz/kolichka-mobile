/// HTTP client wrapper for the Kolichka public API.
///
/// All endpoints are public and do not require authentication.
/// This service handles request building, error parsing, and retry logic.
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/category.dart';
import '../models/store.dart';
import '../models/geocode_result.dart';
import '../models/compare_result.dart';
import '../models/basket_result.dart';
import '../models/promotion_result.dart';

/// Broad category of an API failure, so callers can show a specific,
/// user-friendly message (see [friendlyError]) instead of a raw exception.
enum ApiErrorKind {
  network, // offline / DNS / connection refused
  timeout, // request took too long
  notFound, // 404
  rateLimited, // 429
  server, // 5xx
  badResponse, // unexpected status / invalid JSON
  unknown,
}

/// Exceptions thrown by [ApiService].
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final ApiErrorKind kind;

  const ApiException(this.message, {this.statusCode, this.kind = ApiErrorKind.unknown});

  @override
  String toString() => 'ApiException[$statusCode/${kind.name}]: $message';
}

/// Maps any thrown error to a short Bulgarian message safe to show a user.
/// Callers should render this rather than `e.toString()` (which leaks English
/// internals like "SocketException" / "ApiException[500]").
String friendlyError(Object e) {
  if (e is ApiException) {
    switch (e.kind) {
      case ApiErrorKind.network:
        return 'Няма връзка с интернет. Провери мрежата и опитай пак.';
      case ApiErrorKind.timeout:
        return 'Сървърът не отговори навреме. Опитай пак.';
      case ApiErrorKind.rateLimited:
        return 'Твърде много заявки. Изчакай малко и опитай пак.';
      case ApiErrorKind.server:
        return 'Проблем със сървъра. Опитай пак по-късно.';
      case ApiErrorKind.notFound:
        return 'Не е намерено.';
      case ApiErrorKind.badResponse:
        return 'Неочакван отговор от сървъра. Опитай пак.';
      case ApiErrorKind.unknown:
        return 'Възникна грешка. Опитай пак.';
    }
  }
  if (e is TimeoutException) return 'Сървърът не отговори навреме. Опитай пак.';
  return 'Няма връзка с интернет. Провери мрежата и опитай пак.';
}

/// Classifies a low-level (non-HTTP-status) failure — a thrown timeout vs. any
/// other connectivity error — into a typed [ApiException].
ApiException _netError(Object e) {
  if (e is TimeoutException) {
    return const ApiException('Request timed out', kind: ApiErrorKind.timeout);
  }
  return ApiException('Network error: $e', kind: ApiErrorKind.network);
}

class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// GET request with JSON parsing and error handling.
  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? params}) async {
    final uri = Uri.parse('${Config.apiBaseUrl}$path').replace(queryParameters: params);
    try {
      final response = await _client.get(uri, headers: {'User-Agent': Config.userAgent}).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 500) {
        throw ApiException('Server error (${response.statusCode})',
            statusCode: response.statusCode, kind: ApiErrorKind.server);
      }
      if (response.statusCode == 429) {
        throw const ApiException('Rate limited. Please wait and try again.',
            statusCode: 429, kind: ApiErrorKind.rateLimited);
      }
      if (response.statusCode != 200) {
        throw ApiException('Unexpected status ${response.statusCode}',
            statusCode: response.statusCode, kind: ApiErrorKind.badResponse);
      }
      if (response.body.isEmpty) return {};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const ApiException('Invalid JSON response', kind: ApiErrorKind.badResponse);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _netError(e);
    }
  }

  /// GET request that returns a list at the top level.
  Future<List<dynamic>> _getList(String path, {Map<String, String>? params}) async {
    final uri = Uri.parse('${Config.apiBaseUrl}$path').replace(queryParameters: params);
    try {
      final response = await _client.get(uri, headers: {'User-Agent': Config.userAgent}).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 500) {
        throw ApiException('Server error (${response.statusCode})',
            statusCode: response.statusCode, kind: ApiErrorKind.server);
      }
      if (response.statusCode == 429) {
        throw const ApiException('Rate limited. Please wait and try again.',
            statusCode: 429, kind: ApiErrorKind.rateLimited);
      }
      if (response.statusCode != 200) {
        throw ApiException('Unexpected status ${response.statusCode}',
            statusCode: response.statusCode, kind: ApiErrorKind.badResponse);
      }
      if (response.body.isEmpty) return [];
      final decoded = jsonDecode(response.body);
      if (decoded is List) return decoded;
      throw const ApiException('Invalid JSON response', kind: ApiErrorKind.badResponse);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _netError(e);
    }
  }

  // ---- Public endpoints ----

  /// GET /api/categories
  Future<List<Category>> getCategories() async {
    final list = await _getList('/api/categories');
    return list.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /api/iploc — approximate location from the client IP via server GeoIP
  /// (MaxMind). Last-resort fallback when device GPS is off/denied. Returns null
  /// if the server can't resolve the IP.
  Future<GeocodeResult?> iploc() async {
    try {
      final body = await _get('/api/iploc');
      final lat = (body['lat'] as num?)?.toDouble();
      final lng = (body['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return GeocodeResult(lat: lat, lng: lng, display: (body['label'] as String?) ?? 'твоят регион');
    } catch (_) {
      return null;
    }
  }

  /// GET /api/geocode?q=...
  Future<List<GeocodeResult>> geocode(String query) async {
    final list = await _getList('/api/geocode', params: {'q': query});
    return list.map((e) => GeocodeResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Reverse-geocode coords → a human area name (suburb/city), in Bulgarian.
  /// Goes through OUR server (/api/reverse), which proxies Nominatim with caching +
  /// a stable egress IP. Calling Nominatim directly from each device violated their
  /// usage policy and got rate-limited (429) at scale, so the app fell back to the
  /// generic "Моето местоположение" label. Returns null on failure.
  Future<String?> reverseArea(double lat, double lng) async {
    try {
      final body = await _get('/api/reverse', params: {'lat': _coord(lat), 'lng': _coord(lng)});
      final a = body['area'];
      return (a is String && a.trim().isNotEmpty) ? a.trim() : null;
    } catch (_) {
      return null;
    }
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
        headers: {'Content-Type': 'application/json', 'User-Agent': Config.userAgent},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 201) {
        _throwForStatus(response.statusCode, 'Feedback submission failed');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _netError(e);
    }
  }

  /// Shared family basket (cross-device synced checklist). Items are
  /// [{'n': name, 'b': bought}].
  Future<Map<String, dynamic>> famCreate(List<Map<String, dynamic>> items) async {
    final uri = Uri.parse('${Config.apiBaseUrl}/api/fambasket');
    try {
      final resp = await _client
          .post(uri,
              headers: {'Content-Type': 'application/json', 'User-Agent': Config.userAgent},
              body: jsonEncode({'items': items}))
          .timeout(const Duration(seconds: 15));
      _throwForStatus(resp.statusCode, 'Create failed');
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _netError(e);
    }
  }

  /// Returns null if the code does not exist (404).
  Future<Map<String, dynamic>?> famGet(String code) async {
    final uri = Uri.parse('${Config.apiBaseUrl}/api/fambasket/$code');
    try {
      final resp = await _client
          .get(uri, headers: {'User-Agent': Config.userAgent})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 404) return null;
      _throwForStatus(resp.statusCode, 'Get failed');
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _netError(e);
    }
  }

  Future<void> famPut(String code, List<Map<String, dynamic>> items) async {
    final uri = Uri.parse('${Config.apiBaseUrl}/api/fambasket/$code');
    try {
      final resp = await _client
          .put(uri,
              headers: {'Content-Type': 'application/json', 'User-Agent': Config.userAgent},
              body: jsonEncode({'items': items}))
          .timeout(const Duration(seconds: 15));
      _throwForStatus(resp.statusCode, 'Sync failed');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _netError(e);
    }
  }

  /// Throws a typed [ApiException] for a non-200 status (no-op on 200).
  void _throwForStatus(int status, String label) {
    if (status == 200) return;
    if (status >= 500) {
      throw ApiException('$label ($status)', statusCode: status, kind: ApiErrorKind.server);
    }
    if (status == 429) {
      throw ApiException('$label ($status)', statusCode: status, kind: ApiErrorKind.rateLimited);
    }
    throw ApiException('$label ($status)', statusCode: status, kind: ApiErrorKind.badResponse);
  }

  /// POST /api/subscribe — weekly-offers email (server sends a confirm mail).
  Future<void> subscribe({required String email, double? lat, double? lng}) async {
    final uri = Uri.parse('${Config.apiBaseUrl}/api/subscribe');
    final body = <String, dynamic>{'email': email};
    if (lat != null) body['lat'] = _coord(lat);
    if (lng != null) body['lng'] = _coord(lng);
    final response = await _client
        .post(uri,
            headers: {'Content-Type': 'application/json', 'User-Agent': Config.userAgent},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException('Subscribe failed (${response.statusCode})',
          statusCode: response.statusCode);
    }
  }

  String _coord(double value) => value.toStringAsFixed(6);

  void close() {
    _client.close();
  }
}
