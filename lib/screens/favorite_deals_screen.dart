/// "Discounted favourites near you" — pulls the user's saved favourites and
/// shows which are on promotion within their radius (see /api/favorites/deals).
///
/// Opened from the Favourites sheet and from the daily reminder notification.
/// When opened from a notification (cold start) no location is passed, so the
/// screen resolves it itself: last known GPS → server GeoIP → Sofia default.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../models/favorite_deal.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../services/location_service.dart';
import 'search_results_screen.dart';

class FavoriteDealsScreen extends StatefulWidget {
  /// Optional starting location. When null the screen resolves it (used by the
  /// notification deep-link, which has no app state to hand over).
  final double? lat;
  final double? lng;
  final double? radiusKm;

  const FavoriteDealsScreen({super.key, this.lat, this.lng, this.radiusKm});

  @override
  State<FavoriteDealsScreen> createState() => _FavoriteDealsScreenState();
}

class _FavoriteDealsScreenState extends State<FavoriteDealsScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  List<FavoriteDeal> _deals = [];
  int _favCount = 0;
  double _lat = 42.6977, _lng = 23.3219; // Sofia default
  double _radiusKm = Config.defaultRadiusKm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _resolveLocation() async {
    _radiusKm = widget.radiusKm ?? await LocationService().getRadius();
    if (widget.lat != null && widget.lng != null) {
      _lat = widget.lat!;
      _lng = widget.lng!;
      return;
    }
    try {
      final Position? pos = await LocationService().getLastPosition();
      if (pos != null) {
        _lat = pos.latitude;
        _lng = pos.longitude;
        return;
      }
    } catch (_) {/* fall through to GeoIP */}
    try {
      final ip = await _api.iploc();
      if (ip != null) {
        _lat = ip.lat;
        _lng = ip.lng;
      }
    } catch (_) {/* keep Sofia default */}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _resolveLocation();
      final favs = await LocalStore.favorites();
      _favCount = favs.length;
      if (favs.isEmpty) {
        setState(() {
          _deals = [];
          _loading = false;
        });
        return;
      }
      final deals = await _api.favoriteDeals(
        favorites: favs,
        lat: _lat,
        lng: _lng,
        radiusKm: _radiusKm,
      );
      if (!mounted) return;
      setState(() {
        _deals = deals;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _openDeal(FavoriteDeal d) {
    final q = d.query.trim().isEmpty ? d.name : d.query;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(
          query: q,
          displayQuery: q,
          lat: _lat,
          lng: _lng,
          radiusKm: _radiusKm,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Намаления на любими'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(cs),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _fullMessage(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'Опитай пак',
        onAction: _load,
      );
    }
    if (_favCount == 0) {
      return _fullMessage(
        icon: Icons.favorite_border_rounded,
        title: 'Нямаш любими продукти още',
        subtitle: 'Маркирай продукти със сърце ♥, за да ги следим за намаления близо до теб.',
      );
    }
    if (_deals.isEmpty) {
      return _fullMessage(
        icon: Icons.search_off_rounded,
        title: 'В момента няма намаления на любимите ти',
        subtitle: 'Проверихме $_favCount любими в радиус ${_radiusKm.toStringAsFixed(_radiusKm % 1 == 0 ? 0 : 1)} км. Дръпни надолу, за да провериш пак.',
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _deals.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
            child: Text(
              '${_deals.length} намаления на любимите ти в радиус ${_radiusKm.toStringAsFixed(_radiusKm % 1 == 0 ? 0 : 1)} км',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          );
        }
        return _DealCard(deal: _deals[i - 1], onTap: () => _openDeal(_deals[i - 1]));
      },
    );
  }

  Widget _fullMessage({
    required IconData icon,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final cs = Theme.of(context).colorScheme;
    // Wrap in a scroll view so pull-to-refresh works even on the empty states.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Icon(icon, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant)),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          Center(child: FilledButton(onPressed: onAction, child: Text(actionLabel))),
        ],
      ],
    );
  }
}

class _DealCard extends StatelessWidget {
  final FavoriteDeal deal;
  final VoidCallback onTap;

  const _DealCard({required this.deal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Discount badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFD23B3B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('-${deal.pctOff}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deal.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text('❤ ${deal.favorite}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('${deal.pricePromo.toStringAsFixed(2)} €',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.primary)),
                        const SizedBox(width: 8),
                        Text('${deal.priceRetail.toStringAsFixed(2)} €',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                                decoration: TextDecoration.lineThrough)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.storefront_outlined, size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('${deal.chainName} · на ${deal.distKm.toStringAsFixed(1)} км',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
