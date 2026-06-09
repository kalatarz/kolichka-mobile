/// Product category model.
/// Corresponds to GET /api/categories response items.
class Category {
  final String slug;
  final String label;
  final String? emoji;

  const Category({
    required this.slug,
    required this.label,
    this.emoji,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      slug: json['slug'] as String,
      label: json['label'] as String,
      emoji: json['emoji'] as String?,
    );
  }

  /// Query string for use in /api/compare.
  String get queryParam => 'cat:$slug';

  @override
  String toString() => (emoji != null && emoji!.isNotEmpty) ? '$emoji $label' : label;
}
