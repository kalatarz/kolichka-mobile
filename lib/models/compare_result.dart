/// Models for the /api/compare endpoint response.

class Qty {
  final num value;
  final String unit;
  final int? grams;

  const Qty({required this.value, required this.unit, this.grams});

  factory Qty.fromJson(Map<String, dynamic> json) {
    return Qty(
      value: (json['value'] as num?) ?? 0,
      unit: json['unit'] as String? ?? '',
      grams: json['grams'] != null ? (json['grams'] as num).toInt() : null,
    );
  }

  @override
  String toString() => '$value $unit';
}

class ChainPrice {
  final String chainSlug;
  final String chainName;
  final double minPrice;
  final double? priceRetail;
  final String? snapshotDate;
  final int? nStores;

  const ChainPrice({
    required this.chainSlug,
    required this.chainName,
    required this.minPrice,
    this.priceRetail,
    this.snapshotDate,
    this.nStores,
  });

  factory ChainPrice.fromJson(Map<String, dynamic> json) {
    return ChainPrice(
      chainSlug: json['chain_slug'] as String? ?? '',
      chainName: json['chain_name'] as String? ?? '',
      minPrice: (json['min_price'] as num?)?.toDouble() ?? 0,
      priceRetail: json['price_retail'] != null ? (json['price_retail'] as num).toDouble() : null,
      snapshotDate: json['snapshot_date'] as String?,
      nStores: json['n_stores'] != null ? (json['n_stores'] as num).toInt() : null,
    );
  }

  bool get isPromo => priceRetail != null && minPrice < priceRetail!;

  int? get pctOff {
    if (!isPromo) return null;
    return ((1 - minPrice / priceRetail!) * 100).round();
  }
}

class Spread {
  final double min;
  final double max;
  final int pct;

  const Spread({required this.min, required this.max, required this.pct});

  factory Spread.fromJson(Map<String, dynamic> json) {
    return Spread(
      min: (json['min'] as num?)?.toDouble() ?? 0,
      max: (json['max'] as num?)?.toDouble() ?? 0,
      pct: (json['pct'] as num?)?.toInt() ?? 0,
    );
  }
}

class MatchResult {
  final int canonicalId;
  final String display;
  final Qty? qty;
  final int nChains;
  final ChainPrice cheapest;
  final Spread? spread;
  final List<ChainPrice> chains;

  const MatchResult({
    required this.canonicalId,
    required this.display,
    this.qty,
    required this.nChains,
    required this.cheapest,
    this.spread,
    required this.chains,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final chains = (json['chains'] as List<dynamic>?)
            ?.map((e) => ChainPrice.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return MatchResult(
      canonicalId: (json['canonical_id'] as num?)?.toInt() ?? 0,
      display: json['display'] as String? ?? '',
      qty: json['qty'] != null ? Qty.fromJson(json['qty']) : null,
      nChains: (json['n_chains'] as num?)?.toInt() ?? chains.length,
      cheapest: json['cheapest'] != null
          ? ChainPrice.fromJson(json['cheapest'])
          : (chains.isNotEmpty
              ? chains.first
              : const ChainPrice(chainSlug: '', chainName: '—', minPrice: 0)),
      spread: json['spread'] != null ? Spread.fromJson(json['spread']) : null,
      chains: chains,
    );
  }
}

class LooseResult {
  final String chainSlug;
  final String chainName;
  final String rawName;
  final Qty? qty;
  final double price;
  final double? priceRetail;
  final String? snapshotDate;
  final String? address;
  final int? distM;

  const LooseResult({
    required this.chainSlug,
    required this.chainName,
    required this.rawName,
    this.qty,
    required this.price,
    this.priceRetail,
    this.snapshotDate,
    this.address,
    this.distM,
  });

  factory LooseResult.fromJson(Map<String, dynamic> json) {
    return LooseResult(
      chainSlug: json['chain_slug'] as String? ?? '',
      chainName: json['chain_name'] as String? ?? '',
      rawName: json['raw_name'] as String? ?? '',
      qty: json['qty'] != null ? Qty.fromJson(json['qty']) : null,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      priceRetail: json['price_retail'] != null ? (json['price_retail'] as num).toDouble() : null,
      snapshotDate: json['snapshot_date'] as String?,
      address: json['address'] as String?,
      distM: json['dist_m'] != null ? (json['dist_m'] as num).toInt() : null,
    );
  }
}

class CompareResponse {
  final String? query;
  final Map<String, dynamic>? category;
  final int count;
  final List<MatchResult> matches;
  final List<LooseResult> loose;

  const CompareResponse({
    this.query,
    this.category,
    required this.count,
    required this.matches,
    required this.loose,
  });

  factory CompareResponse.fromJson(Map<String, dynamic> json) {
    return CompareResponse(
      query: json['query'] as String?,
      category: json['category'] as Map<String, dynamic>?,
      count: (json['count'] as num?)?.toInt() ?? 0,
      matches: (json['matches'] as List<dynamic>?)
              ?.map((e) => MatchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      loose: (json['loose'] as List<dynamic>?)
             ?.map((e) => LooseResult.fromJson(e as Map<String, dynamic>))
             .toList() ??
          [],
    );
  }
}
