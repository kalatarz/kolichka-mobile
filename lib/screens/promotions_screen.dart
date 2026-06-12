/// Promotions / deals screen.
library;

import 'package:flutter/material.dart';
import '../models/promotion_result.dart';
import '../services/api_service.dart';
import '../widgets/app_theme.dart';

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
      return const Center(
        child: Text('Няма промоции в тази зона', style: TextStyle(color: AppTheme.mutedText)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: result.chains.length,
        itemBuilder: (context, index) {
          final chain = result.chains[index];
          return ChainPromoCard(chain: chain);
        },
      ),
    );
  }
}

class ChainPromoCard extends StatelessWidget {
  final PromoChain chain;

  const ChainPromoCard({super.key, required this.chain});

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
                  child: Text(chain.chainName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${chain.nStores} магазина',
                    style: const TextStyle(fontSize: 11, color: AppTheme.accentGreen),
                  ),
                ),
              ],
            ),
            if (chain.latestSnapshot != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Обновено: ${chain.latestSnapshot}',
                  style: TextStyle(fontSize: 10, color: AppTheme.mutedText),
                ),
              ),
            const SizedBox(height: 4),
            ...chain.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(item.rawName, style: const TextStyle(fontSize: 13)),
                  ),
                  // Retail price (strikethrough)
                  if (item.priceRetail > item.pricePromo)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${item.priceRetail.toStringAsFixed(2)} €',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.mutedText,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  // Promo price
                  Text(
                    '${item.pricePromo.toStringAsFixed(2)} €',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  // Discount badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '-${item.pctOff}%',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
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
