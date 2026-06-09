/// Per-chain marker colors — mirrors the web app's `chainColor()` /
/// `KNOWN_CHAIN_COLOR` so the mobile map legend matches production exactly.
library;

import 'package:flutter/material.dart';

/// Brand colors for the major chains (hand-picked, non-conflicting).
const Map<String, Color> _knownChainColor = {
  'kaufland': Color(0xFF2C7BE5), // brand blue
  'lidl': Color(0xFFF0B46A), // brand orange
  'fantastico1': Color(0xFF5DD3A8), // green
  'fantastico2': Color(0xFF5DD3A8),
  'billa': Color(0xFFD6A32A), // mustard
  'kam': Color(0xFF6B46C1), // purple
  'metro': Color(0xFF0EA5E9), // cyan
  'tmarket': Color(0xFF7C3AED), // violet
  'apteki_remedium_0471': Color(0xFF22C55E), // pharmacy bright green
  'remedium_3306': Color(0xFF22C55E),
};

/// Deterministic, well-spread color for a chain slug. Known chains use their
/// brand color; everything else hashes to a hue in 50–320 (skips red, which is
/// reserved) at fixed saturation/lightness so distinct chains never collide.
Color chainColor(String slug) {
  final known = _knownChainColor[slug];
  if (known != null) return known;
  int h = 0;
  for (int i = 0; i < slug.length; i++) {
    // Mirror JS `((h << 5) - h + c) | 0` (signed 32-bit wrap) for parity.
    h = (((h << 5) - h) + slug.codeUnitAt(i)).toSigned(32);
  }
  final hue = 50 + (h.abs() % 270);
  return HSLColor.fromAHSL(1.0, hue.toDouble(), 0.65, 0.42).toColor();
}

/// 'Фантастико (Груп ООД)' → 'Фантастико' for legend chips, so different legal
/// entities of the same brand collapse into one row.
String prettyChainName(String? name) {
  if (name == null || name.isEmpty) return '';
  final stripped = name.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), '').trim();
  return stripped.isNotEmpty ? stripped : name;
}
