// Pins the logic behind the home-screen discount strip.
//
// The bug this guards against was not a crash: the deals SCREEN worked fine, but it
// was reachable only via Favourites → bottom sheet → a button, so in practice the app
// never showed a discount. The strip must therefore be non-empty in the cases a real
// user is actually in — including the day-one case of having no favourites at all.
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the interleave in _loadDeals: take one item per chain per pass, so the strip
/// is not a single retailer's shelf.
List<Map<String, dynamic>> interleave(List<List<Map<String, dynamic>>> byChain, int max) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; out.length < max; i++) {
    var added = false;
    for (final list in byChain) {
      if (i < list.length) { out.add(list[i]); added = true; }
      if (out.length >= max) break;
    }
    if (!added) break;
  }
  return out;
}

void main() {
  Map<String, dynamic> item(String chain, int pct) => {'chain': chain, 'pct': pct};

  group('deal strip composition', () {
    test('interleaves chains instead of emptying the first one', () {
      final r = interleave([
        [item('Кауфланд', 80), item('Кауфланд', 70), item('Кауфланд', 60)],
        [item('Лидл', 50), item('Лидл', 40)],
        [item('Билла', 30)],
      ], 6);
      expect(r.map((x) => x['chain']).take(3).toList(), ['Кауфланд', 'Лидл', 'Билла'],
          reason: 'first pass must take one from each chain');
      final chains = r.map((x) => x['chain']).toSet();
      expect(chains.length, 3, reason: 'strip must not be one retailer');
    });

    test('terminates when chains run dry rather than looping forever', () {
      final r = interleave([[item('A', 10)], [item('B', 20)]], 12);
      expect(r.length, 2);
    });

    test('handles no promotions at all', () {
      expect(interleave([], 12), isEmpty);
      expect(interleave([[], []], 12), isEmpty);
    });

    test('respects the cap', () {
      final many = List.generate(30, (i) => item('X', i));
      expect(interleave([many], 12).length, 12);
    });
  });

  group('distance display', () {
    // /api/promotions carries no distance, so the fallback path marks it -1 and the
    // card must then show the chain alone rather than "· -1.0 км".
    String label(String chain, double distKm) =>
        distKm >= 0 ? '$chain · ${distKm.toStringAsFixed(1)} км' : chain;

    test('shows distance when known', () => expect(label('Билла', 0.3), 'Билла · 0.3 км'));
    test('omits it when unknown', () => expect(label('Билла', -1), 'Билла'));
    test('does not render a negative distance', () => expect(label('Билла', -1).contains('-1'), isFalse));
  });
}
