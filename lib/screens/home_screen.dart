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

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../models/category.dart';
import '../models/store.dart';
import '../models/compare_result.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/local_store.dart';
import '../services/analytics.dart';
import '../main.dart';
import '../widgets/brand_header.dart';
import '../widgets/location_chip.dart';
import '../widgets/search_bar.dart';
import '../widgets/radius_segment.dart';
import '../data/cat_groups.dart';
import '../widgets/chain_colors.dart';
import 'basket_screen.dart';
import 'map_screen.dart';
import 'promotions_screen.dart';
import 'settings_screen.dart';
import 'location_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
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
  final Set<String> _chainFilter = <String>{}; // selected chain slugs in results

  // Stores count for display
  int _storesCount = 0;

  // Basket FAB badge
  int _basketCount = 0;

  // Favorites (lowercased names) for quick lookup while rendering cards
  Set<String> _favorites = <String>{};

  @override
  void initState() {
    super.initState();
    _init();
    _refreshLocalState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    try {
      // 1) Instant: render with the last saved location (no GPS wait, so the
      //    initial open never times out). Falls back to the Sofia default.
      final saved = await _location.getLastPosition();
      final savedAddress = await _location.getLastAddress();
      if (saved != null) {
        _lat = saved.latitude;
        _lng = saved.longitude;
      }

      final results = await Future.wait([
        _api.getCategories(),
        _api.getNearbyStores(_lat, _lng, radiusKm: _radiusKm),
      ]);

      setState(() {
        _categories = results[0] as List<Category>;
        final stores = results[1] as List<Store>;
        _storesCount = stores.length;
        _locationLabel = savedAddress ?? 'Моята локация';
        _isLoading = false;
        _locationError = false;
      });
      await _refreshLocalState();
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
    try {
      final pos = await _location.getCurrentPosition();
      if (!mounted) return;
      Analytics.instance.track('location_ok');
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locationLabel = 'Моята локация';
      });
      await _location.savePosition(pos, address: 'Моето местоположение');
      try {
        final stores = await _api.getNearbyStores(_lat, _lng, radiusKm: _radiusKm);
        if (mounted) setState(() => _storesCount = stores.length);
      } catch (_) {}
    } catch (_) {
      Analytics.instance.track('location_fail');
    }
  }

  /// Handle search — either direct product query or category selection.
  Future<void> _performSearch(String query, {String? displayQuery}) async {
    if (_lat == 0 && _lng == 0) return;

    setState(() {
      _searching = true;
      _searchError = null;
      _lastQuery = displayQuery ?? query;
      _chainFilter.clear();
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
      Analytics.instance.track('saw_prices', {
        'results': result.matches.length + result.loose.length,
        'matches': result.matches.length,
      });

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
      setState(() {
        if (result['radiusKm'] != null) {
          _radiusKm = result['radiusKm'];
        }
        if (result['label'] != null) {
          _locationLabel = result['label'];
        }
        if (result['selectedChains'] != null) {
          _chainFilter.clear();
          _chainFilter.addAll(result['selectedChains'] as Set<String>);
        }
      });
      // Re-search with updated chain filter
      if (_lastQuery != null) {
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

  /// Navigate to promotions screen.
  void _openPromotions() {
    Analytics.instance.track('open_promotions');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => PromotionsScreen(
          lat: _lat,
          lng: _lng,
          radiusKm: _radiusKm,
        ),
      ),
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
              onSettings: _openSettings,
            ),

            // 2. Location chip
            LocationChip(
              locationText: _locationLabel != null
                  ? '${_locationLabel!} · $_storesCount магазина'
                  : 'Намери магазини…',
              onTap: _openLocationSettings,
            ),

            // 3. Search bar
            KolichkaSearchBar(
              controller: _searchController,
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
          // GROUP ROW — always visible with all groups + Промоции button
          SizedBox(
            height: 30,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: groups.length + 1, // +1 for Промоции
              itemBuilder: (ctx, i) {
                // First item is Промоции button (Web v2 parity)
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: _openPromotions,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.transparent, width: 1.2),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: const [
                          Text('🏷️', style: TextStyle(fontSize: 13)),
                          SizedBox(width: 3),
                          Text('Промоции', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ]),
                      ),
                    ),
                  );
                }

                // Group chips
                final idx = groups[i - 1].key;
                final group = groups[i - 1].value;
                final isExpanded = _openGroupIndex == idx;
                final (iconData, iconColor) = _groupIconWithColor(group.label);
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
                        Icon(iconData, size: 14, color: iconColor),
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
            const SizedBox(height: 6),
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
            cat.label,
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

  Widget _buildResults() {
    final result = _currentResult!;
    final matches = result.matches;
    final loose = result.loose.where((l) => l.price > 0).toList();
    final chainsPresent = <String, String>{};
    for (final m in matches) {
      for (final c in m.chains) {
        chainsPresent.putIfAbsent(c.chainSlug, () => c.chainName);
      }
    }
    final filtered = _chainFilter.isEmpty
        ? matches
        : matches
            .where((m) => m.chains.any((c) => _chainFilter.contains(c.chainSlug)))
            .toList();

    if (matches.isEmpty && loose.isEmpty) {
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
              Text(
                '${matches.length + loose.length} резултата за "${_lastQuery}"',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () {
                  if (_lastQuery != null) _performSearch(_lastQuery!);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),

        if (chainsPresent.length > 1) _buildChainFilter(chainsPresent),

        if (filtered.isEmpty && _chainFilter.isNotEmpty)
          Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: Text('Няма продукти за избраните вериги.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),

        // Exact match product cards (filtered by chain)
        ...filtered.map((match) => _ProductCard(
              match: match,
              isFav: _favorites.contains(match.display.trim().toLowerCase()),
              onAddToBasket: () => _addToBasket(match.display),
              onToggleFav: () => _toggleFav(match.display),
              onOpenMap: () => _openMap(productQuery: match.display),
            )),

        // Loose matches section
        if (loose.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Приблизителни съвпадения (${loose.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ...loose.map((looseMatch) => _LooseCard(
              loose: looseMatch,
              onOpenMap: () => _openMap(productQuery: looseMatch.rawName),
            )),
        ],

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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Начало'),
          BottomNavigationBarItem(icon: Icon(Icons.local_offer_outlined), label: 'Промоции'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Карта'),
        ],
        onTap: (idx) {
          switch (idx) {
            case 0: // Already on home
              break;
            case 1:
              _openPromotions();
              break;
            case 2:
              _openMap(); // no product — general store map
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
                      Text(m.display,
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25, color: cs.onSurface)),
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
