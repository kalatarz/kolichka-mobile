import 'package:flutter/material.dart';

class KolichkaSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onSearch;
  final VoidCallback? onClear;
  final String hintText;
  final List<dynamic>? suggestions;

  const KolichkaSearchBar({
    super.key,
    required this.controller,
    required this.onSearch,
    this.onClear,
    this.hintText = 'Търси...',
    this.suggestions,
  });

  @override
  State<KolichkaSearchBar> createState() => _KolichkaSearchBarState();
}

class _KolichkaSearchBarState extends State<KolichkaSearchBar> {
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() => _hasText = widget.controller.text.isNotEmpty);
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSearch(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
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
                    focusNode: _focusNode,
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
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
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
          if (_hasText && widget.suggestions != null && _focusNode.hasFocus)
            _buildSuggestionsOverlay(),
        ],
      ),
    );
  }

  Widget _buildSuggestionsOverlay() {
    final query = widget.controller.text.toLowerCase();
    final filteredSuggestions = widget.suggestions?.where((item) {
      if (item is String) {
        return item.toLowerCase().contains(query);
      } else {
        return item.label.toLowerCase().contains(query);
      }
    }).toList() ?? [];

    if (filteredSuggestions.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 55,
      left: 12,
      right: 12,
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        elevation: 8,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: filteredSuggestions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final item = filteredSuggestions[i];
              String text = "";
              if (item is String) {
                text = item;
              } else {
                text = '${item.label}';
              }
              return ListTile(
                leading: const Icon(Icons.category_outlined),
                title: Text(text),
                onTap: () {
                  if (item is String) {
                    widget.controller.text = item;
                    widget.onSearch(item);
                  } else {
                    widget.onSearch('cat:${item.slug}');
                    widget.controller.clear();
                  }
                  _submit();
                  _focusNode.unfocus();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
