/// Basket / multi-item comparison screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/basket_result.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../services/analytics.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/external.dart';
import '../widgets/item_emoji.dart';
import 'map_screen.dart';

/// Thrown internally when a joined family code doesn't exist (404).
class _FamNotFound implements Exception {
  const _FamNotFound();
}

class BasketScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final double radiusKm;

  const BasketScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });

  @override
  State<BasketScreen> createState() => _BasketScreenState();
}

class _BasketScreenState extends State<BasketScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();

  final List<String> _items = [];
  Set<String> _bought = <String>{};
  BasketResponse? _result;
  bool _loading = false;
  String? _error;
  String? _famCode; // joined shared/family basket code

  // Autocomplete for product suggestions
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  // Quick-pick popular items (shown when the add field is empty, or when the
  // user taps + with nothing typed) so adding is one tap and obviously possible.
  bool _showPopular = false;

  /// Curated, clean staples for the one-tap quick-add slider.
  static const _popularItems = <String>[
    'Хляб', 'Мляко', 'Яйца', 'Сирене', 'Кашкавал', 'Кисело мляко',
    'Краве масло', 'Олио', 'Ориз', 'Захар', 'Брашно', 'Пиле',
    'Картофи', 'Домати', 'Банани', 'Кафе',
  ];

  /// Common Bulgarian grocery items for autocomplete.
  static const _commonProducts = <String>[
    'мляко', 'извара', 'сирене', 'кашкавал', 'путер',
    'хляб', 'чиабатa', 'палачинки', 'кисело мляко',
    'яйца', 'пилешко', 'шунка', 'сухар', 'колбас',
    'захар', 'сол', 'брашно', 'макарони', 'ориз',
    'олио', 'зехтин', 'сок', 'вода', 'кола',
    'чай', 'кафе', 'шоколад', 'бисквити', 'чипс',
    'плодове', 'зелки', 'домати', 'краставици', 'картофи',
    'банани', 'ябълки', 'портокали', 'лимон',
    'кetchup', 'майонеза', 'горчица', 'соус',
    'пастетa', 'консерва', 'туна', 'риба',
    'пица', 'бургер', 'суши', 'ледено сладолед',
    'вино', 'бира', 'минерална вода', 'еко мляко',
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _famCode = await LocalStore.famCode();
    if (_famCode != null) {
      await _famLoad(silent: true);
    } else {
      final saved = await LocalStore.basket();
      final bought = await LocalStore.boughtItems();
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(saved);
          _bought = bought.map((e) => e.trim().toLowerCase()).toSet();
        });
      }
    }
    if (_items.isNotEmpty) _compare();
  }

  Future<void> _persist() => LocalStore.setBasket(_items);

  List<Map<String, dynamic>> _serialize() => _items
      .map((n) => {'n': n, 'b': _bought.contains(n.trim().toLowerCase())})
      .toList();

  /// Push the current list to the shared basket (fire-and-forget).
  Future<void> _famSync() async {
    final code = _famCode;
    if (code == null) return;
    try {
      await _api.famPut(code, _serialize());
    } catch (_) {/* offline — local kept, resyncs on next change */}
  }

  /// Pull the shared list from the server and replace local state.
  Future<void> _famLoad({bool silent = false}) async {
    final code = _famCode;
    if (code == null) return;
    try {
      final data = await _api.famGet(code);
      if (data == null) {
        await LocalStore.clearFamCode();
        if (mounted) setState(() => _famCode = null);
        return;
      }
      final raw = (data['items'] as List?) ?? [];
      final names = <String>[];
      final bought = <String>[];
      for (final it in raw) {
        final n = (it is Map ? it['n'] : null)?.toString() ?? '';
        if (n.isEmpty) continue;
        names.add(n);
        if (it is Map && it['b'] == true) bought.add(n);
      }
      await LocalStore.setBasket(names);
      await LocalStore.setBought(bought);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(names);
        _bought = bought.map((e) => e.trim().toLowerCase()).toSet();
      });
      if (_items.isNotEmpty) _compare();
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _famCreate() async {
    try {
      final data = await _api.famCreate(_serialize());
      final code = data['code']?.toString();
      if (code == null) return;
      await LocalStore.setFamCode(code);
      Analytics.instance.track('fam_create');
      if (!mounted) return;
      setState(() => _famCode = code);
      _showFamCode(code);
      await _famLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  /// Normalizes a family code the way the server does (lowercase, keep only
  /// [a-z0-9]). The Bulgarian keyboard shares digits with Cyrillic letters, so
  /// users often type stray characters (e.g. "442834и"); this keeps the stored
  /// code clean and matching.
  static String _normFamCode(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Joins an existing shared basket by [code]. Throws [_FamNotFound] if the
  /// code does not exist, or an [ApiException] on network/server failures — the
  /// caller (join dialog) surfaces these to the user.
  Future<void> _joinWithCode(String code) async {
    final data = await _api.famGet(code);
    if (data == null) throw const _FamNotFound();
    await LocalStore.setFamCode(code);
    _famCode = code;
    Analytics.instance.track('fam_join');
    await _famLoad();
  }

  Future<void> _shareFamCode() async {
    final code = _famCode;
    if (code == null) return;
    await _doShare(
        'Присъедини се към семейната ни количка с код: $code\nИзтегли Количка: https://kolichka.gotvach.com',
        subject: 'Семейна количка');
  }

  void _showFamCode(String code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Готово!'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Сподели този код със семейството:'),
          const SizedBox(height: 8),
          SelectableText(code,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 3)),
        ]),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); _shareFamCode(); }, child: const Text('Сподели')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Готово')),
        ],
      ),
    );
  }

  void _openFamDialog() {
    if (_famCode != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Семейна кошница'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Споделена с код:'),
            const SizedBox(height: 6),
            SelectableText(_famCode!,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text('Всеки с този код вижда и редактира същия списък — отметки и премахвания се синхронизират на всички устройства.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
          actions: [
            TextButton(onPressed: () { Navigator.pop(ctx); _shareFamCode(); }, child: const Text('Сподели')),
            TextButton(onPressed: () async { Navigator.pop(ctx); await LocalStore.clearFamCode(); if (mounted) setState(() => _famCode = null); }, child: const Text('Напусни')),
            TextButton(onPressed: () { Navigator.pop(ctx); _famLoad(); }, child: const Text('Опресни')),
          ],
        ),
      );
      return;
    }
    final joinCtrl = TextEditingController();
    bool joining = false;
    String? joinErr;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> doJoin() async {
            final code = _normFamCode(joinCtrl.text);
            if (code.isEmpty) {
              setLocal(() => joinErr = 'Въведи код, за да се присъединиш.');
              return;
            }
            setLocal(() { joining = true; joinErr = null; });
            try {
              await _joinWithCode(code);
              if (ctx.mounted) Navigator.pop(ctx);
            } on _FamNotFound {
              setLocal(() { joining = false; joinErr = 'Няма кошница с код „$code“. Провери кода и опитай пак.'; });
            } catch (e) {
              setLocal(() { joining = false; joinErr = friendlyError(e); });
            }
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('Семейна кошница'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Споделете един списък със семейството — отметки (купено) и премахвания се виждат на всички устройства.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: joining ? null : () { Navigator.pop(ctx); _famCreate(); },
                icon: const Icon(Icons.add), label: const Text('Създай нова'))),
              const SizedBox(height: 12),
              Text('или въведи код:', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: TextField(
                    controller: joinCtrl,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !joining,
                    textInputAction: TextInputAction.go,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(16),
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    ],
                    onSubmitted: (_) => joining ? null : doJoin(),
                    decoration: const InputDecoration(hintText: 'код', isDense: true, border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: joining ? null : doJoin,
                    child: joining
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Влез')),
              ]),
              if (joinErr != null) ...[
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline, size: 18, color: Theme.of(ctx).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text(joinErr!,
                      style: TextStyle(fontSize: 12.5, color: Theme.of(ctx).colorScheme.error))),
                ]),
              ],
            ]),
          );
        },
      ),
    );
  }

  void _addItem({String? suggestion}) {
    final text = (suggestion ?? _controller.text).trim();
    if (text.isEmpty) return;
    if (_items.any((e) => e.toLowerCase() == text.toLowerCase())) {
      setState(() {
        _controller.clear();
        _suggestions = [];
        _showSuggestions = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$text" вече е в кошницата'), duration: const Duration(seconds: 1)),
        );
      }
      return;
    }
    setState(() {
      _items.add(text);
      _controller.clear();
      // Clear the autocomplete dropdown too (it used to linger after adding).
      _suggestions = [];
      _showSuggestions = false;
    });
    _persist();
    _famSync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавено: $text'), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _removeItem(int index) async {
    final item = _items[index];
    setState(() => _items.removeAt(index));
    await LocalStore.removeFromBasket(item);
    final bought = await LocalStore.boughtItems();
    if (mounted) {
      setState(() => _bought = bought.map((e) => e.trim().toLowerCase()).toSet());
    }
    _famSync();
  }

  Future<void> _toggleBought(String item) async {
    await LocalStore.toggleBought(item);
    final bought = await LocalStore.boughtItems();
    if (!mounted) return;
    setState(() => _bought = bought.map((e) => e.trim().toLowerCase()).toSet());
    _famSync();
    // If a comparison is on screen, refresh it so checked-off items drop out.
    if (_result != null) _compare();
  }

  /// Present the native share sheet. Uses the current share_plus API with a
  /// [sharePositionOrigin] (required on iPad, harmless on iPhone) and surfaces
  /// failures — the old bare `Share.share` silently did nothing on iOS.
  Future<void> _doShare(String text, {String? subject}) async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = (box != null && box.hasSize)
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await Share.share(text, subject: subject, sharePositionOrigin: origin);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Споделянето не бе успешно: ${friendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _share() async {
    if (_items.isEmpty) return;
    final lines = _items.map((e) => '\u2022 $e').join('\n');
    final url =
        'https://kolichka.gotvach.com/?b=${Uri.encodeComponent(_items.join(','))}';
    await _doShare('\u041c\u043e\u044f\u0442\u0430 \u043a\u043e\u043b\u0438\u0447\u043a\u0430:\n$lines\n\n\u0421\u0440\u0430\u0432\u043d\u0438 \u0446\u0435\u043d\u0438: $url',
        subject: 'Моята количка в Количка');
    Analytics.instance.track('share_basket', {'items': _items.length});
  }

  /// Send the basket to miniChef to be cooked.
  ///
  /// Unbought items only. A ticked item is already in the cupboard; what this shop is for is
  /// the rest, and it is also the shorter, better prompt. Falls back to the whole basket when
  /// everything is ticked, because an empty hand-off would read as a broken button.
  Future<void> _cookWithBasket() async {
    var names = _items.where((n) => !_bought.contains(n.trim().toLowerCase())).toList();
    if (names.isEmpty) names = List<String>.from(_items);
    if (names.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Кошницата е празна')));
      }
      return;
    }
    Analytics.instance.track('basket_cook', {'items': names.length});
    // Uri.replace percent-encodes for us — do NOT also call Uri.encodeComponent,
    // or the Cyrillic arrives double-encoded as mojibake.
    final uri = Uri.parse('https://minichef.gotvach.com/').replace(queryParameters: {
      'cook': names.join(','),
      'lang': 'bg',
      'from': 'kolichka-app',
    });
    // externalApplication, NOT an in-app web view: miniChef asks for an email at the end of
    // the demo, and an in-app browser has no password manager, no existing session and no
    // Apple sign-in on iOS.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _compare() async {
    // Only compare items still to buy — bought (checked-off) items must not
    // appear in the store comparison anymore.
    final active = _items.where((e) => !_bought.contains(e.trim().toLowerCase())).toList();
    if (active.isEmpty) {
      setState(() { _result = null; _error = null; _loading = false; });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.basket(
        items: active,
        lat: widget.lat,
        lng: widget.lng,
        radiusKm: widget.radiusKm,
      );
      setState(() {
        _result = result;
        _loading = false;
      });
      Analytics.instance.track('compare_basket', {
        'items': _items.length,
        'stores': result.count,
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кошница'),
        actions: [
          IconButton(
            tooltip: 'Семейна кошница',
            icon: Icon(_famCode != null ? Icons.groups : Icons.group_add_outlined,
                color: _famCode != null ? Theme.of(context).colorScheme.primary : null),
            onPressed: _openFamDialog,
          ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Сподели',
              icon: const Icon(Icons.share),
              onPressed: _share,
            ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Изчисти',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await LocalStore.clearBasket();
                if (!mounted) return;
                setState(() {
                  _items.clear();
                  _bought.clear();
                  _result = null;
                });
                _famSync();
              },
            ),
        ],
      ),
      body: SafeArea(top: false, child: Column(
        children: [
          if (_famCode != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Icon(Icons.groups, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text('Семейна кошница · код $_famCode',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))),
                InkWell(onTap: () => _famLoad(),
                    child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.primary))),
              ]),
            ),
          // Add-item row with autocomplete
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: 'Добави продукт (напр. хляб)',
                      prefixIcon: Icon(Icons.search, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.surfaceContainerHighest
                          : const Color(0xFFEEF1F5),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _addItem(),
                    onChanged: (text) {
                      setState(() {
                        if (text.length >= 2) {
                          _suggestions = _commonProducts.where((p) =>
                              p.toLowerCase().contains(text.toLowerCase()) &&
                              !_items.any((e) => e.toLowerCase() == p.toLowerCase())
                          ).take(5).toList();
                          _showSuggestions = true;
                        } else {
                          _suggestions = [];
                          _showSuggestions = false;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: () {
                  // With text → add it. Empty → reveal popular quick-picks
                  // instead of doing nothing (clear "add something" affordance).
                  if (_controller.text.trim().isEmpty) {
                    setState(() {
                      _showSuggestions = false;
                      _showPopular = !_showPopular;
                    });
                  } else {
                    setState(() => _showSuggestions = false);
                    _addItem();
                  }
                }, child: const Icon(Icons.add)),
              ],
            ),
          ),
          // Popular quick-add slider — shown when the field is empty and the
          // user asked for ideas (tapped +), or whenever the basket is empty.
          if (!_showSuggestions &&
              _controller.text.trim().isEmpty &&
              (_showPopular || _items.isEmpty))
            _buildPopularStrip(),
          // Autocomplete suggestions dropdown
          if (_showSuggestions && _suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              color: Theme.of(context).colorScheme.surface,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return ListTile(
                    leading: Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    title: Text(suggestion),
                    dense: true,
                    onTap: () => _addItem(suggestion: suggestion),
                  );
                },
              ),
            ),
          if (_items.isNotEmpty) _buildCounter(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                ..._buildChecklist(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _items.isNotEmpty ? _compare : null,
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('Сравни цени в магазините'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                // Directly under the primary action, on the list someone is about to shop:
                // "what do I cook with this?" lands here and nowhere else. Secondary
                // styling keeps it an offer rather than a detour.
                if (_items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _cookWithBasket,
                        icon: const Text('👨‍🍳', style: TextStyle(fontSize: 16)),
                        label: const Text('Сготви с това'),
                      ),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(_error!)))
                else if (_result != null) ...[
                  const Divider(),
                  _buildResults(),
                ],
              ],
            ),
          ),
        ],
      )),
    );
  }

  /// One row in the empty-state personal/family explainer.
  Widget _emptyOptionRow({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: cs.primary.withOpacity(0.10), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              if (action != null) action,
            ],
          ),
        ),
      ],
    );
  }

  /// Horizontal slider of popular staples — one tap adds to the basket.
  Widget _buildPopularStrip() {
    final cs = Theme.of(context).colorScheme;
    final items = _popularItems
        .where((p) => !_items.any((e) => e.toLowerCase() == p.toLowerCase()))
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 14, color: cs.primary),
              const SizedBox(width: 4),
              Text('Популярни — докосни, за да добавиш',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final name = items[i];
              return ActionChip(
                avatar: Text(itemEmoji(name), style: const TextStyle(fontSize: 15)),
                label: Text(name, style: const TextStyle(fontSize: 13)),
                shape: StadiumBorder(side: BorderSide(color: cs.primary.withOpacity(0.4))),
                backgroundColor: cs.primary.withOpacity(0.06),
                onPressed: () => _addItem(suggestion: name),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCounter() {
    final bought =
        _items.where((e) => _bought.contains(e.trim().toLowerCase())).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Text('Списък за пазаруване',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const Spacer(),
          Text('$bought / ${_items.length} купени',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  List<Widget> _buildChecklist() {
    if (_items.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Започни своята количка',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text('Добави продукти, които искаш да купиш, после натисни „Сравни цени" и виж къде е най-евтино. Отметвай артикулите, щом ги вземеш.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              // Personal vs. family explainer.
              _emptyOptionRow(
                icon: Icons.person_outline,
                title: 'Личен списък',
                body: 'Само на това устройство. Идеален за бързо пазаруване сам.',
              ),
              const SizedBox(height: 10),
              _emptyOptionRow(
                icon: Icons.groups_outlined,
                title: 'Семейна кошница',
                body: 'Сподели един списък с близките си — всички виждат и редактират в реално време (отметки и премахвания се синхронизират).',
                action: TextButton.icon(
                  onPressed: _openFamDialog,
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Създай или влез с код'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return _items.asMap().entries.map((e) {
      final i = e.key;

      final item = e.value;
      final bought = _bought.contains(item.trim().toLowerCase());
      return ListTile(
        dense: true,
        leading: Checkbox(
          value: bought,
          activeColor: Theme.of(context).colorScheme.primary,
          onChanged: (_) => _toggleBought(item),
        ),
        title: Row(
          children: [
            Text(itemEmoji(item), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: bought ? TextDecoration.lineThrough : null,
                  color: bought ? Theme.of(context).colorScheme.onSurfaceVariant : null,
                ),
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Премахни',
          onPressed: () => _removeItem(i),
        ),
        onTap: () => _toggleBought(item),
      );
    }).toList();
  }

  Widget _buildResults() {
    final result = _result!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mixed optimal summary
          if (result.mixedOptimal != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 6),
                        const Text(
                          'Най-евтино (разделено)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const Spacer(),
                        Text(
                          '${result.mixedOptimal!.total.toStringAsFixed(2)} €',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${result.mixedOptimal!.storesCount} магазинa, ${result.mixedOptimal!.itemsFound}/${result.mixedOptimal!.itemsTotal} продукта',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    ...result.mixedOptimal!.breakdown.where((item) => item.price > 0).map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text(itemEmoji(item.query), style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(item.query, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                          Text(item.chainName, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 8),
                          Text(
                            '${item.price.toStringAsFixed(2)} €',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Per-store results — only stores that actually carry at least one of
          // the basket items (drop "0 €" / nothing-found stores).
          ...(() {
            final stores = result.stores
                .where((s) => s.itemsFound > 0 && s.total > 0)
                .toList();
            return [
              Text(
                'По магазин (${stores.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              if (stores.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Няма магазини с продукти от кошницата наблизо.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              else
                ...stores.map((store) => _StoreCard(store: store, radiusKm: widget.radiusKm)),
            ];
          })(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final BasketStore store;
  final double radiusKm;

  const _StoreCard({required this.store, required this.radiusKm});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MapScreen(
                lat: store.lat,
                lng: store.lng,
                radiusKm: radiusKm,
                articleStoreId: store.storeId,
                articleLat: store.lat,
                articleLng: store.lng,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.chainName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${store.distanceText} · ${store.itemsFound}/${store.itemsTotal} продукта',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (store.address.isNotEmpty)
                        Text(
                          store.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Навигация',
                  icon: Icon(Icons.directions, color: Theme.of(context).colorScheme.primary),
                  onPressed: () => openInMaps('${store.lat}, ${store.lng}'),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${store.total.toStringAsFixed(2)} €',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.secondary),
                    ),
                    if (store.complete)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Комплетно', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.secondary)),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Only items this store actually carries — skip not-found (0 €) rows.
            ...store.breakdown.where((item) => item.price > 0).map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(itemEmoji(item.name ?? item.query), style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name ?? item.query, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        if (item.name != null)
                          Text(item.query, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.price.toStringAsFixed(2)} €',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )),
          ],
        ),
        ),
      ),
    );
  }
}
