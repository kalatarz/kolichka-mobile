/// FoodBase (foodbase.dev) integration — nutrition scores for products.
///
/// Searches the FoodBase catalog by product name (Bulgarian) and exposes the
/// per-product Nutri-Score / NOVA / Eco-Score plus a macro summary, and builds
/// the public article link (the nutrition-scores page) for a product.
///
/// The API key is provided at BUILD time via `--dart-define=FOODBASE_KEY=…`
/// (sourced from ~/work/secrets/foodbase → $FOODBASE_KEY). It is NEVER committed
/// to source. If no key is compiled in, [enabled] is false and the UI hides the
/// nutrition affordance.
///
/// NOTE (security): a client-embedded key is fine for an internal review build,
/// but for public release the call should be proxied through the Kolichka
/// backend so the key never ships in the APK. See README / TODO.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// API base (versioned) and the public website used for article links.
const String _apiBase = 'https://foodbase.dev/v1';
const String _webBase = 'https://foodbase.dev/products';

/// Compiled-in API key (build-time only, never committed).
const String _foodbaseKey =
    String.fromEnvironment('FOODBASE_KEY', defaultValue: '');

class FoodbaseException implements Exception {
  final String message;
  FoodbaseException(this.message);
  @override
  String toString() => message;
}

/// Per-100g macro summary.
class FoodbaseNutrition {
  final double? energyKcal, proteinsG, carbsG, fatG, sugarsG, fiberG;
  const FoodbaseNutrition({
    this.energyKcal,
    this.proteinsG,
    this.carbsG,
    this.fatG,
    this.sugarsG,
    this.fiberG,
  });

  bool get isEmpty =>
      energyKcal == null &&
      proteinsG == null &&
      carbsG == null &&
      fatG == null &&
      sugarsG == null &&
      fiberG == null;

  static double? _num(dynamic v) => (v is num) ? v.toDouble() : null;

  factory FoodbaseNutrition.fromJson(Map<String, dynamic> j) => FoodbaseNutrition(
        energyKcal: _num(j['energy_kcal']),
        proteinsG: _num(j['proteins_g']),
        carbsG: _num(j['carbs_g']),
        fatG: _num(j['fat_g']),
        sugarsG: _num(j['sugars_g']),
        fiberG: _num(j['fiber_g']),
      );
}

/// A single FoodBase catalog item (subset of the API's FoodItem we render).
class FoodbaseFood {
  final String id;
  final String name;
  final String? brand;
  final String? nutriscore; // a–e
  final int? novaGroup; // 1–4
  final String? ecoscore; // a–e
  final String? imageUrl;
  final FoodbaseNutrition? nutrition;

  const FoodbaseFood({
    required this.id,
    required this.name,
    this.brand,
    this.nutriscore,
    this.novaGroup,
    this.ecoscore,
    this.imageUrl,
    this.nutrition,
  });

  bool get hasAnyScore =>
      (nutriscore != null && nutriscore!.isNotEmpty) ||
      novaGroup != null ||
      (ecoscore != null && ecoscore!.isNotEmpty);

  /// Resolve a display name across the API's several name shapes:
  /// prefer an explicit localized field, then the `name` array (bg first),
  /// falling back to `name_default`.
  static String _displayName(Map<String, dynamic> j) {
    final loc = j['name_localized'];
    if (loc is String && loc.trim().isNotEmpty) return loc.trim();

    String? fromEntry(dynamic e) {
      if (e is String && e.trim().isNotEmpty) return e.trim();
      if (e is Map) {
        for (final k in ['value', 'name', 'text', 'label']) {
          final v = e[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }
      return null;
    }

    final name = j['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    if (name is List && name.isNotEmpty) {
      // Prefer a Bulgarian entry when the array carries language tags.
      for (final e in name) {
        if (e is Map) {
          final lang = (e['lang'] ?? e['language'])?.toString().toLowerCase();
          if (lang == 'bg') {
            final v = fromEntry(e);
            if (v != null) return v;
          }
        }
      }
      for (final e in name) {
        final v = fromEntry(e);
        if (v != null) return v;
      }
    }
    final def = j['name_default'];
    return (def is String && def.trim().isNotEmpty) ? def.trim() : '—';
  }

  factory FoodbaseFood.fromJson(Map<String, dynamic> j) {
    final ns = j['nutrition_summary'];
    return FoodbaseFood(
      id: (j['id'] ?? '').toString(),
      name: _displayName(j),
      brand: (j['brand'] is String && (j['brand'] as String).trim().isNotEmpty)
          ? (j['brand'] as String).trim()
          : null,
      nutriscore: _grade(j['nutriscore']),
      novaGroup: (j['nova_group'] is num) ? (j['nova_group'] as num).toInt() : null,
      ecoscore: _grade(j['ecoscore_grade']),
      imageUrl: (j['image_url'] is String && (j['image_url'] as String).isNotEmpty)
          ? j['image_url'] as String
          : null,
      nutrition: ns is Map<String, dynamic> ? FoodbaseNutrition.fromJson(ns) : null,
    );
  }

  /// Normalize a grade to a single a–e letter (ignore "unknown"/"not-applicable").
  static String? _grade(dynamic v) {
    if (v is! String) return null;
    final s = v.trim().toLowerCase();
    if (s.isEmpty) return null;
    final c = s[0];
    return (c.compareTo('a') >= 0 && c.compareTo('e') <= 0) ? c : null;
  }
}

class FoodbaseService {
  /// True when a key was compiled in — gate the UI on this.
  static bool get enabled => _foodbaseKey.isNotEmpty;

  /// Public article / nutrition-scores link for a product name, e.g.
  /// https://foodbase.dev/products?q=кисело+мляко
  static Uri articleUrl(String query) =>
      Uri.parse('$_webBase?q=${Uri.encodeQueryComponent(query.trim())}');

  /// Search the catalog by name. Returns the top matches (best first).
  Future<List<FoodbaseFood>> search(String query,
      {String lang = 'bg', int limit = 5}) async {
    if (!enabled) throw FoodbaseException('FoodBase не е конфигуриран.');
    final q = query.trim();
    if (q.isEmpty) return const [];

    final uri = Uri.parse('$_apiBase/foods/search').replace(queryParameters: {
      'q': q,
      'lang': lang,
      'limit': '$limit',
    });

    late final http.Response res;
    try {
      res = await http
          .get(uri, headers: {'X-API-Key': _foodbaseKey, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw FoodbaseException('Няма връзка с FoodBase. Провери интернет.');
    }

    if (res.statusCode == 429) {
      throw FoodbaseException('Дневният лимит към FoodBase е достигнат.');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw FoodbaseException('Невалиден ключ за FoodBase.');
    }
    if (res.statusCode != 200) {
      throw FoodbaseException('FoodBase грешка (${res.statusCode}).');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw FoodbaseException('Неочакван отговор от FoodBase.');
    }
    // The API returns {error, message} with a 200 on some quota states.
    if (body['error'] != null && body['data'] == null) {
      throw FoodbaseException(body['message']?.toString() ?? body['error'].toString());
    }
    final data = (body['data'] as List?) ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(FoodbaseFood.fromJson)
        .toList();
  }
}
