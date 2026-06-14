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
/// notifies listeners when the user toggles between light / dark.
class ThemeProvider extends ChangeNotifier {
  static ThemeProvider? instance;
  bool _isDark = false;

  bool get isDark => _isDark;

  /// Load saved preference from disk (call once at startup).
  Future<void> load() async {
    final saved = await LocalStore.themeMode();
    _isDark = saved == 'dark';
    notifyListeners();
  }

  /// Toggle between light and dark.
  void toggle() {
    _isDark = !_isDark;
    LocalStore.setThemeMode(_isDark ? 'dark' : 'light');
    notifyListeners();
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

class KolichkaApp extends StatefulWidget {
  final ThemeProvider provider;

  const KolichkaApp({super.key, required this.provider});

  @override
  State<KolichkaApp> createState() => _KolichkaAppState();
}

class _KolichkaAppState extends State<KolichkaApp> {
  late bool _isDark;

  @override
  void initState() {
    super.initState();
    _isDark = widget.provider.isDark;
    widget.provider.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        _isDark = widget.provider.isDark;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Количка',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}
