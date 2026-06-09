/// Models for the /api/basket endpoint response.

class BasketBreakdownItem {
  final String query;
  final double price;
  final String? name;
  final String? snapshotDate;

  const BasketBreakdownItem({
    required this.query,
    required this.price,
    this.name,
    this.snapshotDate,
  });

  factory BasketBreakdownItem.fromJson(Map<String, dynamic> json) {
    return BasketBreakdownItem(
      query: json['query'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      name: json['name'] as String?,
      snapshotDate: json['snapshot_date'] as String?,
    );
  }
}

class BasketStore {
  final int storeId;
  final String chainSlug;
  final String chainName;
  final String address;
  final double lat;
  final double lng;
  final int distM;
  final int itemsFound;
  final int itemsTotal;
  final double total;
  final bool complete;
  final List<BasketBreakdownItem> breakdown;

  const BasketStore({
    required this.storeId,
    required this.chainSlug,
    required this.chainName,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distM,
    required this.itemsFound,
    required this.itemsTotal,
    required this.total,
    required this.complete,
    required this.breakdown,
  });

  factory BasketStore.fromJson(Map<String, dynamic> json) {
    return BasketStore(
      storeId: (json['store_id'] as num?)?.toInt() ?? 0,
      chainSlug: json['chain_slug'] as String? ?? '',
      chainName: json['chain_name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      distM: (json['dist_m'] as num?)?.toInt() ?? 0,
      itemsFound: (json['items_found'] as num?)?.toInt() ?? 0,
      itemsTotal: (json['items_total'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      complete: json['complete'] as bool? ?? false,
      breakdown: (json['breakdown'] as List<dynamic>?)
              ?.map((e) => BasketBreakdownItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String get distanceText {
    if (distM < 1000) return '${distM} m';
    return '${(distM / 1000).toStringAsFixed(1)} km';
  }
}

class MixedOptimalItem {
  final String query;
  final double price;
  final String chainName;
  final int storeId;
  final int distM;

  const MixedOptimalItem({
    required this.query,
    required this.price,
    required this.chainName,
    required this.storeId,
    required this.distM,
  });

  factory MixedOptimalItem.fromJson(Map<String, dynamic> json) {
    return MixedOptimalItem(
      query: json['query'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      chainName: json['chain_name'] as String? ?? '',
      storeId: (json['store_id'] as num?)?.toInt() ?? 0,
      distM: (json['dist_m'] as num?)?.toInt() ?? 0,
    );
  }
}

class MixedOptimal {
  final List<MixedOptimalItem> breakdown;
  final double total;
  final int storesCount;
  final int itemsFound;
  final int itemsTotal;
  final bool complete;

  const MixedOptimal({
    required this.breakdown,
    required this.total,
    required this.storesCount,
    required this.itemsFound,
    required this.itemsTotal,
    required this.complete,
  });

  factory MixedOptimal.fromJson(Map<String, dynamic> json) {
    return MixedOptimal(
      breakdown: (json['breakdown'] as List<dynamic>?)
              ?.map((e) => MixedOptimalItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: (json['total'] as num?)?.toDouble() ?? 0,
      storesCount: (json['stores_count'] as num?)?.toInt() ?? 0,
      itemsFound: (json['items_found'] as num?)?.toInt() ?? 0,
      itemsTotal: (json['items_total'] as num?)?.toInt() ?? 0,
      complete: json['complete'] as bool? ?? false,
    );
  }
}

class BasketResponse {
  final List<String> items;
  final int count;
  final List<BasketStore> stores;
  final MixedOptimal? mixedOptimal;

  const BasketResponse({
    required this.items,
    required this.count,
    required this.stores,
    this.mixedOptimal,
  });

  factory BasketResponse.fromJson(Map<String, dynamic> json) {
    return BasketResponse(
      items: (json['items'] as List<dynamic>?)?.cast<String>() ?? [],
      count: (json['count'] as num?)?.toInt() ?? 0,
      stores: (json['stores'] as List<dynamic>?)
              ?.map((e) => BasketStore.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      mixedOptimal: json['mixed_optimal'] != null
          ? MixedOptimal.fromJson(json['mixed_optimal'])
          : null,
    );
  }
}
