/// Basket / multi-item comparison screen.
library;

import 'package:flutter/material.dart';
import '../models/basket_result.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../services/analytics.dart';
import 'package:share_plus/share_plus.dart';
import '../services/external.dart';

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
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Грешка при синхронизация')));
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Грешка при създаване')));
      }
    }
  }

  Future<void> _famJoin(String code) async {
    try {
      final data = await _api.famGet(code);
      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Няма такъв код')));
        }
        return;
      }
      await LocalStore.setFamCode(code);
      _famCode = code;
      Analytics.instance.track('fam_join');
      await _famLoad();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Грешка при присъединяване')));
      }
    }
  }

  Future<void> _shareFamCode() async {
    final code = _famCode;
    if (code == null) return;
    await Share.share(
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Семейна кошница'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Споделете един списък със семейството — отметки (купено) и премахвания се виждат на всички устройства.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () { Navigator.pop(ctx); _famCreate(); },
            icon: const Icon(Icons.add), label: const Text('Създай нова'))),
          const SizedBox(height: 12),
          Text('или въведи код:', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: joinCtrl,
                decoration: const InputDecoration(hintText: 'код', isDense: true, border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            FilledButton(onPressed: () { final c = joinCtrl.text.trim(); Navigator.pop(ctx); if (c.isNotEmpty) _famJoin(c); }, child: const Text('Влез')),
          ]),
        ]),
      ),
    );
  }

  void _addItem() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_items.any((e) => e.toLowerCase() == text.toLowerCase())) {
      _controller.clear();
      return;
    }
    setState(() {
      _items.add(text);
      _controller.clear();
    });
    _persist();
    _famSync();
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
  }

  Future<void> _share() async {
    if (_items.isEmpty) return;
    final lines = _items.map((e) => '\u2022 $e').join('\n');
    final url =
        'https://kolichka.gotvach.com/?b=${Uri.encodeComponent(_items.join(','))}';
    await Share.share('\u041c\u043e\u044f\u0442\u0430 \u043a\u043e\u043b\u0438\u0447\u043a\u0430:\n$lines\n\n\u0421\u0440\u0430\u0432\u043d\u0438 \u0446\u0435\u043d\u0438: $url',
        subject: 'Моята количка в Количка');
    Analytics.instance.track('share_basket', {'items': _items.length});
  }

  Future<void> _compare() async {
    if (_items.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.basket(
        items: _items,
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
        _error = e.toString();
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
      body: Column(
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
          // Add-item row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Добави продукт (напр. хляб)',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _addItem, child: const Icon(Icons.add)),
              ],
            ),
          ),
          if (_items.isNotEmpty) _buildCounter(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                ..._buildChecklist(),
                Padding(
                  padding: const EdgeInsets.all(12),
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
      ),
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
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 12),
          child: Text(
            'Добави продукти, които искаш да купиш. Отметни ги, щом ги вземеш.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        title: Text(
          item,
          style: TextStyle(
            decoration: bought ? TextDecoration.lineThrough : null,
            color: bought ? Theme.of(context).colorScheme.onSurfaceVariant : null,
          ),
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
                    ...result.mixedOptimal!.breakdown.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.query, style: const TextStyle(fontSize: 12))),
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

          // Per-store results
          Text(
            'По магазин (${result.count})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...result.stores.map((store) => _StoreCard(store: store)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final BasketStore store;

  const _StoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          // Future: Navigate to store details
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
                  onPressed: () => openInMaps(store.lat, store.lng),
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
            ...store.breakdown.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name ?? item.query, style: const TextStyle(fontSize: 12)),
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
