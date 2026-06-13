/// In-app 5-star rating + feedback sheet.
///
/// Replaces the old "email us" feedback. Behaviour (smart routing):
///   • the rating + optional comment are POSTed to /api/feedback (real feedback)
///   • 4–5★  → after submit, trigger the native Google Play in-app review
///             (falls back to opening the Play listing)
///   • 1–3★  → ask for a private comment instead, so unhappy users give us
///             actionable feedback rather than a public 1-star review.
library;

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import '../services/api_service.dart';
import '../services/analytics.dart';

Future<void> showRatingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => const _RatingSheet(),
  );
}

class _RatingSheet extends StatefulWidget {
  const _RatingSheet();

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  bool _done = false;

  @override
  void dispose() {
    _comment.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    final comment = _comment.text.trim();

    try {
      await _api.submitFeedback(
        category: 'app-rating',
        rating: _rating,
        comment: comment.isEmpty ? null : comment,
        context: {'platform': 'android', 'source': 'rating-sheet'},
      );
    } catch (_) {
      // Still thank the user even if the network call fails.
    }
    Analytics.instance.track('rating_submitted', {
      'stars': _rating,
      'has_comment': comment.isNotEmpty,
    });

    // Happy users → nudge a public Google Play review.
    if (_rating >= 4) {
      try {
        final review = InAppReview.instance;
        if (await review.isAvailable()) {
          await review.requestReview();
        } else {
          await review.openStoreListing();
        }
      } catch (_) {
        // Not installed from Play / no store — ignore silently.
      }
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: _done ? _buildThanks(textColor) : _buildForm(textColor),
      ),
    );
  }

  Widget _buildThanks(Color textColor) {
    final happy = _rating >= 4;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Icon(happy ? Icons.celebration : Icons.favorite,
            size: 44, color: happy ? Theme.of(context).colorScheme.primary : Colors.redAccent),
        const SizedBox(height: 12),
        Text(
          happy
              ? 'Благодарим! Радваме се, че Количка ти е полезна.'
              : 'Благодарим за обратната връзка — ще я разгледаме.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Готово'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(Color textColor) {
    final lowRating = _rating > 0 && _rating <= 3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'Хареса ли ти Количка?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textColor),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Дай ни оценка с до 5 звезди',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 14),
        // Stars
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final filled = i < _rating;
            return IconButton(
              onPressed: () => setState(() => _rating = i + 1),
              iconSize: 38,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              constraints: const BoxConstraints(),
              icon: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: filled ? Colors.amber : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        // Comment — prompted for low ratings, optional for high.
        if (_rating > 0) ...[
          TextField(
            controller: _comment,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: lowRating
                  ? 'Какво да подобрим? (ще го прочетем лично)'
                  : 'Какво ти хареса? (по желание)',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          if (_rating >= 4)
            Text(
              'След изпращане ще те поканим да ни оцениш и в Google Play.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (_rating == 0 || _submitting) ? null : _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_rating >= 4 ? 'Оцени в Google Play' : 'Изпрати отзив'),
          ),
        ),
      ],
    );
  }
}
