/// Kolichka app smoke test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolichka/main.dart';
import 'package:kolichka/screens/home_screen.dart';

void main() {
  group('Kolichka App', () {
    testWidgets('HomeScreen shows loading state initially', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pump();

      // Initially shows CircularProgressIndicator while loading location
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('App launches without crashing', (tester) async {
      final provider = ThemeProvider();
      await provider.load();
      await tester.pumpWidget(KolichkaApp(provider: provider));
      await tester.pump();

      // App should render — Scaffold is the root container
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
