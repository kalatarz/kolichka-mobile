/// Local persistence for the basket and favorites (SharedPreferences-backed).
///
/// Both are simple ordered lists of product names/queries, deduplicated
/// case-insensitively. Keys mirror the web app's localStorage naming.
library;

import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  LocalStore._();

  static const _basketKey = 'kolichka.basket';
  static const _boughtKey = 'kolichka.basket.bought';
  static const _favKey = 'kolichka.favorites';
  static const _famKey = 'kolichka.fam.code';
  static const _themeModeKey = 'kolichka.theme.mode';
  static const _subDoneKey = 'kolichka.sub.done';
  static const _subPromptedKey = 'kolichka.sub.promptedAt';
  static const _firstSeenKey = 'kolichka.firstSeenAt';
  static const _launchCountKey = 'kolichka.launchCount';

  // ---- App engagement (first-seen + session count) ----
  /// Records the first-launch timestamp (once) and increments the launch
  /// counter. Returns the new launch count. Call exactly once per app start.
  static Future<int> bumpLaunch() async {
    final p = await SharedPreferences.getInstance();
    if ((p.getInt(_firstSeenKey) ?? 0) == 0) {
      await p.setInt(_firstSeenKey, DateTime.now().millisecondsSinceEpoch);
    }
    final n = (p.getInt(_launchCountKey) ?? 0) + 1;
    await p.setInt(_launchCountKey, n);
    return n;
  }

  /// Epoch ms when the app was first opened (0 if never recorded yet).
  static Future<int> firstSeenAt() async =>
      (await SharedPreferences.getInstance()).getInt(_firstSeenKey) ?? 0;

  /// Number of times the app has been launched.
  static Future<int> launchCount() async =>
      (await SharedPreferences.getInstance()).getInt(_launchCountKey) ?? 0;

  // ---- Email-subscription nudge state ----
  /// True once the user has submitted the subscribe form (don't nag again).
  static Future<bool> subscribeDone() async =>
      (await SharedPreferences.getInstance()).getBool(_subDoneKey) ?? false;
  static Future<void> setSubscribeDone() async =>
      (await SharedPreferences.getInstance()).setBool(_subDoneKey, true);
  /// Epoch ms of the last auto-prompt (0 if never), for cool-down.
  static Future<int> subscribePromptedAt() async =>
      (await SharedPreferences.getInstance()).getInt(_subPromptedKey) ?? 0;
  static Future<void> markSubscribePrompted(int epochMs) async =>
      (await SharedPreferences.getInstance()).setInt(_subPromptedKey, epochMs);

  // ---- Feedback / rating prompt (after positive engagement) ----
  static const _feedbackDoneKey = 'kolichka.feedback.done';
  static const _searchWinsKey = 'kolichka.search.wins';
  /// True once the rating sheet has been auto-prompted (never auto-nag again).
  static Future<bool> feedbackPromptDone() async =>
      (await SharedPreferences.getInstance()).getBool(_feedbackDoneKey) ?? false;
  static Future<void> setFeedbackPromptDone() async =>
      (await SharedPreferences.getInstance()).setBool(_feedbackDoneKey, true);
  /// Count of searches that returned results (a "good" experience). Returns new total.
  static Future<int> bumpSearchWins() async {
    final p = await SharedPreferences.getInstance();
    final n = (p.getInt(_searchWinsKey) ?? 0) + 1;
    await p.setInt(_searchWinsKey, n);
    return n;
  }

  // ---- Daily favourite-promo push reminders ----
  static const _notifyKey = 'kolichka.notify.favpromos';
  static Future<bool> notifyEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_notifyKey) ?? false;
  static Future<void> setNotifyEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_notifyKey, v);

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
    // drop any "bought" mark for the removed item
    final bought = await _getList(_boughtKey);
    if (_contains(bought, item)) {
      bought.removeWhere((e) => e.trim().toLowerCase() == t);
      await _setList(_boughtKey, bought);
    }
  }

  static Future<void> setBasket(List<String> items) => _setList(_basketKey, items);

  static Future<void> setBought(List<String> items) => _setList(_boughtKey, items);

  // ---- Shared family-basket code ----
  static Future<String?> famCode() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString(_famKey);
    return (c != null && c.isNotEmpty) ? c : null;
  }

  static Future<void> setFamCode(String code) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_famKey, code);
  }

  static Future<void> clearFamCode() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_famKey);
  }

  static Future<void> clearBasket() async {
    await _setList(_basketKey, <String>[]);
    await _setList(_boughtKey, <String>[]);
  }

  // ---- Basket "bought" checklist state ----

  static Future<List<String>> boughtItems() => _getList(_boughtKey);

  static Future<bool> isBought(String item) async =>
      _contains(await _getList(_boughtKey), item);

  /// Toggle an item's bought/checked state. Returns the NEW state.
  static Future<bool> toggleBought(String item) async {
    final t = item.trim();
    if (t.isEmpty) return false;
    final list = await _getList(_boughtKey);
    if (_contains(list, t)) {
      list.removeWhere((e) => e.trim().toLowerCase() == t.toLowerCase());
      await _setList(_boughtKey, list);
      return false;
    }
    list.add(t);
    await _setList(_boughtKey, list);
    return true;
  }

  // ---- Theme Mode ----

  /// Returns the saved theme mode string: "light", "dark", or null (system).
  static Future<String?> themeMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_themeModeKey);
  }

  /// Saves the theme mode preference.
  static Future<void> setThemeMode(String? mode) async {
    final p = await SharedPreferences.getInstance();
    if (mode == null) {
      await p.remove(_themeModeKey);
    } else {
      await p.setString(_themeModeKey, mode);
    }
  }

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
