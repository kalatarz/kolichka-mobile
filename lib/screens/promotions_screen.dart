/// Promotions / deals screen with chain filter chips and store locations.
library;

import 'package:flutter/material.dart';
import '../models/promotion_result.dart';
import '../services/api_service.dart';
import "../utils/date_utils.dart" as date_utils;

class PromotionsScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final double radiusKm;

  const PromotionsScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  final ApiService _api = ApiService();
  PromotionsResponse? _result;
  bool _loading = true;
  String? _error;
  // Chain filter: empty means all chains shown
  final Set<String> _chainFilter = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _api.promotions(
        lat: widget.lat,
        lng: widget.lng,
        radiusKm: widget.radiusKm,
      );
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleChain(String slug) {
    setState(() {
      if (_chainFilter.contains(slug)) {
        _chainFilter.remove(slug);
      } else {
        _chainFilter.add(slug);
      }
    });
  }

  List<PromoChain> get _filteredChains {
    final chains = _result?.chains ?? [];
    if (_chainFilter.isEmpty) return chains;
    return chains.where((c) => _chainFilter.contains(c.chainSlug)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Промоции'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _load, child: const Text('Опитай отново')),
                      ],
                    ),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final result = _result!;
    if (result.chains.isEmpty) {
      return Center(
        child: Text('Няма промоции в тази зона', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    return Column(
      children: [
        // Chain filter chips row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            border: Border(
              bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // "All" chip
                FilterChip(
                  label: Text('Всички (${result.chains.length})'),
                  selected: _chainFilter.isEmpty,
                  onSelected: (_) => setState(() => _chainFilter.clear()),
                  selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  checkmarkColor: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                // Per-chain chips
                ...result.chains.map((c) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(c.chainName),
                    selected: _chainFilter.contains(c.chainSlug),
                    onSelected: (_) => _toggleChain(c.chainSlug),
                    selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    checkmarkColor: Theme.of(context).colorScheme.primary,
                  ),
                )),
              ],
            ),
          ),
        ),

        // Filtered results
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _filteredChains.isEmpty
                ? Center(
                    child: Text('Няма промоции за избраните вериги', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredChains.length,
                    itemBuilder: (context, index) {
                      final chain = _filteredChains[index];
                      return ChainPromoCard(
                        chain: chain,
                        lat: widget.lat,
                        lng: widget.lng,
                        radiusKm: widget.radiusKm,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class ChainPromoCard extends StatelessWidget {
  final PromoChain chain;
  final double lat;
  final double lng;
  final double radiusKm;

  const ChainPromoCard({
    super.key,
    required this.chain,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });

  @override
  Widget build(BuildContext context) {
    // Sort items by discount percentage (highest first)
    final sortedItems = List<PromoItem>.from(chain.items)..sort((a, b) => b.pctOff.compareTo(a.pctOff));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chain header with store count badge
            Row(
              children: [
                Icon(Icons.local_offer_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(chain.chainName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${chain.nStores} магазина',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.secondary),
                  ),
                ),
              ],
            ),
            if (chain.latestSnapshot != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Обновено: ${date_utils.DateUtils.formatToDayMonth(chain.latestSnapshot)}',
                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            const Divider(height: 16),
            // Sorted promo items
            ...sortedItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.rawName, style: const TextStyle(fontSize: 13)),
                        if (item.qty != null)
                          Text(
                            '${item.qty!['value'] ?? ''} ${item.qty!['unit'] ?? ''}',
                            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  // Price column
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Retail price (strikethrough)
                      if (item.priceRetail > item.pricePromo)
                        Padding(
                          padding: const EdgeInsets.only(right: 6, bottom: 2),
                          child: Text(
                            '${item.priceRetail.toStringAsFixed(2)} €',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      // Promo price
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${item.pricePromo.toStringAsFixed(2)} €',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
                          ),
                          const SizedBox(width: 6),
                          // Discount badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '-${item.pctOff}%',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ],
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
