/// Location chip matching the web v2 design.
/// Full-width tappable button with pin icon, location text, and settings cog.
library;

import 'package:flutter/material.dart';
import 'app_theme.dart';

class LocationChip extends StatelessWidget {
  final String locationText;
  final VoidCallback onTap;

  const LocationChip({
    super.key,
    required this.locationText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? AppTheme.darkLine : AppTheme.lightLine,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.place, size: 16, color: AppTheme.primaryGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locationText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppTheme.primaryTextDark : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: isDark ? AppTheme.mutedText : AppTheme.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
