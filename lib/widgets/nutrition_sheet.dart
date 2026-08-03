/// Nutrition bottom sheet — FoodBase (foodbase.dev) integration.
///
/// Searches FoodBase for a product name and shows the top match's Nutri-Score,
/// NOVA group and Eco-Score plus a per-100g macro summary, with a button that
/// opens the full FoodBase article (nutrition-scores page) for the product.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/foodbase_service.dart';
import '../services/analytics.dart';

/// Open the nutrition sheet for [productName]. No-op if FoodBase isn't enabled.
Future<void> showNutritionSheet(BuildContext context, String productName) {
  Analytics.instance.track('foodbase_open', {'q': productName});
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => _NutritionSheet(productName: productName),
  );
}

class _NutritionSheet extends StatefulWidget {
  final String productName;
  const _NutritionSheet({required this.productName});

  @override
  State<_NutritionSheet> createState() => _NutritionSheetState();
}

class _NutritionSheetState extends State<_NutritionSheet> {
  final _svc = FoodbaseService();
  late Future<List<FoodbaseFood>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.search(widget.productName);
  }

  void _retry() => setState(() => _future = _svc.search(widget.productName));

  Future<void> _openArticle() async {
    final uri = FoodbaseService.articleUrl(widget.productName);
    Analytics.instance.track('foodbase_article', {'q': widget.productName});
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* ignore — device without a browser */}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.eco_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Хранителни стойности',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(widget.productName,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            FutureBuilder<List<FoodbaseFood>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return _message(
                    icon: Icons.wifi_off_rounded,
                    text: snap.error.toString(),
                    showRetry: true,
                  );
                }
                final foods = snap.data ?? const [];
                if (foods.isEmpty) {
                  return _message(
                    icon: Icons.search_off_rounded,
                    text: 'Няма намерен продукт във FoodBase.',
                  );
                }
                return _result(foods.first);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openArticle,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Виж във FoodBase'),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Данни от foodbase.dev',
                  style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message({required IconData icon, required String text, bool showRetry = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 34, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          if (showRetry) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: _retry, child: const Text('Опитай пак')),
          ],
        ],
      ),
    );
  }

  Widget _result(FoodbaseFood f) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (f.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  f.imageUrl!,
                  width: 54, height: 54, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (f.imageUrl != null) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  if (f.brand != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(f.brand!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (f.hasAnyScore)
          Wrap(
            spacing: 10, runSpacing: 10,
            children: [
              if (f.nutriscore != null) _GradeBadge(label: 'Nutri-Score', grade: f.nutriscore!, palette: _nutriPalette),
              if (f.ecoscore != null) _GradeBadge(label: 'Eco-Score', grade: f.ecoscore!, palette: _ecoPalette),
              if (f.novaGroup != null) _NovaBadge(group: f.novaGroup!),
            ],
          )
        else
          Text('Няма оценки за този продукт.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        if (f.nutrition != null && !f.nutrition!.isEmpty) ...[
          const SizedBox(height: 16),
          Text('На 100 г / 100 мл',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _macro('Калории', f.nutrition!.energyKcal, 'kcal'),
              _macro('Протеини', f.nutrition!.proteinsG, 'г'),
              _macro('Въглехидрати', f.nutrition!.carbsG, 'г'),
              _macro('от които захари', f.nutrition!.sugarsG, 'г'),
              _macro('Мазнини', f.nutrition!.fatG, 'г'),
              _macro('Фибри', f.nutrition!.fiberG, 'г'),
            ].whereType<Widget>().toList(),
          ),
        ],
      ],
    );
  }

  Widget? _macro(String label, double? value, String unit) {
    if (value == null) return null;
    final cs = Theme.of(context).colorScheme;
    final v = value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 1),
          Text('$v $unit',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: cs.onSurface)),
        ],
      ),
    );
  }
}

// --- Score palettes (official-ish Nutri-Score / Eco-Score colours a–e). ---
const Map<String, Color> _nutriPalette = {
  'a': Color(0xFF038141),
  'b': Color(0xFF85BB2F),
  'c': Color(0xFFFECB02),
  'd': Color(0xFFEE8100),
  'e': Color(0xFFE63E11),
};
const Map<String, Color> _ecoPalette = {
  'a': Color(0xFF1E8F4E),
  'b': Color(0xFF7BC043),
  'c': Color(0xFFE8C221),
  'd': Color(0xFFEF7D1A),
  'e': Color(0xFFDE4A26),
};

class _GradeBadge extends StatelessWidget {
  final String label;
  final String grade; // a–e
  final Map<String, Color> palette;
  const _GradeBadge({required this.label, required this.grade, required this.palette});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final letter = String.fromCharCode('a'.codeUnitAt(0) + i);
            final active = letter == grade;
            final color = palette[letter] ?? Colors.grey;
            return Container(
              margin: EdgeInsets.only(right: i == 4 ? 0 : 3),
              width: active ? 26 : 18,
              height: active ? 30 : 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? color : color.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(6),
                border: active ? Border.all(color: cs.onSurface.withValues(alpha: 0.35), width: 1.4) : null,
              ),
              child: Text(letter.toUpperCase(),
                  style: TextStyle(
                      fontSize: active ? 15 : 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            );
          }),
        ),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _NovaBadge extends StatelessWidget {
  final int group; // 1–4
  const _NovaBadge({required this.group});

  static const Map<int, Color> _colors = {
    1: Color(0xFF00A040),
    2: Color(0xFFF2C300),
    3: Color(0xFFF07F00),
    4: Color(0xFFD9202B),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _colors[group] ?? Colors.grey;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30, height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text('$group',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(height: 5),
        Text('NOVA', style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
