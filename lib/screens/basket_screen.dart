/// Basket / multi-item comparison screen.
library;

import 'package:flutter/material.dart';
import '../models/basket_result.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../services/analytics.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _loadAndCompare();
  }

  /// Load the persisted basket and, if it has items, compare immediately.
  Future<void> _loadAndCompare() async {
    final saved = await LocalStore.basket();
    final bought = await LocalStore.boughtItems();
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(saved);
      _bought = bought.map((e) => e.trim().toLowerCase()).toSet();
    });
    if (_items.isNotEmpty) _compare();
  }

  Future<void> _persist() => LocalStore.setBasket(_items);

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
  }

  Future<void> _removeItem(int index) async {
    final item = _items[index];
    setState(() => _items.removeAt(index));
    await LocalStore.removeFromBasket(item);
    final bought = await LocalStore.boughtItems();
    if (mounted) {
      setState(() => _bought = bought.map((e) => e.trim().toLowerCase()).toSet());
    }
  }

  Future<void> _toggleBought(String item) async {
    await LocalStore.toggleBought(item);
    final bought = await LocalStore.boughtItems();
    if (!mounted) return;
    setState(() => _bought = bought.map((e) => e.trim().toLowerCase()).toSet());
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
              },
            ),
        ],
      ),
      body: Column(
        children: [
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
          const Text('Списък за пазаруване',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mutedText)),
          const Spacer(),
          Text('$bought / ${_items.length} купени',
              style: const TextStyle(fontSize: 12, color: AppTheme.mutedText)),
        ],
      ),
    );
  }

  List<Widget> _buildChecklist() {
    if (_items.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 12),
          child: Text(
            'Добави продукти, които искаш да купиш. Отметни ги, щом ги вземеш.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.mutedText),
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
          activeColor: AppTheme.primaryGreen,
          onChanged: (_) => _toggleBought(item),
        ),
        title: Text(
          item,
          style: TextStyle(
            decoration: bought ? TextDecoration.lineThrough : null,
            color: bought ? AppTheme.mutedText : null,
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
                        const Icon(Icons.star, color: AppTheme.warnAmber, size: 18),
                        const SizedBox(width: 6),
                        const Text(
                          'Най-евтино (разделено)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const Spacer(),
                        Text(
                          '${result.mixedOptimal!.total.toStringAsFixed(2)} лв',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.accentGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${result.mixedOptimal!.storesCount} магазина, ${result.mixedOptimal!.itemsFound}/${result.mixedOptimal!.itemsTotal} продукта',
                      style: TextStyle(fontSize: 11, color: AppTheme.mutedText),
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
                            '${item.price.toStringAsFixed(2)} лв',
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
                        style: TextStyle(fontSize: 11, color: AppTheme.mutedText),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${store.total.toStringAsFixed(2)} лв',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.accentGreen),
                    ),
                    if (store.complete)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Комплетно', style: TextStyle(fontSize: 10, color: AppTheme.accentGreen)),
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
                          Text(item.query, style: TextStyle(fontSize: 10, color: AppTheme.mutedText)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.price.toStringAsFixed(2)} лв',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}
