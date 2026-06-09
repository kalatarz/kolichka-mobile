/// Models for the /api/promotions endpoint response.

class PromoItem {
  final String rawName;
  final Map<String, dynamic>? qty;
  final double priceRetail;
  final double pricePromo;
  final int pctOff;
  final String? snapshotDate;

  const PromoItem({
    required this.rawName,
    this.qty,
    required this.priceRetail,
    required this.pricePromo,
    required this.pctOff,
    this.snapshotDate,
  });

  factory PromoItem.fromJson(Map<String, dynamic> json) {
    return PromoItem(
      rawName: json['raw_name'] as String? ?? '',
      qty: json['qty'] as Map<String, dynamic>?,
      priceRetail: (json['price_retail'] as num?)?.toDouble() ?? 0,
      pricePromo: (json['price_promo'] as num?)?.toDouble() ?? 0,
      pctOff: (json['pct_off'] as num?)?.toInt() ?? 0,
      snapshotDate: json['snapshot_date'] as String?,
    );
  }
}

class PromoChain {
  final String chainSlug;
  final String chainName;
  final int nStores;
  final String? latestSnapshot;
  final List<PromoItem> items;

  const PromoChain({
    required this.chainSlug,
    required this.chainName,
    required this.nStores,
    this.latestSnapshot,
    required this.items,
  });

  factory PromoChain.fromJson(Map<String, dynamic> json) {
    return PromoChain(
      chainSlug: json['chain_slug'] as String? ?? '',
      chainName: json['chain_name'] as String? ?? '',
      nStores: (json['n_stores'] as num?)?.toInt() ?? 0,
      latestSnapshot: json['latest_snapshot'] as String?,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => PromoItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class PromotionsResponse {
  final int count;
  final String? latestSnapshot;
  final int maxStaleDays;
  final String? query;
  final List<PromoChain> chains;

  const PromotionsResponse({
    required this.count,
    this.latestSnapshot,
    required this.maxStaleDays,
    this.query,
    required this.chains,
  });

  factory PromotionsResponse.fromJson(Map<String, dynamic> json) {
    return PromotionsResponse(
      count: (json['count'] as num?)?.toInt() ?? 0,
      latestSnapshot: json['latest_snapshot'] as String?,
      maxStaleDays: (json['max_stale_days'] as num?)?.toInt() ?? 0,
      query: json['query'] as String?,
      chains: (json['chains'] as List<dynamic>?)
              ?.map((e) => PromoChain.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
