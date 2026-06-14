/// Location settings screen — city search, radius, chain multi-select.
///
/// Modern Material 3 design with color-coded chain cards. Tapping a card
/// toggles the chain selection with a subtle background tint and checkmark
/// badge rather than old-school checkboxes.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../models/store.dart';
import '../widgets/chain_colors.dart';
import '../widgets/radius_segment.dart';

class LocationSettingsScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final double radiusKm;
  final String? locationLabel;
  /// Currently selected chain slugs (from HomeScreen _chainFilter).
  final Set<String> selectedChains;

  const LocationSettingsScreen({
    super.key,
    this.lat = 42.7,
    this.lng = 23.3,
    this.radiusKm = 5.0,
    this.locationLabel,
    this.selectedChains = const {},
  });

  @override
  State<LocationSettingsScreen> createState() => _LocationSettingsScreenState();
}

class _LocationSettingsScreenState extends State<LocationSettingsScreen> {
  final _api = ApiService();
  final _location = LocationService();
  final _cityController = TextEditingController();

  double _radius = 5.0;
  bool _isLoading = false;
  List<Store> _nearbyStores = [];
  Set<String> _selectedChains = {}; // chain slugs the user checked

  @override
  void initState() {
    super.initState();
    _radius = widget.radiusKm;
    _cityController.text = widget.locationLabel ?? '';
    _selectedChains = Set.from(widget.selectedChains);
    _loadStores();
  }

  @override
  void dispose() {
    _cityController.dispose();
    _api.close();
    super.dispose();
  }

  // ------------------------------------------------------------------ helpers
  Future<void> _loadStores({double? lat, double? lng}) async {
    final l = lat ?? widget.lat;
    final n = lng ?? widget.lng;
    setState(() => _isLoading = true);
    try {
      _nearbyStores = await _api.getNearbyStores(l, n, radiusKm: _radius);
      // Auto-select all chains on first load if nothing selected yet
      if (_selectedChains.isEmpty) {
        final allSlugs = _nearbyStores.map((s) => s.chainSlug).toSet();
        setState(() => _selectedChains = allSlugs);
      }
    } catch (_) {
      _nearbyStores = [];
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchCity() async {
    final query = _cityController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final results = await _api.geocode(query);
      if (results.isNotEmpty && mounted) {
        final r = results.first;
        setState(() {
          _cityController.text = r.display;
        });
        await _loadStores(lat: r.lat, lng: r.lng);
        await _location.savePosition(
          Position(latitude: r.lat, longitude: r.lng, timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, heading: 0, speed: 0,
            speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0),
          address: r.display,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не намерен адрес за "$query"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Грешка при търсенето: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _isLoading = true);
    try {
      final pos = await _location.getCurrentPosition();
      setState(() => _cityController.text = 'Моето местоположение');
      await _loadStores(lat: pos.latitude, lng: pos.longitude);
      await _location.savePosition(pos, address: 'Моето местоположение');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Грешка при местоположението: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _saveAndReturn() {
    _location.saveRadius(_radius);
    Navigator.of(context).pop({
      'radiusKm': _radius,
      'label': _cityController.text.trim(),
      'selectedChains': _selectedChains,
    });
  }

  // ------------------------------------------------------------------ groups
  /// Group stores by chain slug.
  Map<String, List<Store>> _groupedStores() {
    final map = <String, List<Store>>{};
    for (final s in _nearbyStores) {
      map.putIfAbsent(s.chainSlug, () => []).add(s);
    }
    return map;
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final cardBg = isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Местоположение и магазини'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          TextButton(
            onPressed: _saveAndReturn,
            child: const Text('Запази', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isLoading && _nearbyStores.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      // ---- CITY / ADDRESS SEARCH ----
                      _sectionTitle('Град или адрес'),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                        ),
                        child: Row(children: [
                          const Icon(Icons.search, size: 20, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _cityController,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Напр. София, Пловдив...',
                                hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                              onSubmitted: (_) => _searchCity(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.my_location, size: 20, color: Colors.grey),
                            onPressed: _useMyLocation,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ]),
                      ),

                      const SizedBox(height: 16),

                      // ---- RADIUS ----
                      _sectionTitle('Радиус на търсене'),
                      RadiusSegment(
                        selectedKm: _radius,
                        onChanged: (km) {
                          setState(() => _radius = km);
                          _loadStores();
                        },
                      ),

                      const SizedBox(height: 16),

                      // ---- CHAIN SELECTION ----
                      Row(children: [
                        _sectionTitle('Магазини'),
                        const Spacer(),
                        Text(
                          '${_selectedChains.length}/${_groupedStores().length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_isLoading)
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ]),

                      // Quick select buttons — modern pill style
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          _pillChip('Всички',
                              _selectedChains.length == _groupedStores().length && _groupedStores().isNotEmpty,
                              () {
                                setState(() => _selectedChains = _groupedStores().keys.toSet());
                              }),
                          const SizedBox(width: 6),
                          _pillChip('Никой', _selectedChains.isEmpty,
                              () => setState(() => _selectedChains.clear())),
                        ]),
                      ),

                      // Chain cards — modern Material 3 style
                      ..._buildChainCards(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Modern pill-shaped quick-select chip.
  Widget _pillChip(String label, bool isActive, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
              : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: isActive ? 1.2 : 0.8,
          ),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          color: isActive ? Theme.of(context).colorScheme.primary : null,
        )),
      ),
    );
  }

  List<Widget> _buildChainCards() {
    final grouped = _groupedStores();
    final sorted = grouped.entries.toList()
      ..sort((a, b) => prettyChainName(a.key).compareTo(prettyChainName(b.key)));

    return sorted.expand((entry) {
      final slug = entry.key;
      final stores = entry.value;
      final isChecked = _selectedChains.contains(slug);
      final cColor = chainColor(slug);
      final isDark = Theme.of(context).brightness == Brightness.dark;

      return [
        // Chain card — tap to toggle
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                if (isChecked) _selectedChains.remove(slug);
                else _selectedChains.add(slug);
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                // Selected: chain color tint. Unselected: subtle grey tint.
                color: isChecked
                    ? cColor.withOpacity(isDark ? 0.12 : 0.08)
                    : (isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isChecked
                      ? cColor.withOpacity(0.5)
                      : (isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200),
                  width: isChecked ? 1.5 : 1,
                ),
              ),
              child: Row(children: [
                // Colored indicator circle with checkmark
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: isChecked ? cColor : cColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isChecked ? Icons.check_rounded : null,
                    size: 18,
                    color: isChecked ? Colors.white : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prettyChainName(slug),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isChecked ? cColor : null,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${stores.length} магазин${stores.length > 1 ? 'а' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Subtle chevron indicator
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isChecked ? cColor : (isDark ? Colors.white24 : Colors.grey.shade400),
                ),
              ]),
            ),
          ),
        ),
      ];
    }).toList();
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
    );
  }
}
