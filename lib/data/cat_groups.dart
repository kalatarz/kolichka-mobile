/// Two-level category groups — mirrors the web app's `CAT_GROUPS`.
///
/// Each group bundles a set of category slugs. On the home screen the user taps
/// a group chip and the categories belonging to it expand below (drill-down),
/// matching the production web experience. Slugs that aren't present in the
/// live `/api/categories` response (disabled / out of season) are filtered out
/// at render time, and empty groups are hidden.
library;

class CatGroup {
  final String label;
  final String emoji;
  final List<String> slugs;

  const CatGroup({required this.label, required this.emoji, required this.slugs});
}

const List<CatGroup> kCatGroups = [
  CatGroup(label: 'Основни и варива', emoji: '🍞', slugs: ['bread', 'flour', 'rice', 'pasta', 'legumes']),
  CatGroup(label: 'Мляко и яйца', emoji: '🥛', slugs: ['milk', 'yogurt', 'cheese-white', 'cheese-yellow', 'butter', 'eggs']),
  CatGroup(label: 'Месо и риба', emoji: '🥩', slugs: ['meat', 'ground-meat', 'cold-cuts', 'chicken', 'pork', 'beef', 'fish']),
  CatGroup(label: 'Зеленчуци', emoji: '🥬', slugs: ['potato', 'tomato', 'cucumber', 'onion', 'cabbage', 'carrot', 'olives']),
  CatGroup(label: 'Плодове', emoji: '🍎', slugs: ['apple', 'banana', 'lemon', 'orange']),
  CatGroup(label: 'Сладко', emoji: '🍫', slugs: ['chocolate', 'sugar', 'biscuits']),
  CatGroup(label: 'Олио и мазнини', emoji: '🫒', slugs: ['oil-sunflower', 'olive-oil']),
  CatGroup(label: 'Напитки', emoji: '🥤', slugs: ['water', 'coffee', 'tea']),
  CatGroup(label: 'Алкохол', emoji: '🍷', slugs: ['beer', 'wine', 'spirits']),
  CatGroup(label: 'Дом и хигиена', emoji: '🧼', slugs: ['toilet-paper', 'wet-wipes', 'dishwash', 'home-clean']),
];
