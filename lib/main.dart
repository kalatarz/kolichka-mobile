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
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KolichkaApp());
}

class KolichkaApp extends StatelessWidget {
  const KolichkaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Количка',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
