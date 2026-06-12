/// Search bar matching the web v2 design.
/// Shows magnifying glass icon, search input, clear button, and "Търси" button.
library;

import 'package:flutter/material.dart';
import 'app_theme.dart';

class KolichkaSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSearch;
  final VoidCallback? onClear;

  const KolichkaSearchBar({
    super.key,
    required this.controller,
    this.hintText = 'Търси продукт — мляко, хляб, вино…',
    required this.onSearch,
    this.onClear,
  });

  @override
  State<KolichkaSearchBar> createState() => _KolichkaSearchBarState();
}

class _KolichkaSearchBarState extends State<KolichkaSearchBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() => _hasText = widget.controller.text.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Search input box
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? AppTheme.darkLine : AppTheme.lightLine,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Magnifying glass icon
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Icon(Icons.search, size: 18, color: isDark ? AppTheme.mutedText : AppTheme.mutedText),
                  ),
                  // Input field
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submit(),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppTheme.primaryTextDark : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(color: isDark ? AppTheme.mutedText : AppTheme.mutedText),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  // Clear button
                  if (_hasText)
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: isDark ? AppTheme.mutedText : AppTheme.mutedText),
                      onPressed: () {
                        widget.controller.clear();
                        widget.onClear?.call();
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // "Търси" button
          Material(
            color: AppTheme.primaryGreen,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _submit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'Търси',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSearch(text);
    }
  }
}
