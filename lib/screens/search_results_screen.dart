/// Search results screen showing price comparison for a product or category.
library;

import 'package:flutter/material.dart';
import '../models/compare_result.dart';
import "../services/api_service.dart";
import "../services/local_store.dart";

class SearchResultsScreen extends StatefulWidget {
  final String query;
  final String displayQuery;
  final double lat;
  final double lng;
  final double radiusKm;

  const SearchResultsScreen({
    super.key,
    required this.query,
    required this.displayQuery,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  final ApiService _api = ApiService();
  CompareResponse? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final result = await _api.compare(
        query: widget.query,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Резултати за "${widget.displayQuery}"'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _search),
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
                        ElevatedButton(onPressed: _search, child: const Text('Опитай отново')),
                      ],
                    ),
                  ),
                )
              : _buildResults(),
    );
  }

  Widget _buildResults() {
    final result = _result!;
    if (result.matches.isEmpty && result.loose.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('Няма намерени резултати', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                'Опитайте с по-голям радиус или друг продукт.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _search,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Summary
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${result.count} продукта от ${result.matches.fold<int>(0, (m, e) => m + e.nChains)} вериги',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),

          // Canonical matches
          ...result.matches.map((match) => MatchCard(match: match)),

          // Loose results
          if (result.loose.isNotEmpty) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Други резултати',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            ...result.loose.map((loose) => LooseCard(loose: loose)),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

/// Card for a canonical match result.
class MatchCard extends StatelessWidget {
  final MatchResult match;

  const MatchCard({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name + qty
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.display,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                if (match.qty != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      match.qty!.toString(),
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.add_shopping_cart, color: Colors.green, size: 20),
                  onPressed: () async {
                    await LocalStore.addToBasket(match.display);
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Cheapest highlight
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        match.cheapest.chainName,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        match.cheapest.minPrice <= 0 ? '—' : '${match.cheapest.minPrice.toStringAsFixed(2)} €',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
                      ),
                      if (match.cheapest.isPromo)
                        Text(
                          'на цена от ${match.cheapest.priceRetail!.toStringAsFixed(2)} € (-${match.cheapest.pctOff}%)',
                          style: const TextStyle(fontSize: 10, color: Colors.amber),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Spread info
                if (match.spread != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Разлика: ${match.spread!.pct}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${match.spread!.min.toStringAsFixed(2)} — ${match.spread!.max.toStringAsFixed(2)} €',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          '${match.nChains} вериги',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // All chains row
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: match.chains.map((chain) {
                final isBest = chain.chainSlug == match.cheapest.chainSlug;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBest ? Theme.of(context).colorScheme.secondary.withOpacity(0.1) : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isBest ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chain.chainName,
                        style: TextStyle(fontSize: 11, color: isBest ? Theme.of(context).colorScheme.secondary : null),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${chain.minPrice.toStringAsFixed(2)} €',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isBest ? Theme.of(context).colorScheme.secondary : null,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final chains = [...match.chains]..sort((a, b) => a.minPrice.compareTo(b.minPrice));
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(match.display, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (match.qty != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(match.qty!.toString(), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            const Divider(),
            ...chains.map((c) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.chainName),
                  subtitle: c.nStores != null ? Text('${c.nStores} магазина') : null,
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${c.minPrice.toStringAsFixed(2)} €',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (c.isPromo)
                        Text('от ${c.priceRetail!.toStringAsFixed(2)} (-${c.pctOff}%)',
                            style: const TextStyle(fontSize: 11, color: Colors.amber)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Card for a loose (non-canonical) result.
class LooseCard extends StatelessWidget {
  final LooseResult loose;

  const LooseCard({super.key, required this.loose});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(loose.rawName, style: const TextStyle(fontSize: 13)),
        subtitle: Text(loose.chainName),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add_shopping_cart, color: Colors.green, size: 20),
              onPressed: () async {
                await LocalStore.addToBasket(loose.rawName);
              },
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  loose.price <= 0 ? '—' : '${loose.price.toStringAsFixed(2)} €',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (loose.distM != null)
                  Text(
                    loose.distM! < 1000 ? '${loose.distM} m' : '${(loose.distM! / 1000).toStringAsFixed(1)} km',
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
