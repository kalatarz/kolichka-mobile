/// Radius segment control matching the web v2 design.
/// Shows 1/3/5/10 km buttons with active state highlighted in green.
library;

import 'package:flutter/material.dart';

class RadiusSegment extends StatelessWidget {
  final double selectedKm;
  final ValueChanged<double> onChanged;

  const RadiusSegment({
    super.key,
    required this.selectedKm,
    required this.onChanged,
  });

  static const List<double> _options = [1, 3, 5, 10];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text(
            'Радиус:',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          ..._options.map((km) {
            final active = km == selectedKm;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: active ? Theme.of(context).colorScheme.primary : (isDark ? Theme.of(context).colorScheme.surface : Colors.white),
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onChanged(km),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      '${km} км',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? Colors.white : (isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
