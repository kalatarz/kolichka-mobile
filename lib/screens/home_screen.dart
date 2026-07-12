/// Home screen — redesigned to match the web v2 interface.
///
/// Layout mirrors the web version:
///   1. Brand header bar (🛒 Количка + action buttons)
///   2. Location chip (tappable, opens location filters)
///   3. Search bar with "Търси" button
///   4. Category groups (expandable, two-level drill-down)
///   5. Results area (inline product comparison results)
///   6. Basket FAB (floating action button)
///
/// The map is accessible via a dedicated screen from settings/location panel.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../models/category.dart';
import '../models/store.dart';
import '../models/compare_result.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/local_store.dart';
import '../services/notify_service.dart';
import '../widgets/subscribe_sheet.dart';
import '../widgets/feedback_sheet.dart';
import '../services/analytics.dart';
import '../main.dart';
import '../widgets/brand_header.dart';
import '../widgets/location_chip.dart';
import '../widgets/search_bar.dart';
import '../widgets/radius_segment.dart';
import '../data/cat_groups.dart';
import '../widgets/chain_colors.dart';
import '../widgets/item_emoji.dart';
import 'basket_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';
import 'location_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final ApiService _api = ApiService();
  final LocationService _location = LocationService();
    final GlobalKey _resultsKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Location state
  double _lat = 42.7; // Sofia default
  double _lng = 23.3;
  String? _locationLabel;
  bool _isLoading = true;
  bool _locationError = false;
  bool _gpsFixed = false; // got a precise device-GPS fix (vs IP/saved fallback)
  bool _locating = false;  // re-entrancy guard: a location fetch is in flight

  // Search state
  double _radiusKm = Config.defaultRadiusKm;

  // Category state
  List<Category> _categories = [];
  int? _openGroupIndex;       // which group is expanded
  String? _selectedCategory;   // selected subcategory slug

  // Results state (inline, like web)
  CompareResponse? _currentResult;
  bool _searching = false;
  String? _searchError;
  String? _lastQuery;
  bool _promoMode = false; // current results are promotions (red label)
  final Set<String> _chainFilter = <String>{}; // selected chain slugs in results

  // Bottom-nav tab: 0 = Начало (home), 1 = Промоции (dedicated promo browser).
  int _tab = 0;
  // Промоции tab state — its own promo list + live client-side text filter.
  final TextEditingController _promoSearchController = TextEditingController();
  List<MatchResult> _promoItems = [];
  bool _promoTabLoading = false;
  String? _promoTabError;

  // Stores count for display
  int _storesCount = 0;

  // Basket FAB badge
  int _basketCount = 0;

  // Favorites (lowercased names) for quick lookup while rendering cards
  Set<String> _favorites = <String>{};

  // Gently propose the email subscription — but only once the user is actually
  // engaged: they've come back (≥2 sessions) AND used the app for a few hours
  // total. Shown once per qualifying session after a short dwell, with a 7-day
  // cool-down; never if already subscribed. Keeps brand-new users from being
  // hit on their first screen and bouncing.
  Timer? _subNudgeTimer;
  static const int _subMinLaunches = 2;
  static const int _subMinHoursSinceFirstSeen = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    _refreshLocalState();
  }

  /// Ask for a rating only after the user has had several *successful* searches
  /// (≥4 with results) — engaged + getting value = the sweet spot. Shown once,
  /// after a short delay so they see the results first; the rating sheet itself
  /// routes 1–3★ to private feedback (no public 1-star).
  Future<void> _maybePromptFeedback() async {
    if (await LocalStore.feedbackPromptDone()) return;
    final wins = await LocalStore.bumpSearchWins();
    if (wins < 4) return;
    await LocalStore.setFeedbackPromptDone();
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    Analytics.instance.track('feedback_prompt_shown', {'after_searches': wins});
    showRatingSheet(context);
  }

  /// Schedule the one-shot email-subscription nudge after a dwell period.
  void _scheduleSubscribeNudge() {
    _subNudgeTimer?.cancel();
    _subNudgeTimer = Timer(const Duration(seconds: 45), () async {
      if (!mounted) return;
      if (await LocalStore.subscribeDone()) return;
      // Only nudge engaged users: returned at least once AND a few hours in.
      final launches = await LocalStore.launchCount();
      final firstSeen = await LocalStore.firstSeenAt();
      final now = DateTime.now().millisecondsSinceEpoch;
      final hoursSinceFirstSeen =
          firstSeen == 0 ? 0.0 : (now - firstSeen) / (60 * 60 * 1000);
      if (launches < _subMinLaunches ||
          hoursSinceFirstSeen < _subMinHoursSinceFirstSeen) {
        return;
      }
      final last = await LocalStore.subscribePromptedAt();
      const weekMs = 7 * 24 * 60 * 60 * 1000;
      if (last != 0 && now - last < weekMs) return; // cool-down
      if (!mounted) return;
      await LocalStore.markSubscribePrompted(now);
      Analytics.instance.track('subscribe_nudge_shown');
      showSubscribeSheet(context);
    });
  }

  @override
  void dispose() {
    _subNudgeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _promoSearchController.dispose();
    _scrollController.dispose();
    _api.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user comes back to the app — e.g. after toggling GPS in Android
    // settings — retry device location ONLY if we never got a precise fix.
    // CRITICAL: check availability FIRST (permission granted + service on) and
    // only then upgrade. Calling _upgradeLocation() unconditionally on every
    // resume made getCurrentPosition() re-invoke requestPermission()/the GPS
    // stack each time; with GPS off (or permission denied) that re-popped the
    // system dialog on every return and could wedge the geolocator plugin,
    // leaving the whole app unresponsive to taps. isLocationAvailable() never
    // shows a dialog and returns false when GPS is off, so we simply skip.
    if (state == AppLifecycleState.resumed && !_gpsFixed && !_locating) {
      _location.isLocationAvailable().then((ok) {
        if (ok && mounted && !_gpsFixed && !_locating) _upgradeLocation();
      }).catchError((_) {});
    }
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    try {
      // 1) Instant: render with the last saved location (no GPS wait, so the
      //    initial open never times out). Falls back to the Sofia default.
      final saved = await _location.getLastPosition();
      final savedAddress = await _location.getLastAddress();
      // Restore the previously chosen search radius so 1/3/5/10 km persists
      // across launches (and the Location screen opens with the right value).
      _radiusKm = await _location.getRadius();
      String? ipLabel;
      if (saved != null) {
        _lat = saved.latitude;
        _lng = saved.longitude;
      } else {
        // No saved location yet → approximate from the client IP (server GeoIP)
        // so the app works even when device location is off. Precise GPS, if
        // available, snaps over this in _upgradeLocation().
        final ip = await _api.iploc();
        if (ip != null) {
          _lat = ip.lat;
          _lng = ip.lng;
          ipLabel = ip.display;
        }
      }

      final results = await Future.wait([
        _api.getCategories(),
        _api.getNearbyStores(_lat, _lng, radiusKm: _radiusKm),
      ]);

      setState(() {
        _categories = results[0] as List<Category>;
        final stores = results[1] as List<Store>;
        _storesCount = stores.length;
        _locationLabel = savedAddress ?? ipLabel ?? 'Моята локация';
        _isLoading = false;
        _locationError = false;
      });
      await _refreshLocalState();
      // Auto-load nearby promotions on open (geo-based) so the home isn't empty.
      if (_currentResult == null && !_searching) _openPromotions();
      _scheduleSubscribeNudge();
      // 2) Background: get a precise GPS fix and snap the UI to it.
      _upgradeLocation();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _locationError = true;
      });
    }
  }

  /// Background-fetch a precise GPS fix (high accuracy) and snap to it. Never
  /// blocks startup; on permission-deny or timeout it silently keeps the
  /// last-known location.
  Future<void> _upgradeLocation() async {
    if (_locating) return; // never run two location fetches at once
    _locating = true;
    try {
      // CRITICAL: never call getCurrentPosition() unless location is actually
      // available. With GPS off, getCurrentPosition() makes Google Play Services
      // pop its "Location off" warning activity OVER the app (confirmed via
      // logcat: gms LocationOffWarningActivity) — on some devices it sits on top
      // and blocks all taps. isLocationAvailable() only reads the service +
      // permission state (never shows a dialog), so this is the safe gate. It
      // guards BOTH the cold-start (_init) and resume callers.
      if (!await _location.isLocationAvailable()) return;
      final pos = await _location.getCurrentPosition();
      if (!mounted) return;
      Analytics.instance.track('location_ok');
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _gpsFixed = true; // precise fix obtained → stop retrying on resume
      });
      // Reverse-geocode to a real area name (e.g. "Малинова долина", "Сандански")
      // instead of a generic placeholder. Falls back to the existing label.
      final area = await _api.reverseArea(pos.latitude, pos.longitude);
      final label = (area != null && area.isNotEmpty)
          ? area
          : (_locationLabel ?? 'Моята локация');
      if (mounted) setState(() => _locationLabel = label);
      await _location.savePosition(pos, address: label);
      try {
        final stores = await _api.getNearbyStores(_lat, _lng, radiusKm: _radiusKm);
        if (mounted) setState(() => _storesCount = stores.length);
      } catch (_) {}
      // If the home is still showing the auto-loaded promos (user hasn't
      // searched), refresh them for the precise GPS location.
      if (mounted && _promoMode) _openPromotions();
    } catch (_) {
      Analytics.instance.track('location_fail');
    } finally {
      _locating = false;
    }
  }

  /// Handle search — either direct product query or category selection.
  Future<void> _performSearch(String query, {String? displayQuery}) async {
    if (_lat == 0 && _lng == 0) return;

    setState(() {
      _searching = true;
      _searchError = null;
      _promoMode = false;
      _lastQuery = displayQuery ?? query;
      // NB: do NOT clear _chainFilter here — it is the persistent store filter
      // chosen on the Location screen and must apply across searches.
    });
    Analytics.instance.track('search', {
      'kind': query.startsWith('cat:') ? 'category' : 'text',
      if (query.startsWith('cat:')) 'slug': query.substring(4),
    });

    try {
      final result = await _api.compare(
        query: query,
        lat: _lat,
        lng: _lng,
        radiusKm: _radiusKm,
      );
      setState(() {
        _currentResult = result;
        _searching = false;
      });
      final hits = result.matches.length + result.loose.length;
      Analytics.instance.track('saw_prices', {
        'results': hits,
        'matches': result.matches.length,
      });
      // Feedback "sweet spot": only after several searches that actually found
      // prices (a good experience) do we ask for a rating — never on first use
      // or on an empty result, so we don't provoke a frustrated low review.
      if (hits > 0) _maybePromptFeedback();

      if (_resultsKey.currentContext != null) {
        Scrollable.ensureVisible(
          _resultsKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      setState(() {
        _searchError = e.toString();
        _searching = false;
      });
    }
  }

  /// Web v2 parity: toggle group → show/hide subcats. Auto-select first category on open.
  void _toggleGroup(int index) {
    final wasOpen = _openGroupIndex == index;

    setState(() {
      if (wasOpen) {
        // Collapsing: hide subcats, keep search results visible
        _openGroupIndex = null;
        _selectedCategory = null;
      } else {
        // Opening: show this group's subcats, auto-select first category → fire search
        _openGroupIndex = index;
        final slugs = kCatGroups[index].slugs
            .where((s) => _categories.any((c) => c.slug == s))
            .toList();
        if (slugs.isNotEmpty) {
          final firstSlug = slugs.first;
          final firstCat = _categories.firstWhere((c) => c.slug == firstSlug);
          _selectedCategory = firstSlug;
          // Auto-fire search for first category (Web v2 behavior)
          _performSearch('cat:$firstSlug', displayQuery: firstCat.label);
        }
      }
    });
  }


  Future<void> _openLocationSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => LocationSettingsScreen(
          lat: _lat,
          lng: _lng,
          radiusKm: _radiusKm,
          locationLabel: _locationLabel,
          selectedChains: Set.from(_chainFilter),
        ),
      ),
    );
    if (result != null && mounted) {
      bool locationMoved = false;
      setState(() {
        if (result['radiusKm'] != null) {
          _radiusKm = result['radiusKm'];
        }
        // Apply the picked coordinates so the chosen location actually takes
        // effect (previously lat/lng were dropped, so picking a city did nothing).
        if (result['lat'] != null && result['lng'] != null) {
          final newLat = (result['lat'] as num).toDouble();
          final newLng = (result['lng'] as num).toDouble();
          if (newLat != _lat || newLng != _lng) locationMoved = true;
          _lat = newLat;
          _lng = newLng;
        }
        if (result['label'] != null && (result['label'] as String).isNotEmpty) {
          _locationLabel = result['label'];
        }
        if (result['selectedChains'] != null) {
          _chainFilter
            ..clear()
            ..addAll(result['selectedChains'] as Set<String>);
        }
      });
      // Persist the chosen location so it survives app restarts.
      if (locationMoved) {
        await _location.savePosition(
          Position(
            latitude: _lat, longitude: _lng, timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, heading: 0, speed: 0,
            speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
          ),
          address: _locationLabel,
        );
        try {
          final stores = await _api.getNearbyStores(_lat, _lng, radiusKm: _radiusKm);
          if (mounted) setState(() => _storesCount = stores.length);
        } catch (_) {}
      }
      // The Промоции tab's cached list is now stale for the new location.
      _promoItems = [];
      if (_tab == 1) _loadPromoTab(force: true);
      // Re-run the current query with the updated location / radius / chain filter.
      if (_promoMode) {
        _openPromotions();
      } else if (_lastQuery != null) {
        _performSearch(_lastQuery!, displayQuery: _lastQuery);
      }
    }
  }


  /// Open location/settings panel (bottom sheet).
  void _openLocationPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => _LocationFilterSheet(
        lat: _lat,
        lng: _lng,
        radiusKm: _radiusKm,
        locationLabel: _locationLabel ?? 'Моето местоположение',
        storesCount: _storesCount,
        onRadiusChanged: (km) {
          setState(() => _radiusKm = km);
          if (_lastQuery != null) {
            _performSearch(_lastQuery!, displayQuery: _lastQuery);
          }
        },
        onLocationChanged: (String label, double newLat, double newLng) async {
          setState(() {
            _lat = newLat;
            _lng = newLng;
            _locationLabel = label;
          });
          await _location.savePosition(
            Position(
              latitude: newLat,
              longitude: newLng,
              timestamp: DateTime.now(),
              accuracy: 0, altitude: 0, heading: 0,
              speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
            ),
            address: label,
          );
          // Reload stores with new location
          try {
            final stores = await _api.getNearbyStores(newLat, newLng, radiusKm: _radiusKm);
            setState(() => _storesCount = stores.length);
          } catch (_) {}

          if (_lastQuery != null) {
            _performSearch(_lastQuery!, displayQuery: _lastQuery);
          }
        },
      ),
    );
  }

  /// Navigate to basket screen.
  Future<void> _openBasket() async {
    Analytics.instance.track('open_basket');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => BasketScreen(
          lat: _lat,
          lng: _lng,
          radiusKm: _radiusKm,
        ),
      ),
    );
    await _refreshLocalState();
  }

  /// Load promotions inline as regular product cards (no separate screen).
  /// Promo offers from every nearby chain are flattened into synthetic
  /// MatchResults, sorted by biggest discount first, and rendered through the
  /// same _ProductCard pipeline as a normal search — so they can be added to
  /// the basket / favourites and opened on the map like any other item.
  /// Fetch nearby promotions and flatten them into MatchResult cards, biggest
  /// discount first. Shared by the home auto-load and the Промоции tab.
  Future<List<MatchResult>> _fetchPromoMatches() async {
    final promos = await _api.promotions(lat: _lat, lng: _lng, radiusKm: _radiusKm);
    final matches = <MatchResult>[];
    for (final ch in promos.chains) {
      for (final it in ch.items) {
        final cp = ChainPrice(
          chainSlug: ch.chainSlug,
          chainName: ch.chainName,
          minPrice: it.pricePromo,
          priceRetail: it.priceRetail,
          snapshotDate: it.snapshotDate ?? ch.latestSnapshot,
          nStores: ch.nStores,
        );
        matches.add(MatchResult(
          canonicalId: -1,
          display: it.rawName,
          qty: it.qty != null
              ? Qty(
                  value: (it.qty!['value'] as num?) ?? 0,
                  unit: it.qty!['unit'] as String? ?? '')
              : null,
          nChains: 1,
          cheapest: cp,
          chains: [cp],
        ));
      }
    }
    matches.sort((a, b) => (b.cheapest.pctOff ?? 0).compareTo(a.cheapest.pctOff ?? 0));
    return matches;
  }

  /// Home "Промоции" view (inline in the results area, red label).
  Future<void> _openPromotions() async {
    if (_lat == 0 && _lng == 0) return;
    Analytics.instance.track('open_promotions');
    setState(() {
      _searching = true;
      _searchError = null;
      _promoMode = true;
      _lastQuery = 'Промоции';
      _selectedCategory = null;
      _openGroupIndex = null;
      _chainFilter.clear();
    });
    try {
      final matches = await _fetchPromoMatches();
      if (!mounted) return;
      setState(() {
        _currentResult = CompareResponse(
            count: matches.length, matches: matches, loose: const []);
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e.toString();
        _searching = false;
      });
    }
  }

  /// Load (or reload) the dedicated Промоции tab's promo list.
  Future<void> _loadPromoTab({bool force = false}) async {
    if (_lat == 0 && _lng == 0) return;
    if (_promoTabLoading) return;
    if (_promoItems.isNotEmpty && !force) return;
    setState(() {
      _promoTabLoading = true;
      _promoTabError = null;
    });
    try {
      final matches = await _fetchPromoMatches();
      if (!mounted) return;
      setState(() {
        _promoItems = matches;
        _promoTabLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _promoTabError = e.toString();
        _promoTabLoading = false;
      });
    }
  }

  /// Children of the Промоции tab: its own search bar + the filtered promo list.
  List<Widget> _buildPromoTabChildren() {
    return [
      KolichkaSearchBar(
        controller: _promoSearchController,
        suggestions: const [], // no category suggestions here
        hintText: 'Търси в промоциите…',
        onSearch: (_) {}, // filtering is live (client-side) as the user types
        onClear: () {},
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _loadPromoTab(force: true),
          child: _buildPromoTabBody(),
        ),
      ),
    ];
  }

  Widget _buildPromoTabBody() {
    final cs = Theme.of(context).colorScheme;
    if (_promoTabLoading && _promoItems.isEmpty) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator(color: cs.primary)),
        ),
      ]);
    }
    if (_promoTabError != null && _promoItems.isEmpty) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('Неуспешно зареждане на промоциите.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _loadPromoTab(force: true),
                child: const Text('Опитай отново'),
              ),
            ]),
          ),
        ),
      ]);
    }
    // Live filter: rebuild ONLY this list as the user types (the search field
    // itself is never rebuilt, so the keyboard stays put).
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _promoSearchController,
      builder: (context, value, _) {
        final q = value.text.trim().toLowerCase();
        final items = q.isEmpty
            ? _promoItems
            : _promoItems
                .where((m) => m.display.toLowerCase().contains(q))
                .toList();
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: items.length + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: const Color(0xFFD23B3B),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('🔥 ПРОМОЦИИ',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3)),
                  ),
                  const SizedBox(width: 8),
                  Text('${items.length} оферти',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              );
            }
            final match = items[i - 1];
            return _ProductCard(
              match: match,
              isFav: _favorites.contains(match.display.trim().toLowerCase()),
              onAddToBasket: () => _addToBasket(match.display),
              onToggleFav: () => _toggleFav(match.display),
              onOpenMap: () => _openMap(productQuery: match.display),
            );
          },
        );
      },
    );
  }

  /// Open the store map.
  void _openMap({String? productQuery}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => MapScreen(
          lat: _lat,
          lng: _lng,
          radiusKm: _radiusKm,
          productQuery: productQuery,
        ),
      ),
    );
  }

  /// Navigate to settings screen.
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => const SettingsScreen()),
    );
  }

  /// Reload basket count + favorites set from local storage.
  Future<void> _refreshLocalState() async {
    final count = await LocalStore.basketCount();
    final favs = await LocalStore.favorites();
    if (!mounted) return;
    setState(() {
      _basketCount = count;
      _favorites = favs.map((e) => e.trim().toLowerCase()).toSet();
    });
  }

  /// Add a product to the persistent basket.
  Future<void> _addToBasket(String name) async {
    final added = await LocalStore.addToBasket(name);
    Analytics.instance.track('add_to_basket', {'new': added});
    await _refreshLocalState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? 'Добавено в кошницата: $name' : '„$name" вече е в кошницата'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(label: 'Кошница', onPressed: _openBasket),
      ),
    );
  }

  /// Toggle a product as favorite (persisted).
  Future<void> _toggleFav(String name) async {
    final nowFav = await LocalStore.toggleFavorite(name);
    Analytics.instance.track(nowFav ? 'favorite_add' : 'favorite_remove');
    await _refreshLocalState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nowFav ? 'Добавено в любими: $name' : 'Премахнато от любими'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Open the favorites bottom sheet.
  void _openFavorites() {
    Analytics.instance.track('open_favorites');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => _FavoritesSheet(
        onSearch: (q) {
          Navigator.pop(ctx);
          _searchController.text = q;
          _performSearch(q);
        },
        onChanged: _refreshLocalState,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                SizedBox(height: 16),
                Text('Зареждане...', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    if (_locationError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_off, size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                const Text(
                  'Възникна проблем при зареждането',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Провери връзката си и опитай отново.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _init,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Опитай отново'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 1. Brand header
            BrandHeader(
              onThemeToggle: () {
                final tp = ThemeProvider.instance;
                if (tp != null) {
                  tp.toggle();
                }
              },
              onFavorites: _openFavorites,
            ),

            // 2. Location chip
            LocationChip(
              locationText: _locationLabel != null
                  ? '${_locationLabel!} · $_storesCount магазина'
                  : 'Намери магазини…',
              onTap: _openLocationSettings,
            ),

            // Tab 0 = Начало (home: search + categories + results/top promos).
            // Tab 1 = Промоции (dedicated promo browser with its own search).
            if (_tab == 0) ...[
              // 3. Search bar
              KolichkaSearchBar(
                controller: _searchController,
                suggestions: _categories,
                onSearch: (text) => _performSearch(text),
                onClear: () {
                  setState(() {
                    _currentResult = null;
                    _lastQuery = null;
                    _selectedCategory = null;
                    _openGroupIndex = null;
                  });
                },
              ),

              // Scrollable content area
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _init(),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 80), // space for FAB
                    child: Column(
                      children: [
                        // 4. Category groups
                        _buildCategoryGroups(),

                        // 5. Results area
                        if (_searching)
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                            ),
                          )
                        else if (_searchError != null)
                          _buildSearchError()
                        else if (_currentResult != null)
                          _buildResults(),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              ..._buildPromoTabChildren(),
          ],
        ),
      ),

      // 6. Basket FAB
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openBasket,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.shopping_basket, size: 20),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Кошница', style: TextStyle(fontWeight: FontWeight.w600)),
            if (_basketCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_basketCount',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),

      // Bottom nav bar for quick access
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// Category groups section — horizontal wrap of group chips (mirrors the web
  /// header), with the open group's subcategories shown full-width below.
  /// Compact horizontal group row + category chips + initial articles.
  /// Web v2 parity: groups row always visible, subcats only when group selected.
  Widget _buildCategoryGroups() {
    final groups = <MapEntry<int, CatGroup>>[];
    for (var i = 0; i < kCatGroups.length; i++) {
      final g = kCatGroups[i];
      final hasActive = g.slugs.any((s) => _categories.any((c) => c.slug == s));
      if (hasActive) groups.add(MapEntry(i, g));
    }
    if (groups.isEmpty) return const SizedBox.shrink();

    // Subcats: only show when a group is active (Web v2 behavior)
    final subcatWidgets = <Widget>[];
    if (_openGroupIndex != null && _openGroupIndex! >= 0) {
      final g = kCatGroups[_openGroupIndex!];
      for (final slug in g.slugs) {
        try {
          final cat = _categories.firstWhere((c) => c.slug == slug);
          subcatWidgets.add(_buildSubcatChip(cat, g));
        } catch (_) {}
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text('ГРУПИ',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          SizedBox(
            height: 30,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: groups.length + 1, // +1 for Промоции
              itemBuilder: (ctx, i) {
                // First item is Промоции button (Web v2 parity)
                if (i == 0) {
                  // Highlight the Промоции chip while promotions are the active
                  // view (mirrors the bottom-nav Промоции highlight).
                  final promoActive = _promoMode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: _openPromotions,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(promoActive ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: promoActive ? Colors.orange.shade700 : Colors.transparent,
                            width: 1.2,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('🏷️', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 3),
                          Text('Промоции',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: promoActive ? FontWeight.w700 : FontWeight.w500,
                                color: promoActive ? Colors.orange.shade900 : null,
                              )),
                        ]),
                      ),
                    ),
                  );
                }

                // Group chips
                final idx = groups[i - 1].key;
                final group = groups[i - 1].value;
                final isExpanded = _openGroupIndex == idx;
                final (_, iconColor) = _groupIconWithColor(group.label);
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => _toggleGroup(idx),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isExpanded ? iconColor.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isExpanded ? iconColor : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(group.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 3),
                        Text(
                          group.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isExpanded ? FontWeight.w700 : FontWeight.w500,
                            color: isExpanded ? iconColor : null,
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),

          // SUBCATS — only visible when a group is selected (Web v2 behavior)
          if (subcatWidgets.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: Text('КАТЕГОРИИ',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4,
                      color: Theme.of(context).colorScheme.primary)),
            ),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: subcatWidgets,
            ),
          ],
        ],
      ),
    );
  }

  /// Build a single subcategory chip (Web v2 style).
  Widget _buildSubcatChip(Category cat, CatGroup group) {
    final isSelected = _selectedCategory == cat.slug;
    final (_, iconColor) = _groupIconWithColor(group.label);
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 3),
      child: InkWell(
        onTap: () {
          final catLabel = cat.label;
          setState(() {
            _selectedCategory = (_selectedCategory == cat.slug) ? null : cat.slug;
          });
          // Web v2: subcat click sets query and runs search
          _searchController.text = catLabel;
          _performSearch('cat:${cat.slug}', displayQuery: catLabel);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? iconColor.withOpacity(0.15)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? iconColor : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            cat.emoji != null && cat.emoji!.isNotEmpty ? '${cat.emoji} ${cat.label}' : cat.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? iconColor : null,
            ),
          ),
        ),
      ),
    );
  }

  /// Colorful icon + color for each category group — matches web v2 visual style.
  (IconData icon, Color color) _groupIconWithColor(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (label) {
      case 'Млечни':
        return (Icons.lunch_dining, const Color(0xFF42A5F5)); // milk blue
      case 'Месо и риба':
        return (Icons.set_meal, const Color(0xFFD32F2F)); // meat red
      case 'Плодове и зеленчуци':
        return (Icons.eco, const Color(0xFF43A047)); // fresh green
      case 'Основни':
        return (Icons.kitchen, const Color(0xFFD4A24E)); // warm wheat
      case 'Лакомства':
        return (Icons.cake, const Color(0xFF6D4C41)); // chocolate brown
      case 'Напитки':
        return (Icons.local_bar, const Color(0xFFFF7043)); // drink orange
      case 'Дом и хигиена':
        return (Icons.cleaning_services, const Color(0xFF039BE5)); // blue
      default:
        return (Icons.category, isDark ? Colors.grey.shade400 : Colors.grey.shade600);
    }
  }

  /// Search error display.
  Widget _buildSearchError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _searchError ?? 'Грешка при търсенето',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                if (_lastQuery != null) _performSearch(_lastQuery!);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Опитай отново'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Results section — mirrors web v2 results layout.
  /// Horizontal chain-filter chips above the results (colored dots, like web).
  Widget _buildChainFilter(Map<String, String> chains) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = chains.entries.toList()
      ..sort((a, b) => prettyChainName(a.value).compareTo(prettyChainName(b.value)));
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final slug = entries[i].key;
          final name = prettyChainName(entries[i].value);
          final sel = _chainFilter.contains(slug);
          return InkWell(
            onTap: () => setState(() {
              if (sel) {
                _chainFilter.remove(slug);
              } else {
                _chainFilter.add(slug);
              }
            }),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sel
                    ? chainColor(slug).withOpacity(0.18)
                    : (isDark ? Theme.of(context).colorScheme.outlineVariant : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  width: 1.5,
                  color: sel ? chainColor(slug) : Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: chainColor(slug), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                        color: isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Exact + approximate matches as one list, cheapest first. Loose results
  /// are wrapped as single-chain MatchResults so they render identically.
  /// Restrict a match to the chains selected on the Location screen and
  /// recompute its cheapest price among them. Returns null if none remain, so
  /// the displayed price/chain reflects the user's store filter (not the
  /// global cheapest chain they've excluded).
  MatchResult? _projectToSelectedChains(MatchResult m) {
    final kept = m.chains.where((c) => _chainFilter.contains(c.chainSlug)).toList();
    if (kept.isEmpty) return null;
    kept.sort((a, b) => a.minPrice.compareTo(b.minPrice));
    return MatchResult(
      canonicalId: m.canonicalId,
      display: m.display,
      qty: m.qty,
      nChains: kept.length,
      cheapest: kept.first,
      chains: kept,
      spread: m.spread,
    );
  }

  List<MatchResult> _combinedResults(List<MatchResult> exact, List<LooseResult> loose) {
    final extra = loose.map((l) {
      final cp = ChainPrice(
        chainSlug: l.chainSlug, chainName: l.chainName, minPrice: l.price,
        priceRetail: l.priceRetail, snapshotDate: l.snapshotDate,
      );
      return MatchResult(
        canonicalId: -1, display: l.rawName, qty: l.qty, nChains: 1,
        cheapest: cp, chains: [cp],
      );
    }).toList();
    final all = [...exact, ...extra];
    all.sort((a, b) => a.cheapest.minPrice.compareTo(b.cheapest.minPrice));
    return all;
  }

  Widget _buildResults() {
    final cs = Theme.of(context).colorScheme;
    final result = _currentResult!;
    final matches = result.matches;
    final allLoose = result.loose.where((l) => l.price > 0).toList();
    // Apply the persistent store filter chosen on the Location screen to BOTH
    // exact matches and loose results (empty set = show all chains).
    final filtered = _chainFilter.isEmpty
        ? matches
        : matches
            .map(_projectToSelectedChains)
            .whereType<MatchResult>()
            .toList();
    final loose = _chainFilter.isEmpty
        ? allLoose
        : allLoose.where((l) => _chainFilter.contains(l.chainSlug)).toList();

    if (filtered.isEmpty && loose.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Няма намерени резултати за "${_lastQuery}"',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                'Опитайте с по-голям радиус или друг продукт.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      key: _resultsKey,

      children: [
        // Results header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (_promoMode) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD23B3B),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('🔥 ПРОМОЦИИ',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3)),
                ),
                const SizedBox(width: 8),
                Text('${matches.length} оферти',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ] else
                Text(
                  '${filtered.length + loose.length} резултата за "${_lastQuery}"',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () {
                  if (_promoMode) {
                    _openPromotions();
                  } else if (_lastQuery != null) {
                    _performSearch(_lastQuery!);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),

        // Promotions: offer email alerts for these deals.
        if (_promoMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: InkWell(
              onTap: () => showSubscribeSheet(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mark_email_unread_outlined, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Получавай тези промоции по имейл, веднъж седмично',
                          style: TextStyle(fontSize: 12.5, color: cs.onSurface)),
                    ),
                    Text('Абонирай се',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.primary)),
                  ],
                ),
              ),
            ),
          ),

        if (filtered.isEmpty && _chainFilter.isNotEmpty)
          Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: Text('Няма продукти за избраните вериги.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),

        // All results (exact + approximate) — cheapest first, same card style
        ..._combinedResults(filtered, loose).map((match) => _ProductCard(
              match: match,
              isFav: _favorites.contains(match.display.trim().toLowerCase()),
              onAddToBasket: () => _addToBasket(match.display),
              onToggleFav: () => _toggleFav(match.display),
              onOpenMap: () => _openMap(productQuery: match.display),
            )),

        const SizedBox(height: 16),
      ],
    );
  }

  /// Bottom navigation bar.
  Widget _buildBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).colorScheme.surface : Colors.white,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: BottomNavigationBar(
        // Reflect the active tab (Начало vs the dedicated Промоции browser).
        currentIndex: _tab,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Начало'),
          BottomNavigationBarItem(icon: Icon(Icons.local_offer_outlined), label: 'Промоции'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Настройки'),
        ],
        onTap: (idx) {
          // Dismiss the keyboard when changing sections.
          FocusScope.of(context).unfocus();
          switch (idx) {
            case 0: // Switch to home (keeps its categories + top promos as-is).
              if (_tab != 0) setState(() => _tab = 0);
              break;
            case 1: // Open the dedicated Промоции tab and load its promo list.
              if (_tab != 1) setState(() => _tab = 1);
              _loadPromoTab();
              break;
            case 2:
              _openSettings();
              break;
          }
        },
        backgroundColor: isDark ? Theme.of(context).colorScheme.surface : Colors.white,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}

/// Location filter bottom sheet.
class _LocationFilterSheet extends StatefulWidget {
  final double lat;
  final double lng;
  final double radiusKm;
  final String locationLabel;
  final int storesCount;
  final ValueChanged<double> onRadiusChanged;
  final Function(String label, double lat, double lng) onLocationChanged;

  const _LocationFilterSheet({
    required this.lat,
    required this.lng,
    required this.radiusKm,
    required this.locationLabel,
    required this.storesCount,
    required this.onRadiusChanged,
    required this.onLocationChanged,
  });

  @override
  State<_LocationFilterSheet> createState() => _LocationFilterSheetState();
}

class _LocationFilterSheetState extends State<_LocationFilterSheet> {
  final ApiService _api = ApiService();
  final LocationService _location = LocationService();
  final TextEditingController _locController = TextEditingController();
  late double _radiusKm;
  List<Store> _stores = [];
  bool _loadingStores = false;

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.radiusKm;
    _loadStores();
  }

  @override
  void dispose() {
    _locController.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _loadStores() async {
    setState(() => _loadingStores = true);
    try {
      final stores = await _api.getNearbyStores(widget.lat, widget.lng, radiusKm: _radiusKm);
      setState(() => _stores = stores);
    } catch (_) {}
    setState(() => _loadingStores = false);
  }

  Future<void> _useMyLocation() async {
    try {
      final pos = await _location.getCurrentPosition();
      widget.onLocationChanged('Моето местоположение', pos.latitude, pos.longitude);
      widget.onRadiusChanged(_radiusKm);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Грешка при определяне на местоположението: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.place, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Локация и филтри',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Затвори'),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Location search
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Локация', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _locController,
                          decoration: InputDecoration(
                            hintText: 'Град или адрес…',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => _searchLocation(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _useMyLocation,
                        icon: const Icon(Icons.my_location, size: 16),
                        label: const Text('Моето местоположение'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Radius slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Радиус на търсене', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  RadiusSegment(
                    selectedKm: _radiusKm,
                    onChanged: (km) {
                      setState(() => _radiusKm = km);
                      widget.onRadiusChanged(km);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),

            // Nearby stores list
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    'Магазини наблизо (${_stores.length})',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MapScreen(
                            lat: widget.lat,
                            lng: widget.lng,
                            radiusKm: _radiusKm,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Карта'),
                  ),
                  if (_loadingStores)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),

            Flexible(
              child: _stores.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Няма магазини в тази зона', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _stores.length,
                      itemBuilder: (ctx, i) {
                        final store = _stores[i];
                        return ListTile(
                          dense: true,
                          leading: Text(store.chainSlug[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                          title: Text(store.chainName, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${store.address} · ${store.distanceText ?? ''}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchLocation() async {
    final query = _locController.text.trim();
    if (query.isEmpty) return;
    try {
      final results = await _api.geocode(query);
      if (results.isNotEmpty && mounted) {
        final r = results.first;
        widget.onLocationChanged(r.display, r.lat, r.lng);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не намерен адрес: $e')),
        );
      }
    }
  }
}

/// Loose match card — approximate product matches.
class _LooseCard extends StatelessWidget {
 final LooseResult loose;
 final VoidCallback? onOpenMap;

 const _LooseCard({required this.loose, this.onOpenMap});

 @override
 Widget build(BuildContext context) {
   final isDark = Theme.of(context).brightness == Brightness.dark;
   final isPromo = loose.priceRetail != null && loose.price < loose.priceRetail!;

   return Material(color: Colors.transparent, child: InkWell(
     onTap: onOpenMap ?? () {},
     borderRadius: BorderRadius.circular(10),
     child: Container(
     margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
     decoration: BoxDecoration(
       color: isDark ? Theme.of(context).colorScheme.surface : Colors.white,
       borderRadius: BorderRadius.circular(10),
       border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
     ),
     child: Padding(
       padding: const EdgeInsets.all(12),
       child: Row(
         children: [
           Expanded(
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   loose.rawName,
                   style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87),
                 ),
                 const SizedBox(height: 2),
                 Text(
                   '${loose.chainName}${loose.address != null ? ' · ${loose.address}' : ''}',
                   style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                 ),
               ],
             ),
           ),
           Column(
             crossAxisAlignment: CrossAxisAlignment.end,
             children: [
               Text(
                 '${loose.price.toStringAsFixed(2)} €',
                 style: TextStyle(
                   fontSize: 16,
                   fontWeight: FontWeight.bold,
                   color: isPromo ? Colors.redAccent : (isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87),
                 ),
               ),
               if (isPromo && loose.priceRetail != null) ...[
                 Text(
                   '${loose.priceRetail!.toStringAsFixed(2)} €',
                   style: TextStyle(fontSize: 10, decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant),
                 ),
               ],
             ],
           ),
         ],
       ),
     ),
    ), // end Container
  ), // end InkWell
); // end Material
 }
}

/// Product comparison card — matches web v2 design.
class _ProductCard extends StatefulWidget {
  final MatchResult match;
  final bool isFav;
  final VoidCallback onAddToBasket;
  final VoidCallback onToggleFav;
  final VoidCallback onOpenMap;

  const _ProductCard({
    required this.match,
    required this.isFav,
    required this.onAddToBasket,
    required this.onToggleFav,
    required this.onOpenMap,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _expanded = false;

  Widget _promoBadge(int pct, Color promo) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: promo, borderRadius: BorderRadius.circular(4)),
        child: Text('\u2212$pct%',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap, String tip) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: color),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final m = widget.match;
    final c0 = m.cheapest;
    final promo = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFD23B3B);
    final more = m.chains.length - 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 6, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(itemEmoji(m.display), style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(m.display,
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25, color: cs.onSurface)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('\u043e\u0442 ', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                          Text('${c0.minPrice.toStringAsFixed(2)} \u20ac',
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: cs.onSurface)),
                          if (c0.isPromo)
                            Padding(padding: const EdgeInsets.only(left: 6), child: _promoBadge(c0.pctOff ?? 0, promo)),
                          Text('  \u00b7  ${c0.chainName}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                          if (more > 0)
                            Text('  \u00b7  +$more \u043e\u0449\u0435', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                _iconBtn(widget.isFav ? Icons.favorite : Icons.favorite_border,
                    widget.isFav ? Colors.redAccent : cs.onSurfaceVariant, widget.onToggleFav, '\u041b\u044e\u0431\u0438\u043c\u0438'),
                _iconBtn(Icons.add_shopping_cart, cs.primary, widget.onAddToBasket, '\u0414\u043e\u0431\u0430\u0432\u0438 \u0432 \u043a\u043e\u0448\u043d\u0438\u0446\u0430\u0442\u0430'),
              ],
            ),
            if (m.chains.length > 1) ...[
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${m.chains.length} \u0432\u0435\u0440\u0438\u0433\u0438 \u2014 \u0432\u0438\u0436 \u0432\u0441\u0438\u0447\u043a\u0438 \u0446\u0435\u043d\u0438',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: cs.primary),
                  ]),
                ),
              ),
              if (_expanded)
                ...m.chains.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: chainColor(c.chainSlug), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c.chainName, style: TextStyle(fontSize: 12.5, color: cs.onSurface))),
                        if (c.isPromo)
                          Padding(padding: const EdgeInsets.only(right: 6), child: _promoBadge(c.pctOff ?? 0, promo)),
                        Text('${c.minPrice.toStringAsFixed(2)} \u20ac',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
                      ]),
                    )),
            ],
            InkWell(
              onTap: widget.onOpenMap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.map_outlined, size: 15, color: cs.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text('\u0412\u0438\u0436 \u043c\u0430\u0433\u0430\u0437\u0438\u043d\u0438\u0442\u0435 \u043d\u0430 \u043a\u0430\u0440\u0442\u0430\u0442\u0430',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing saved favorites. Tap to search, ✕ to remove.
class _FavoritesSheet extends StatefulWidget {
  final void Function(String query) onSearch;
  final Future<void> Function() onChanged;

  const _FavoritesSheet({required this.onSearch, required this.onChanged});

  @override
  State<_FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<_FavoritesSheet> {
  List<String> _favs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await LocalStore.favorites();
    if (!mounted) return;
    setState(() {
      _favs = f;
      _loading = false;
    });
  }

  Future<void> _remove(String item) async {
    await LocalStore.removeFavorite(item);
    await widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.favorite, size: 18, color: Colors.redAccent),
                const SizedBox(width: 6),
                Text('Любими',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Затвори')),
              ],
            ),
          ),
          const Divider(height: 1),
          // Push CTA — daily morning/evening reminders to check favourite promos.
          InkWell(
            onTap: () async {
              final ok = await NotifyService.enableDailyReminders();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Готово! Ще ти напомняме сутрин и вечер за намаления на любимите.'
                    : 'Разреши известия от настройките, за да получаваш напомняния.'),
                duration: const Duration(seconds: 3),
              ));
              Navigator.pop(context);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Известия сутрин и вечер за намаления на любимите',
                        style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface)),
                  ),
                  Text('Включи',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
          else if (_favs.isEmpty)
            Padding(
              padding: EdgeInsets.all(24),
              child: Text('Нямаш любими още. Натисни ♥ върху продукт, за да го запазиш.',
                  textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _favs.length,
                itemBuilder: (ctx, i) {
                  final f = _favs[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.favorite, size: 16, color: Colors.redAccent),
                    title: Text(f, style: const TextStyle(fontSize: 14)),
                    onTap: () => widget.onSearch(f),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _remove(f),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
