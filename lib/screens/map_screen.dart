/// Map of nearby stores (OpenStreetMap via flutter_map).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/store.dart';
import '../services/api_service.dart';
import '../services/analytics.dart';
import '../widgets/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.lat, widget.lng);
    return Scaffold(
      appBar: AppBar(title: Text('Магазини на картата (${_stores.length})')),
      body: Stack(
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
                  // user
                  Marker(
                    point: center,
                    width: 26,
                    height: 26,
                    child: const Icon(Icons.my_location, color: Colors.blue, size: 24),
                  ),
                  // stores
                  ..._stores.map((s) => Marker(
                        point: LatLng(s.lat, s.lng),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => setState(() => _selected = s),
                          child: Icon(Icons.location_on,
                              color: _selected?.id == s.id
                                  ? AppTheme.warnAmber
                                  : AppTheme.primaryGreen,
                              size: 34),
                        ),
                      )),
                ],
              ),
            ],
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_selected != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.store, color: AppTheme.primaryGreen),
                  title: Text(_selected!.chainName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${_selected!.address}${_selected!.distanceText != null ? ' · ${_selected!.distanceText}' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _selected = null),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
