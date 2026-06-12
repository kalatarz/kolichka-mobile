/// Anonymous, privacy-respecting product analytics → self-hosted Umami.
///
/// OFF by default. It only sends data when BOTH are passed at build time:
///   --dart-define=ANALYTICS_ENABLED=true
///   --dart-define=UMAMI_WEBSITE_ID=<uuid>
/// so anyone building from the public OSS source sends nothing, and only the
/// official Google Play build is wired to the Umami instance.
///
/// No PII: a random per-install id (not the device id, no account, no search
/// terms) lets us measure the onboarding funnel and returning users. Actual
/// installs/uninstalls/retention cohorts come from Google Play Console.
library;

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  // ---- build-time configuration ----
  static const bool _flag =
      bool.fromEnvironment('ANALYTICS_ENABLED', defaultValue: false);
  static const String _websiteId =
      String.fromEnvironment('UMAMI_WEBSITE_ID', defaultValue: '');
  static const String _host = String.fromEnvironment(
      'UMAMI_HOST', defaultValue: 'https://analytics.gotvach.com');
  static const String _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  static const _idKey = 'kolichka.analytics.id';
  static const _cohortKey = 'kolichka.analytics.cohort';

  final http.Client _client = http.Client();
  String? _installId;
  String? _cohort; // install date, YYYY-MM-DD
  String? _cache; // Umami session token, reused within a run
  bool _ready = false;

  bool get enabled => _flag && _websiteId.isNotEmpty;

  /// Resolve (or create) the anonymous install id. Fires `first_open` once.
  Future<void> init() async {
    if (!enabled || _ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_idKey);
      var cohort = prefs.getString(_cohortKey);
      final isFirst = id == null;
      if (isFirst) {
        id = _randomId();
        cohort = _todayIso();
        await prefs.setString(_idKey, id);
        await prefs.setString(_cohortKey, cohort);
      }
      _installId = id;
      _cohort = cohort ?? _todayIso();
      _ready = true;
      if (isFirst) _send('first_open', null);
    } catch (_) {
      // never let analytics break startup
    }
  }

  /// Fire-and-forget event. Never throws, never blocks the UI.
  void track(String event, [Map<String, dynamic>? props]) {
    if (!enabled) return;
    _send(event, props);
  }

  Future<void> _send(String event, Map<String, dynamic>? props) async {
    if (!enabled) return;
    try {
      if (!_ready) await init();
      final data = <String, dynamic>{
        'install_id': _installId,
        'cohort': _cohort,
        'app_version': Config.appVersion,
        'build': Config.appBuild,
        'platform': 'android',
        if (props != null) ...props,
      };
      final body = jsonEncode({
        'type': 'event',
        'payload': {
          'website': _websiteId,
          'hostname': 'app.kolichka.gotvach.com',
          'language': 'bg-BG',
          'url': '/mobile',
          'name': event,
          'data': data,
        },
      });
      final headers = <String, String>{
        'Content-Type': 'application/json',
        // A generic Android UA so Umami categorises OS/device sensibly.
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; Kolichka) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/Mobile Safari/537.36',
        if (_cache != null) 'Cache': _cache!,
      };
      final resp = await _client
          .post(Uri.parse('$_host/api/send'), headers: headers, body: body)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['cache'] is String) _cache = j['cache'] as String;
        } catch (_) {}
      }
    } catch (_) {
      // Analytics must never affect the app.
    }
  }

  String _todayIso() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  String _randomId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }
}
