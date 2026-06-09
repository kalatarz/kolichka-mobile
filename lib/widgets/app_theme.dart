/// App-wide theme definitions matching the Kolichka web design.
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  /// Primary brand color — green from the web version (#178a5e).
  static const Color primaryGreen = Color(0xFF178A5E);

  /// Accent color for highlights and best prices (#5dd3a8).
  static const Color accentGreen = Color(0xFF5DD3A8);

  /// Warning color for highest prices / stale data (#f0b46a).
  static const Color warnAmber = Color(0xFFF0B46A);

  /// Pink for special highlights (#ff5d8f).
  static const Color pink = Color(0xFFFF5D8F);

  /// Dark background (#0e1116).
  static const Color darkBg = Color(0xFF0E1116);

  /// Dark card surface (#171b22).
  static const Color darkCard = Color(0xFF171B22);

  /// Dark border/line color (#262b34).
  static const Color darkLine = Color(0xFF262B34);

  /// Muted text (#8b94a3).
  static const Color mutedText = Color(0xFF8B94A3);

  /// Primary text on dark (#e8ecf1).
  static const Color primaryTextDark = Color(0xFFE8ECF1);

  /// Light background.
  static const Color lightBg = Color(0xFFF5F7FA);

  /// Light card surface.
  static const Color lightCard = Color(0xFFFFFFFF);

  /// Light border color.
  static const Color lightLine = Color(0xFFE2E6EA);

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBg,
        primaryColor: primaryGreen,
        colorScheme: const ColorScheme.dark(
          primary: primaryGreen,
          secondary: accentGreen,
          surface: darkCard,
          onSurface: primaryTextDark,
          onPrimary: Colors.white,
          error: pink,
        ),
        cardTheme: CardTheme(
          color: darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: darkLine),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: darkBg,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: primaryTextDark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: darkCard,
          selectedItemColor: accentGreen,
          unselectedItemColor: mutedText,
          type: BottomNavigationBarType.fixed,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: darkCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: darkLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: darkLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: accentGreen, width: 2),
          ),
        ),
        dividerTheme: const DividerThemeData(color: darkLine, thickness: 1),
        listTileTheme: const ListTileThemeData(iconColor: mutedText),
      );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: lightBg,
        primaryColor: primaryGreen,
        colorScheme: const ColorScheme.light(
          primary: primaryGreen,
          secondary: accentGreen,
          surface: lightCard,
          onSurface: Colors.black87,
          onPrimary: Colors.white,
          error: pink,
        ),
        cardTheme: CardTheme(
          color: lightCard,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: lightLine),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: lightBg,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: lightCard,
          selectedItemColor: primaryGreen,
          unselectedItemColor: Color(0xFF8B94A3),
          type: BottomNavigationBarType.fixed,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: lightCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: lightLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: lightLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryGreen, width: 2),
          ),
        ),
        dividerTheme: const DividerThemeData(color: lightLine, thickness: 1),
      );
}
