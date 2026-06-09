/// Brand header bar matching the web v2 design.
/// Shows the 🛒 icon + "Количка" name with action buttons on the right.
library;

import 'package:flutter/material.dart';
import 'app_theme.dart';

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
        color: isDark ? AppTheme.darkCard : Colors.white,
        border: Border(
          bottom: BorderSide(color: isDark ? AppTheme.darkLine : AppTheme.lightLine, width: 1),
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
                  const Text('🛒', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    'Количка',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.primaryTextDark : Colors.black87,
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
              icon: const Text('❤️', style: TextStyle(fontSize: 18)),
              onPressed: onFavorites,
              tooltip: 'Любими',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),

          if (onThemeToggle != null)
            IconButton(
              icon: Text(
                isDark ? '☀️' : '🌙',
                style: const TextStyle(fontSize: 18),
              ),
              onPressed: onThemeToggle,
              tooltip: 'Тема',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),

          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: isDark ? AppTheme.mutedText : AppTheme.mutedText,
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
