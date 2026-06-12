/// Basket / multi-item comparison screen.
library;

import 'package:flutter/material.dart';
import '../models/basket_result.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../services/analytics.dart';
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
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(saved);
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

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
    _persist();
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
              tooltip: 'Изчисти',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await LocalStore.clearBasket();
                if (!mounted) return;
                setState(() {
                  _items.clear();
                  _result = null;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Input area
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
                FilledButton(onPressed: _addItem, child: const Text('+')),
              ],
            ),
          ),

          // Item chips
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _items.asMap().entries.map((entry) {
                  return Chip(
                    label: Text(entry.value),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _removeItem(entry.key),
                  );
                }).toList(),
              ),
            ),

          // Compare button
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _items.isNotEmpty ? _compare : null,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Сравни цени'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          const Divider(),

          // Results
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _result != null
                        ? _buildResults()
                        : const Center(
                            child: Text(
                              'Добавете продукти и натиснете "Сравни цени"',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.mutedText),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final result = _result!;
    return SingleChildScrollView(
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
