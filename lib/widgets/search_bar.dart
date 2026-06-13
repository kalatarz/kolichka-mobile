/// Search bar matching the web v2 design.
/// Shows magnifying glass icon, search input, clear button, and "Търси" button.
library;

import 'package:flutter/material.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(Icons.search, size: 22, color: colorScheme.primary),
            ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(),
                style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                ),
              ),
            ),
            if (_hasText)
              IconButton(
                icon: Icon(Icons.close, size: 20, color: colorScheme.onSurfaceVariant),
                onPressed: () {
                  widget.controller.clear();
                  widget.onClear?.call();
                },
              ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                ),
                child: const Text('Търси', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
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
