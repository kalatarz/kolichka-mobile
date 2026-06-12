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
import '../widgets/app_theme.dart';
import '../widgets/brand_header.dart';
import '../widgets/location_chip.dart';
import '../widgets/search_bar.dart';
import '../widgets/radius_segment.dart';
import '../data/cat_groups.dart';
import 'basket_screen.dart';
import 'map_screen.dart';
import 'promotions_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ApiService _api = ApiService();
  final LocationService _location = LocationService();
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
      // Try GPS first, fall back to saved position
      Position? pos;
      String? address;
      try {
        pos = await _location.getCurrentPosition();
        Analytics.instance.track('location_ok');
      } on Exception catch (_) {
        Analytics.instance.track('location_fail');
        pos = await _location.getLastPosition();
        address = await _location.getLastAddress();
      }

      if (pos != null) {
        final currentPos = pos;
        setState(() {
          _lat = currentPos.latitude;
          _lng = currentPos.longitude;
        });
        address ??= 'Моето местоположение';
        await _location.savePosition(pos, address: address);
      }

      // Load categories and stores in parallel
      final results = await Future.wait([
        _api.getCategories(),
        _api.getNearbyStores(_lat, _lng, radiusKm: _radiusKm),
      ]);

      setState(() {
        _categories = results[0] as List<Category>;
        final stores = results[1] as List<Store>;
        _storesCount = stores.length;
        _locationLabel = address ?? 'Моето местоположение';
        _isLoading = false;
        _locationError = false;
      });
      await _refreshLocalState();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _locationError = true;
      });
    }
  }

  /// Handle search — either direct product query or category selection.
  Future<void> _performSearch(String query, {String? displayQuery}) async {
    if (_lat == 0 && _lng == 0) return;

    setState(() {
      _searching = true;
      _searchError = null;
      _lastQuery = displayQuery ?? query;
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

      // Scroll to results
      _scrollController.animateTo(
        300, // scroll past categories to results area
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      setState(() {
        _searchError = e.toString();
        _searching = false;
      });
    }
  }

  /// Handle category tap — drill down or search.
  void _handleCategoryTap(String slug, String label) {
    setState(() {
      if (_selectedCategory == slug) {
        // Deselect
        _selectedCategory = null;
      } else {
        _selectedCategory = slug;
      }
    });

    // Perform search for this category
    _performSearch('cat:$slug', displayQuery: label);
  }

  /// Handle group expansion toggle.
  void _toggleGroup(int index) {
    setState(() {
      _openGroupIndex = _openGroupIndex == index ? null : index;
    });
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
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.primaryGreen),
                SizedBox(height: 16),
                Text('Зареждане...', style: TextStyle(color: AppTheme.mutedText)),
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
                const Icon(Icons.location_off, size: 64, color: AppTheme.warnAmber),
                const SizedBox(height: 16),
                const Text(
                  'Не мога да определя местоположението',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Моля проверете GPS настройките и опитайте отново.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _init,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Опитай отново'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
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
              onThemeToggle: () {}, // handled globally
              onFavorites: _openFavorites,
              onSettings: _openSettings,
            ),

            // 2. Location chip
            LocationChip(
              locationText: _locationLabel != null
                  ? '${_locationLabel!} · $_storesCount магазина'
                  : 'Намери магазини…',
              onTap: _openLocationPanel,
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
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(color: AppTheme.primaryGreen),
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
        backgroundColor: AppTheme.primaryGreen,
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
  Widget _buildCategoryGroups() {
    final groups = <MapEntry<int, CatGroup>>[];
    for (var i = 0; i < kCatGroups.length; i++) {
      final g = kCatGroups[i];
      final hasActive = g.slugs.any((s) => _categories.any((c) => c.slug == s));
      if (hasActive) groups.add(MapEntry(i, g));
    }
    if (groups.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: groups.map((e) {
              final idx = e.key;
              final group = e.value;
              final isExpanded = _openGroupIndex == idx;
              return InkWell(
                onTap: () => _toggleGroup(idx),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isExpanded
                        ? AppTheme.primaryGreen.withOpacity(0.15)
                        : (isDark ? AppTheme.darkCard : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isExpanded
                          ? AppTheme.primaryGreen
                          : (isDark ? AppTheme.darkLine : AppTheme.lightLine),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_groupIcon(group.label),
                          size: 16,
                          color: isExpanded ? AppTheme.primaryGreen : AppTheme.mutedText),
                      const SizedBox(width: 6),
                      Text(
                        group.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isExpanded ? FontWeight.w700 : FontWeight.w500,
                          color: isExpanded
                              ? AppTheme.primaryGreen
                              : (isDark ? AppTheme.primaryTextDark : Colors.black87),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16,
                        color: isExpanded ? AppTheme.primaryGreen : AppTheme.mutedText,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_openGroupIndex != null) _buildSubcategories(_openGroupIndex!),
        ],
      ),
    );
  }

  /// Subcategory chips for the expanded group (full width, below the chips row).
  Widget _buildSubcategories(int groupIdx) {
    if (groupIdx < 0 || groupIdx >= kCatGroups.length) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeSlugs = kCatGroups[groupIdx].slugs
        .where((s) => _categories.any((c) => c.slug == s))
        .toList();
    if (activeSlugs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: activeSlugs.map((slug) {
          final cat = _categories.firstWhere((c) => c.slug == slug);
          final isSelected = _selectedCategory == slug;
          return InkWell(
            onTap: () => _handleCategoryTap(slug, cat.label),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryGreen
                    : (isDark ? AppTheme.darkLine : Colors.grey.shade200),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                cat.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? AppTheme.primaryTextDark : Colors.black87),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Material icon for a category group (emoji do not render on old Android).
  IconData _groupIcon(String label) {
    switch (label) {
      case 'Основни и варива':
        return Icons.bakery_dining;
      case 'Мляко и яйца':
        return Icons.egg_alt;
      case 'Месо и риба':
        return Icons.set_meal;
      case 'Зеленчуци':
        return Icons.eco;
      case 'Плодове':
        return Icons.apple;
      case 'Сладко':
        return Icons.cake;
      case 'Олио и мазнини':
        return Icons.water_drop;
      case 'Напитки':
        return Icons.local_cafe;
      case 'Алкохол':
        return Icons.wine_bar;
      case 'Дом и хигиена':
        return Icons.cleaning_services;
      default:
        return Icons.category;
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
            const Icon(Icons.error_outline, size: 48, color: AppTheme.pink),
            const SizedBox(height: 12),
            Text(
              _searchError ?? 'Грешка при търсенето',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.mutedText),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                if (_lastQuery != null) _performSearch(_lastQuery!);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Опитай отново'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Results section — mirrors web v2 results layout.
  Widget _buildResults() {
    final result = _currentResult!;
    final matches = result.matches;
    final loose = result.loose;

    if (matches.isEmpty && loose.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 64, color: AppTheme.mutedText),
              const SizedBox(height: 12),
              Text(
                'Няма намерени резултати за "${_lastQuery}"',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                'Опитайте с по-голям радиус или друг продукт.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedText),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
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

        // Exact match product cards
        ...matches.map((match) => _ProductCard(
              match: match,
              isFav: _favorites.contains(match.display.trim().toLowerCase()),
              onAddToBasket: () => _addToBasket(match.display),
              onToggleFav: () => _toggleFav(match.display),
            )),

        // Loose matches section
        if (loose.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Приблизителни съвпадения (${loose.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mutedText),
            ),
          ),
          ...loose.map((looseMatch) => _LooseCard(loose: looseMatch)),
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
        color: isDark ? AppTheme.darkCard : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppTheme.darkLine : AppTheme.lightLine),
        ),
      ),
      child: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Начало'),
          BottomNavigationBarItem(icon: Icon(Icons.local_offer_outlined), label: 'Промоции'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Настройки'),
        ],
        onTap: (idx) {
          switch (idx) {
            case 0: // Already on home
              break;
            case 1:
              _openPromotions();
              break;
            case 2:
              _openSettings();
              break;
          }
        },
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        selectedItemColor: AppTheme.primaryGreen,
        unselectedItemColor: AppTheme.mutedText,
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
                  const Icon(Icons.place, size: 18, color: AppTheme.primaryGreen),
                  const SizedBox(width: 6),
                  Text(
                    'Локация и филтри',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? AppTheme.primaryTextDark : Colors.black87),
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
                  Text('Локация', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.mutedText : AppTheme.mutedText)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _locController,
                          decoration: InputDecoration(
                            hintText: 'град или адрес…',
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
                        label: const Text('моята'),
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
                  Text('Радиус на търсене', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.mutedText : AppTheme.mutedText)),
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.mutedText : AppTheme.mutedText),
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
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Няма магазини в тази зона', style: TextStyle(color: AppTheme.mutedText)),
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
                          subtitle: Text('${store.address} · ${store.distanceText ?? ''}', style: const TextStyle(fontSize: 11, color: AppTheme.mutedText)),
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

 const _LooseCard({required this.loose});

 @override
 Widget build(BuildContext context) {
   final isDark = Theme.of(context).brightness == Brightness.dark;
   final isPromo = loose.priceRetail != null && loose.price < loose.priceRetail!;

   return Container(
     margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
     decoration: BoxDecoration(
       color: isDark ? AppTheme.darkCard : Colors.white,
       borderRadius: BorderRadius.circular(10),
       border: Border.all(color: isDark ? AppTheme.darkLine : AppTheme.lightLine),
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
                   style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? AppTheme.primaryTextDark : Colors.black87),
                 ),
                 const SizedBox(height: 2),
                 Text(
                   '${loose.chainName}${loose.address != null ? ' · ${loose.address}' : ''}',
                   style: TextStyle(fontSize: 11, color: AppTheme.mutedText),
                 ),
               ],
             ),
           ),
           Column(
             crossAxisAlignment: CrossAxisAlignment.end,
             children: [
               Text(
                 '${loose.price.toStringAsFixed(2)} лв',
                 style: TextStyle(
                   fontSize: 16,
                   fontWeight: FontWeight.bold,
                   color: isPromo ? Colors.redAccent : (isDark ? AppTheme.primaryTextDark : Colors.black87),
                 ),
               ),
               if (isPromo && loose.priceRetail != null) ...[
                 Text(
                   '${loose.priceRetail!.toStringAsFixed(2)} лв',
                   style: TextStyle(fontSize: 10, decoration: TextDecoration.lineThrough, color: AppTheme.mutedText),
                 ),
               ],
             ],
           ),
         ],
       ),
     ),
   );
 }
}

/// Product comparison card — matches web v2 design.
class _ProductCard extends StatelessWidget {
  final MatchResult match;
  final bool isFav;
  final VoidCallback onAddToBasket;
  final VoidCallback onToggleFav;

  const _ProductCard({
    required this.match,
    required this.isFav,
    required this.onAddToBasket,
    required this.onToggleFav,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.darkLine : AppTheme.lightLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name + qty
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.display,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppTheme.primaryTextDark : Colors.black87),
                  ),
                ),
                if (match.qty != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkLine : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      match.qty.toString(),
                      style: TextStyle(fontSize: 11, color: isDark ? AppTheme.mutedText : AppTheme.mutedText),
                    ),
                  ),
                IconButton(
                  onPressed: onToggleFav,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.only(left: 6),
                  constraints: const BoxConstraints(),
                  tooltip: 'Любими',
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: isFav ? Colors.redAccent : AppTheme.mutedText,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Cheapest chain highlight
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match.cheapest.chainName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentGreen),
                        ),
                        if (match.cheapest.isPromo)
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  '-${match.cheapest.pctOff}%',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                ),
                              ),
                              if (match.cheapest.priceRetail != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${match.cheapest.priceRetail?.toStringAsFixed(2) ?? ''} лв',
                                  style: TextStyle(
                                    fontSize: 10,
                                    decoration: TextDecoration.lineThrough,
                                    color: AppTheme.mutedText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${match.cheapest.minPrice.toStringAsFixed(2)} лв',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentGreen),
                      ),
                      if (match.cheapest.nStores != null && match.cheapest.nStores! > 1)
                        Text(
                          '${match.cheapest.nStores!} магазина',
                          style: TextStyle(fontSize: 10, color: AppTheme.mutedText),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Other chains
            ...match.chains.skip(1).map((chain) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chain.chainName,
                      style: TextStyle(fontSize: 12, color: isDark ? AppTheme.primaryTextDark : Colors.black87),
                    ),
                  ),
                  if (chain.isPromo) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '-${chain.pctOff}%',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '${chain.minPrice.toStringAsFixed(2)} лв',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.primaryTextDark : Colors.black87,
                    ),
                  ),
                ],
              ),
            )),

            // Spread info
            if (match.spread != null && match.spread!.pct > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 12, color: AppTheme.mutedText),
                    const SizedBox(width: 4),
                    Text(
                      'Разлика ${match.spread!.pct}% (${match.spread!.min.toStringAsFixed(2)} — ${match.spread!.max.toStringAsFixed(2)} лв)',
                      style: TextStyle(fontSize: 10, color: AppTheme.mutedText),
                    ),
                  ],
                ),
              ),

            // Add to basket button
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAddToBasket,
                      icon: const Icon(Icons.shopping_basket_outlined, size: 16),
                      label: const Text('Добави в кошницата', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? AppTheme.primaryTextDark : Colors.black87)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Затвори')),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
          else if (_favs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Нямаш любими още. Натисни ♥ върху продукт, за да го запазиш.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppTheme.mutedText)),
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
