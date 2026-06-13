/// Kolichka — сравни цени на хранителни продукти около теб.
///
/// Flutter mobile application for the Kolichka price comparison platform.
/// Open source under GPLv3 license.
///
/// Run with:
///   flutter run
///
/// Configure API base URL via --dart-define:
///   flutter run --dart-define=API_BASE_URL=https://kolichka.gotvach.com
library;

import 'package:flutter/material.dart';
import 'widgets/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'config.dart';
import 'services/local_store.dart';
import 'screens/home_screen.dart';
import 'services/analytics.dart';

/// Persistent theme mode provider that loads from SharedPreferences and
/// notifies listeners when the user toggles between light / dark / system.
/// Exposed globally so HomeScreen can toggle without dependency injection.
class ThemeProvider extends ChangeNotifier {
  static ThemeProvider? instance;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Load saved preference from disk (call once at startup).
  Future<void> load() async {
    final saved = await LocalStore.themeMode();
    _mode = _fromString(saved);
    notifyListeners();
  }

  /// Cycle: system → light → dark → system …
  void toggle() {
    if (_mode == ThemeMode.system) _mode = ThemeMode.light;
    else if (_mode == ThemeMode.light) _mode = ThemeMode.dark;
    else _mode = ThemeMode.system;
    LocalStore.setThemeMode(_toString(_mode));
    notifyListeners();
  }

  static ThemeMode _fromString(String? v) {
    switch (v) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  static String? _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light: return 'light';
      case ThemeMode.dark: return 'dark';
      case ThemeMode.system: return null;
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final info = await PackageInfo.fromPlatform();
    Config.appVersion = info.version;
    Config.appBuild = info.buildNumber;
  } catch (_) {}
  Analytics.instance.init().then((_) => Analytics.instance.track('app_open'));

  final provider = ThemeProvider();
  ThemeProvider.instance = provider;
  await provider.load();
  runApp(KolichkaApp(provider: provider));
}

class KolichkaApp extends StatelessWidget {
  final ThemeProvider provider;

  const KolichkaApp({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Количка',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: provider.mode,
      builder: (context, child) {
        return ListenableBuilder(
          listenable: provider,
          builder: (context, _) => child!,
        );
      },
      home: const HomeScreen(),
    );
  }
}
