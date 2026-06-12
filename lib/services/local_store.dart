/// Local persistence for the basket and favorites (SharedPreferences-backed).
///
/// Both are simple ordered lists of product names/queries, deduplicated
/// case-insensitively. Keys mirror the web app's localStorage naming.
library;

import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  LocalStore._();

  static const _basketKey = 'kolichka.basket';
  static const _favKey = 'kolichka.favorites';

  static Future<List<String>> _getList(String key) async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(key) ?? <String>[];
  }

  static Future<void> _setList(String key, List<String> v) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(key, v);
  }

  static bool _contains(List<String> list, String item) {
    final t = item.trim().toLowerCase();
    return list.any((e) => e.trim().toLowerCase() == t);
  }

  // ---- Basket ----

  static Future<List<String>> basket() => _getList(_basketKey);

  static Future<int> basketCount() async => (await _getList(_basketKey)).length;

  /// Adds an item to the basket. Returns true if added, false if it was
  /// already present (or blank).
  static Future<bool> addToBasket(String item) async {
    final t = item.trim();
    if (t.isEmpty) return false;
    final list = await _getList(_basketKey);
    if (_contains(list, t)) return false;
    list.add(t);
    await _setList(_basketKey, list);
    return true;
  }

  static Future<void> removeFromBasket(String item) async {
    final t = item.trim().toLowerCase();
    final list = await _getList(_basketKey);
    list.removeWhere((e) => e.trim().toLowerCase() == t);
    await _setList(_basketKey, list);
  }

  static Future<void> setBasket(List<String> items) => _setList(_basketKey, items);

  static Future<void> clearBasket() => _setList(_basketKey, <String>[]);

  // ---- Favorites ----

  static Future<List<String>> favorites() => _getList(_favKey);

  static Future<int> favoritesCount() async => (await _getList(_favKey)).length;

  static Future<bool> isFavorite(String item) async =>
      _contains(await _getList(_favKey), item);

  /// Toggles favorite state. Returns the NEW state (true = now a favorite).
  static Future<bool> toggleFavorite(String item) async {
    final t = item.trim();
    if (t.isEmpty) return false;
    final list = await _getList(_favKey);
    if (_contains(list, t)) {
      list.removeWhere((e) => e.trim().toLowerCase() == t.toLowerCase());
      await _setList(_favKey, list);
      return false;
    }
    list.add(t);
    await _setList(_favKey, list);
    return true;
  }

  static Future<void> removeFavorite(String item) async {
    final t = item.trim().toLowerCase();
    final list = await _getList(_favKey);
    list.removeWhere((e) => e.trim().toLowerCase() == t);
    await _setList(_favKey, list);
  }
}
