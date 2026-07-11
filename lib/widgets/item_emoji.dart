/// Maps a free-text product / basket item name to a category emoji, for quick
/// visual scanning and colour across the basket and the search results.
/// Ordered most-specific first (e.g. chicken before generic meat).
library;

String itemEmoji(String name) {
  final s = name.toLowerCase();
  bool has(List<String> ks) => ks.any((k) => s.contains(k));
  if (has(['пил'])) return '🍗'; // chicken
  if (has(['кайма'])) return '🥩'; // ground meat
  if (has(['колбас', 'салам', 'луканка', 'надениц', 'шунк', 'бекон', 'пастърма'])) return '🥓';
  if (has(['риба', 'скумрия', 'пъстърва', 'херинг', 'тон', 'ципура', 'лаврак', 'сьомга'])) return '🐟';
  if (has(['телеш', 'свин', 'агне', 'говежд', 'кюфте', 'шол', 'месо', 'стек', 'контра', 'врат', 'ребра'])) return '🥩';
  if (has(['кашкавал', 'сирен', 'извара', 'моцарел', 'топено'])) return '🧀';
  if (has(['масло'])) return '🧈';
  if (has(['мляко', 'кисело', 'айрян', 'сметана'])) return '🥛';
  if (has(['яйц'])) return '🥚';
  if (has(['хляб', 'питка', 'багета', 'франзел', 'симид', 'кифл'])) return '🍞';
  if (has(['банан'])) return '🍌';
  if (has(['ябълк'])) return '🍎';
  if (has(['домат'])) return '🍅';
  if (has(['картоф'])) return '🥔';
  if (has(['краставиц'])) return '🥒';
  if (has(['морков'])) return '🥕';
  if (has(['лук'])) return '🧅';
  if (has(['слънчоглед'])) return '🌻';
  if (has(['олио', 'зехтин'])) return '🫒';
  if (has(['ориз'])) return '🍚';
  if (has(['захар'])) return '🍬';
  if (has(['брашно'])) return '🌾';
  if (has(['кафе'])) return '☕';
  if (has(['вода'])) return '💧';
  if (has(['бира', 'пиво'])) return '🍺';
  if (has(['вино', 'ракия', 'водка', 'уиски'])) return '🍷';
  if (has(['шоколад'])) return '🍫';
  if (has(['бисквит', 'вафл'])) return '🍪';
  if (has(['макарон', 'спагет', 'паста', 'фиде'])) return '🍝';
  if (has(['плод', 'зеленчук', 'салата', 'чушк', 'зеле', 'грозде', 'портокал', 'лимон', 'круша', 'праскова'])) return '🥗';
  return '🛒';
}
