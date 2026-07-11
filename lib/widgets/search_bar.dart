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
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    // IMPORTANT: these listeners must NOT call setState(). Rebuilding the
    // TextField subtree while the IME connection is being (re)established makes
    // the keyboard "open then immediately hide" on some real Android devices.
    // The focus border is driven by AnimatedBuilder(animation: _focusNode) and
    // the clear button by ValueListenableBuilder on the controller, so the
    // field element itself is never rebuilt by typing or focus changes — the
    // listeners here only manage the floating suggestion overlay imperatively.
    widget.controller.addListener(_syncOverlaySoon);
    _focusNode.addListener(_syncOverlaySoon);
  }

  @override
  void dispose() {
    _removeOverlay();
    widget.controller.removeListener(_syncOverlaySoon);
    _focusNode.removeListener(_syncOverlaySoon);
    _focusNode.dispose();
    super.dispose();
  }

  void _syncOverlaySoon() {
    // Defer overlay work until after the current build/layout pass.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) widget.onSearch(text);
    _removeOverlay();
  }

  List<dynamic> get _filtered {
    final q = widget.controller.text.toLowerCase();
    if (q.isEmpty || widget.suggestions == null) return const [];
    return widget.suggestions!.where((item) {
      final label = item is String ? item : (item.label as String);
      return label.toLowerCase().contains(q);
    }).toList();
  }

  // ---- Floating overlay (renders above everything, incl. category chips) ----
  void _syncOverlay() {
    if (!mounted) return;
    final show =
        widget.controller.text.isNotEmpty && _focusNode.hasFocus && _filtered.isNotEmpty;
    if (show) {
      if (_overlay == null) {
        _overlay = _buildOverlay();
        Overlay.of(context).insert(_overlay!);
      } else {
        _overlay!.markNeedsBuild();
      }
    } else {
      _removeOverlay();
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  OverlayEntry _buildOverlay() {
    return OverlayEntry(
      builder: (ctx) {
        final items = _filtered;
        final theme = Theme.of(context);
        return Positioned(
          width: _fieldWidth(),
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 6),
            child: Material(
              color: theme.scaffoldBackgroundColor,
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final item = items[i];
                    final isStr = item is String;
                    final String text = isStr ? item : item.label;
                    final String? emoji = isStr ? null : item.emoji;
                    return ListTile(
                      dense: true,
                      leading: emoji != null
                          ? Text(emoji, style: const TextStyle(fontSize: 20))
                          : Icon(Icons.search, size: 20, color: theme.colorScheme.primary),
                      title: Text(text),
                      onTap: () {
                        if (isStr) {
                          widget.controller.text = item;
                          widget.onSearch(item);
                        } else {
                          widget.onSearch('cat:${item.slug}');
                          widget.controller.clear();
                        }
                        _focusNode.unfocus();
                        _removeOverlay();
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _fieldWidth() {
    final box = context.findRenderObject() as RenderBox?;
    // Root is Padding(horizontal:12); subtract it so the dropdown lines up
    // with the input container, not the screen edges.
    return (box?.size.width ?? MediaQuery.of(context).size.width) - 24;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? cs.surfaceContainerHighest : const Color(0xFFEEF1F5);

    // Build the TextField exactly once. It is handed to AnimatedBuilder as the
    // reused `child`, so neither focus changes (border) nor typing (clear
    // button) ever rebuild or replace this element — which is what keeps the
    // soft keyboard from being torn down right after it opens.
    final field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _submit(),
      style: TextStyle(fontSize: 16, color: cs.onSurface),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isCollapsed: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );

    // The inner content (icon + field + clear + submit) is built once and
    // reused; only the border decoration reacts to focus.
    final content = Row(
      children: [
        const SizedBox(width: 14),
        Icon(Icons.search, size: 22, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: field),
        // Clear (×) — rebuilds in isolation when the text empties/fills.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                widget.controller.clear();
                widget.onClear?.call();
                _removeOverlay();
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
              ),
            );
          },
        ),
        // Integrated green action button — circular, native-looking.
        Padding(
          padding: const EdgeInsets.all(5),
          child: Material(
            color: cs.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _submit,
              child: SizedBox(
                width: 42, height: 42,
                child: Icon(Icons.arrow_forward_rounded, color: cs.onPrimary, size: 22),
              ),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: CompositedTransformTarget(
        link: _link,
        child: AnimatedBuilder(
          animation: _focusNode,
          builder: (context, child) {
            final focused = _focusNode.hasFocus;
            return Material(
              color: fill,
              borderRadius: BorderRadius.circular(26),
              clipBehavior: Clip.antiAlias,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: focused ? cs.primary : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: child,
              ),
            );
          },
          child: content,
        ),
      ),
    );
  }
}
