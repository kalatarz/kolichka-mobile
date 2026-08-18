// Regression guard for the doubled basket icon: the compare endpoint echoed
// category items back as "🍅 Домати", and every result row renders itemEmoji()
// beside the name, so tomatoes and cucumbers displayed as "🍅 🍅 Домати".
import 'package:flutter_test/flutter_test.dart';
import 'package:kolichka/widgets/item_emoji.dart';

void main() {
  group('stripLeadingEmoji', () {
    test('strips the emoji the server used to glue on', () {
      expect(stripLeadingEmoji('🍅 Домати'), 'Домати');
      expect(stripLeadingEmoji('🥒 Краставица'), 'Краставица');
      expect(stripLeadingEmoji('🥓 Колбас'), 'Колбас');
      expect(stripLeadingEmoji('🍶 Кисело мляко'), 'Кисело мляко');
    });

    test('leaves a clean name untouched', () {
      expect(stripLeadingEmoji('Домати'), 'Домати');
      expect(stripLeadingEmoji('Хляб Добруджа'), 'Хляб Добруджа');
      expect(stripLeadingEmoji('Ариана Светло пиво 4,5% 2л PET'),
          'Ариана Светло пиво 4,5% 2л PET');
    });

    test('handles multiple/padded emoji and odd input', () {
      expect(stripLeadingEmoji('🍅🥒 Домати'), 'Домати');
      expect(stripLeadingEmoji('  🍅   Домати  '), 'Домати');
      expect(stripLeadingEmoji(''), '');
    });

    test('an all-emoji name keeps its emoji rather than rendering blank', () {
      expect(stripLeadingEmoji('🍅'), '🍅');
    });

    test('never leaves a name that would double the row icon', () {
      for (final n in ['🍅 Домати', '🥒 Краставица', '🥓 Колбас', 'домати']) {
        final shown = stripLeadingEmoji(n);
        expect(shown.startsWith(itemEmoji(n)), isFalse,
            reason: 'row would render "${itemEmoji(n)} $shown"');
      }
    });
  });
}
