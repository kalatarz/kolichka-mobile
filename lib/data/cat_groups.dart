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
  CatGroup(label: 'Млечни', emoji: '🥛', slugs: ['milk', 'yogurt', 'cheese-yellow', 'cheese-white', 'butter']),
  CatGroup(label: 'Месо и риба', emoji: '🥩', slugs: ['meat', 'ground-meat', 'cold-cuts', 'cured-meats', 'chicken', 'pork', 'beef', 'fish']),
  CatGroup(label: 'Плодове и зеленчуци', emoji: '🥗', slugs: ['apple', 'banana', 'orange', 'lemon', 'apricot', 'cherries', 'strawberries', 'peach', 'pear', 'plum', 'grape', 'watermelon', 'melon', 'tomato', 'cucumber', 'potato', 'onion', 'cabbage', 'carrot', 'pepper', 'olives']),
  CatGroup(label: 'Основни', emoji: '🍚', slugs: ['eggs', 'bread', 'flour', 'sugar', 'salt', 'rice', 'pasta', 'legumes', 'oil-sunflower', 'olive-oil', 'vinegar', 'filo']),
  CatGroup(label: 'Лакомства', emoji: '🍫', slugs: ['chocolate', 'biscuits', 'croissant']),
  CatGroup(label: 'Напитки', emoji: '🍷', slugs: ['coffee', 'tea', 'beer', 'wine', 'spirits', 'water', 'juice']),
  CatGroup(label: 'Дом и хигиена', emoji: '🧼', slugs: ['toilet-paper', 'wet-wipes', 'dishwash', 'home-clean', 'soap', 'toothpaste', 'diapers']),
];
