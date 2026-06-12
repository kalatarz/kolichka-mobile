/// Map of nearby stores (OpenStreetMap via flutter_map). Pins are colored dots
/// per chain (like the web), with a tappable legend that filters by chain.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/store.dart';
import '../services/api_service.dart';
import '../services/analytics.dart';
import '../services/external.dart';
import '../widgets/app_theme.dart';
import '../widgets/chain_colors.dart';

class MapScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final double radiusKm;

  const MapScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final ApiService _api = ApiService();
  List<Store> _stores = [];
  bool _loading = true;
  Store? _selected;
  final Set<String> _hidden = {}; // chain brand names hidden via the legend

  @override
  void initState() {
    super.initState();
    Analytics.instance.track('open_map');
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final stores = await _api.getNearbyStores(widget.lat, widget.lng,
          radiusKm: widget.radiusKm < 5 ? 5 : widget.radiusKm);
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Distinct chains present (brand name → representative slug + count).
  Map<String, _Legend> get _legend {
    final m = <String, _Legend>{};
    for (final s in _stores) {
      final brand = prettyChainName(s.chainName);
      final e = m[brand];
      if (e == null) {
        m[brand] = _Legend(brand, s.chainSlug, 1);
      } else {
        e.count++;
      }
    }
    return m;
  }

  bool _visible(Store s) => !_hidden.contains(prettyChainName(s.chainName));

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.lat, widget.lng);
    final shown = _stores.where(_visible).toList();
    final legend = _legend.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return Scaffold(
      appBar: AppBar(title: Text('Магазини на картата (${shown.length})')),
      body: Column(
        children: [
          if (legend.isNotEmpty) _buildLegend(legend),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(initialCenter: center, initialZoom: 13),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.kolichka.kolichka',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: center,
                          width: 24,
                          height: 24,
                          child: const Icon(Icons.my_location, color: Colors.blue, size: 22),
                        ),
                        ...shown.map((s) {
                          final sel = _selected?.id == s.id;
                          return Marker(
                            point: LatLng(s.lat, s.lng),
                            width: sel ? 24 : 18,
                            height: sel ? 24 : 18,
                            child: GestureDetector(
                              onTap: () => setState(() => _selected = s),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: chainColor(s.chainSlug),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: sel ? AppTheme.warnAmber : Colors.white,
                                      width: sel ? 3 : 2),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black26, blurRadius: 2),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_selected != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Card(
                      child: ListTile(
                        leading: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: chainColor(_selected!.chainSlug),
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(_selected!.chainName,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${_selected!.address}${_selected!.distanceText != null ? ' · ${_selected!.distanceText}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Навигация',
                              icon: const Icon(Icons.directions, color: AppTheme.primaryGreen),
                              onPressed: () => openInMaps(_selected!.lat, _selected!.lng),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _selected = null),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(List<_Legend> legend) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 44,
      color: isDark ? AppTheme.darkCard : Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        itemCount: legend.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final l = legend[i];
          final hidden = _hidden.contains(l.brand);
          return InkWell(
            onTap: () => setState(() {
              if (hidden) {
                _hidden.remove(l.brand);
              } else {
                _hidden.add(l.brand);
                if (_selected != null && prettyChainName(_selected!.chainName) == l.brand) {
                  _selected = null;
                }
              }
            }),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hidden
                    ? (isDark ? AppTheme.darkLine : Colors.grey.shade200)
                    : chainColor(l.slug).withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: chainColor(l.slug), width: hidden ? 0 : 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: hidden ? AppTheme.mutedText : chainColor(l.slug),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${l.brand} (${l.count})',
                      style: TextStyle(
                        fontSize: 12,
                        decoration: hidden ? TextDecoration.lineThrough : null,
                        color: hidden ? AppTheme.mutedText : (isDark ? AppTheme.primaryTextDark : Colors.black87),
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Legend {
  final String brand;
  final String slug;
  int count;
  _Legend(this.brand, this.slug, this.count);
}
