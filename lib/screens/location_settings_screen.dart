/// Location settings screen — city search, radius, chain multi-select.
///
/// Modern Material 3 design with color-coded chain cards. Tapping a card
/// toggles the chain selection with a subtle background tint and checkmark
/// badge rather than old-school checkboxes.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../models/store.dart';
import '../models/geocode_result.dart';
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
  // The coordinates the user has chosen on this screen (city search / GPS).
  // Returned to HomeScreen so a picked location actually takes effect.
  late double _chosenLat;
  late double _chosenLng;

  // Address autocomplete: debounced as-you-type suggestions from /api/geocode.
  Timer? _debounce;
  List<GeocodeResult> _suggestions = [];
  bool _suggestLoading = false;

  @override
  void initState() {
    super.initState();
    _radius = widget.radiusKm;
    _chosenLat = widget.lat;
    _chosenLng = widget.lng;
    _cityController.text = widget.locationLabel ?? '';
    _selectedChains = Set.from(widget.selectedChains);
    _loadStores();
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  // As-you-type: debounce 350ms, then fetch address suggestions. Keeps the
  // Nominatim call rate low (server also caches + rate-limits /api/geocode).
  void _onCityChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _suggestLoading = true);
      try {
        final results = await _api.geocode(q);
        if (!mounted) return;
        setState(() { _suggestions = results.take(6).toList(); _suggestLoading = false; });
      } catch (_) {
        if (mounted) setState(() { _suggestions = []; _suggestLoading = false; });
      }
    });
  }

  // Apply a chosen geocode result (from a tapped suggestion or a submit).
  Future<void> _applyResult(GeocodeResult r) async {
    _debounce?.cancel();
    setState(() {
      _cityController.text = r.display;
      _chosenLat = r.lat;
      _chosenLng = r.lng;
      _suggestions = [];
      _isLoading = true;
    });
    FocusScope.of(context).unfocus();
    try {
      await _loadStores(lat: r.lat, lng: r.lng);
      await _location.savePosition(
        Position(latitude: r.lat, longitude: r.lng, timestamp: DateTime.now(),
          accuracy: 0, altitude: 0, heading: 0, speed: 0,
          speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0),
        address: r.display,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Submit (keyboard "search"): if suggestions are showing, take the first;
  // otherwise geocode the raw text and apply the first hit.
  Future<void> _searchCity() async {
    _debounce?.cancel();
    if (_suggestions.isNotEmpty) { await _applyResult(_suggestions.first); return; }
    final query = _cityController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final results = await _api.geocode(query);
      if (results.isNotEmpty && mounted) {
        await _applyResult(results.first);
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
      setState(() {
        _chosenLat = pos.latitude;
        _chosenLng = pos.longitude;
        _cityController.text = 'Моето местоположение';
      });
      await _loadStores(lat: pos.latitude, lng: pos.longitude);
      // Reverse-geocode to a human area name (mirrors web v2).
      final area = await _api.reverseArea(pos.latitude, pos.longitude);
      if (area != null && area.isNotEmpty && mounted) {
        setState(() => _cityController.text = area);
      }
      await _location.savePosition(pos, address: _cityController.text);
    } catch (_) {
      // Device GPS off/denied → fall back to approximate location from the
      // client IP (server GeoIP / MaxMind) so the feature still works.
      final ip = await _api.iploc();
      if (ip != null && mounted) {
        setState(() {
          _chosenLat = ip.lat;
          _chosenLng = ip.lng;
          _cityController.text = ip.display;
        });
        await _loadStores(lat: ip.lat, lng: ip.lng);
        await _location.savePosition(
          Position(latitude: ip.lat, longitude: ip.lng, timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, heading: 0, speed: 0,
            speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0),
          address: ip.display,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Приблизително местоположение (включи GPS за по-точно)')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не успяхме да определим местоположение. Избери град ръчно.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, res) {
        if (didPop) return;
        _location.saveRadius(_radius);
        Navigator.of(context).pop({
          'radiusKm': _radius,
          'label': _cityController.text.trim(),
          'selectedChains': _selectedChains,
          'lat': _chosenLat,
          'lng': _chosenLng,
        });
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Местоположение и магазини'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(top: false, child: _isLoading && _nearbyStores.isEmpty
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
                        height: 52,
                        padding: const EdgeInsets.only(left: 14, right: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : const Color(0xFFEEF1F5),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Row(children: [
                          Icon(Icons.search, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _cityController,
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Напр. София, Пловдив...',
                                hintStyle: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                isCollapsed: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onChanged: _onCityChanged,
                              onSubmitted: (_) => _searchCity(),
                            ),
                          ),
                          // "Use my location" — circular accent button (clear affordance).
                          Padding(
                            padding: const EdgeInsets.all(5),
                            child: Material(
                              color: Theme.of(context).colorScheme.primary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _useMyLocation,
                                child: SizedBox(
                                  width: 42, height: 42,
                                  child: Icon(Icons.my_location, size: 20, color: Theme.of(context).colorScheme.onPrimary),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),

                      // ---- ADDRESS SUGGESTIONS (autocomplete) ----
                      if (_suggestLoading || _suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: _suggestLoading && _suggestions.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (int i = 0; i < _suggestions.length; i++) ...[
                                      if (i > 0) const Divider(height: 1),
                                      ListTile(
                                        dense: true,
                                        leading: Icon(Icons.place_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                                        title: Text(_suggestions[i].display,
                                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                                        onTap: () => _applyResult(_suggestions[i]),
                                      ),
                                    ],
                                  ],
                                ),
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
            )),
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
    // Display the human chain NAME (e.g. "Билла"), not the slug ("billa_…").
    String nameFor(MapEntry<String, List<Store>> e) =>
        prettyChainName(e.value.isNotEmpty ? e.value.first.chainName : e.key);
    final sorted = grouped.entries.toList()
      ..sort((a, b) => nameFor(a).toLowerCase().compareTo(nameFor(b).toLowerCase()));

    return sorted.expand((entry) {
      final slug = entry.key;
      final stores = entry.value;
      final chainName = nameFor(entry);
      final isChecked = _selectedChains.contains(slug);
      final cColor = chainColor(slug);
      final isDark = Theme.of(context).brightness == Brightness.dark;

      return [
        AnimatedOpacity(
          opacity: isChecked ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isChecked) {
                    _selectedChains.remove(slug);
                  } else {
                    _selectedChains.add(slug);
                  }
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: isChecked
                      ? cColor.withOpacity(isDark ? 0.16 : 0.10)
                      : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isChecked ? cColor : (isDark ? Colors.white12 : Colors.grey.shade300),
                    width: isChecked ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 13, height: 13,
                    decoration: BoxDecoration(color: cColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      chainName,
                      style: TextStyle(
                        fontWeight: isChecked ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                        color: isChecked ? cColor : null,
                      ),
                    ),
                  ),
                  Text('${stores.length} обекта',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
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
