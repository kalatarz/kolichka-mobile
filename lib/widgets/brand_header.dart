/// Brand header bar matching the web v2 design.
/// Shows the 🛒 icon + "Количка" name with action buttons on the right.
library;

import 'package:flutter/material.dart';

class BrandHeader extends StatelessWidget {
  final VoidCallback? onThemeToggle;
  final VoidCallback? onFavorites;
  final VoidCallback? onSettings;

  const BrandHeader({
    super.key,
    this.onThemeToggle,
    this.onFavorites,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).colorScheme.surface : Colors.white,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Brand icon + name
          InkWell(
            onTap: onSettings,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_cart, size: 22, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Количка',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Action buttons row
          if (onFavorites != null)
            IconButton(
              icon: Icon(Icons.favorite, size: 20, color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.redAccent),
              onPressed: onFavorites,
              tooltip: 'Любими',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),

          if (onThemeToggle != null)
            IconButton(
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onPressed: onThemeToggle,
              tooltip: 'Тема',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),

          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
            onPressed: onSettings,
            tooltip: 'Настройки',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
