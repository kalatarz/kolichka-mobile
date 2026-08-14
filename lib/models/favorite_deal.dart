/// A discounted favourite product found near the user.
///
/// Returned by `POST /api/favorites/deals`, which matches the user's saved
/// favourites against current promotions within their radius — the same
/// matching the web uses to push "your favourite X is −30% nearby" alerts.
class FavoriteDeal {
  /// The favourite (query string) that matched this deal.
  final String favorite;

  /// The discounted product's raw name as it appears in the store.
  final String name;
  final String chainName;
  final String chainSlug;
  final double pricePromo;
  final double priceRetail;
  final int pctOff;

  /// Distance to the nearest store carrying this deal, in km.
  final double distKm;

  /// Deep-link search query so tapping the deal opens the right results.
  final String query;

  const FavoriteDeal({
    required this.favorite,
    required this.name,
    required this.chainName,
    required this.chainSlug,
    required this.pricePromo,
    required this.priceRetail,
    required this.pctOff,
    required this.distKm,
    required this.query,
  });

  factory FavoriteDeal.fromJson(Map<String, dynamic> j) => FavoriteDeal(
        favorite: j['favorite'] as String? ?? '',
        name: j['name'] as String? ?? '',
        chainName: j['chain_name'] as String? ?? '',
        chainSlug: j['chain_slug'] as String? ?? '',
        pricePromo: (j['price_promo'] as num?)?.toDouble() ?? 0,
        priceRetail: (j['price_retail'] as num?)?.toDouble() ?? 0,
        pctOff: (j['pct_off'] as num?)?.toInt() ?? 0,
        distKm: (j['dist_km'] as num?)?.toDouble() ?? 0,
        query: j['query'] as String? ?? '',
      );
}
