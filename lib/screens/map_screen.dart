import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import '../models/store.dart';
import '../services/api_service.dart';
import '../services/analytics.dart';
import '../services/external.dart';
import '../widgets/chain_colors.dart';

class MapScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final double radiusKm;
  final double? articleLat;
  final double? articleLng;
  final int? articleStoreId;
  /// Optional product name — when set, highlights stores selling this product.
  final String? productQuery;

  const MapScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    this.articleLat,
    this.articleLng,
    this.articleStoreId,
    this.productQuery,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final ApiService _api = ApiService();
  final MapController _mapController = MapController();
  List<Store> _stores = [];
  bool _loading = true;
  Store? _selected;
  final Set<String> _hidden = {};

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
      
      if (widget.articleLat != null && widget.articleLng != null) {
        _mapController.move(LatLng(widget.articleLat!, widget.articleLng!), 15);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

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
    final center = LatLng(widget.articleLat ?? widget.lat, widget.articleLng ?? widget.lng);
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
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center, 
                    initialZoom: 13,
                    interactionOptions: InteractionOptions(),
                  ),
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
                        // Article marker
                        if (widget.articleLat != null && widget.articleLng != null)
                          Marker(
                            point: LatLng(widget.articleLat!, widget.articleLng!),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.location_on, color: Colors.red, size: 30),
                          ),
                        // Target store marker
                        if (widget.articleStoreId != null)
                          ..._getStoreMarkers(widget.articleStoreId!),
                          
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
                                      color: sel ? Colors.amber : Colors.white,
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
                _buildZoomControls(),
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
                              icon: const Icon(Icons.directions, color: Colors.blue),
                              onPressed: () => openInMaps('${_selected!.lat}, ${_selected!.lng}'),
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

  List<Marker> _getStoreMarkers(int storeId) {
    final store = _stores.firstWhereOrNull((s) => s.id == storeId);
    if (store == null) return [];
    return [
      Marker(
        point: LatLng(store.lat, store.lng),
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.shop, color: Colors.white, size: 20),
        ),
      ),
    ];
  }

  Widget _buildZoomControls() {
    return Positioned(
      right: 16,
      bottom: 120,
      child: Column(
        children: [
          FloatingActionButton.small(
            heroTag: 'zoomIn',
            onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'zoomOut',
            onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
            child: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(List<_Legend> legend) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 44,
      color: isDark ? Theme.of(context).colorScheme.surface : Colors.white,
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
                if (_selected != null && prettyChainName(_selected!.chainSlug) == l.brand) {
                  _selected = null;
                }
              }
            }),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hidden
                    ? Theme.of(context).colorScheme.outlineVariant
                    : chainColor(l.slug).withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: hidden ? Theme.of(context).colorScheme.outlineVariant : chainColor(l.slug), 
                    width: hidden ? 0 : 1),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 2),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: hidden ? Theme.of(context).colorScheme.onSurfaceVariant : chainColor(l.slug),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${l.brand} (${l.count})',
                      style: TextStyle(
                        fontSize: 12,
                        decoration: hidden ? TextDecoration.lineThrough : null,
                        color: hidden ? Theme.of(context).colorScheme.onSurfaceVariant : (isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87),
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
