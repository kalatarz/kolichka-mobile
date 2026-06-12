/// Location service using device GPS.
///
/// Handles permission requests and provides the current position.
library;

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static const _savedLatKey = 'last_lat';
  static const _savedLngKey = 'last_lng';
  static const _savedAddressKey = 'last_address';

  /// Determine if location services are enabled and permissions are granted.
  Future<bool> isLocationAvailable() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    final status = await Geolocator.checkPermission();
    return status == LocationPermission.always || status == LocationPermission.whileInUse;
  }

  /// Request location permission and return current position.
  Future<Position> getCurrentPosition() async {
    // Resolve permission first. On Android < 6 this is granted at install time
    // and returns immediately; on newer Android it shows the runtime prompt.
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }
    if (status == LocationPermission.denied ||
        status == LocationPermission.deniedForever) {
      throw const LocationException('Location permission denied.');
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // GPS/location services off — best effort with any cached fix.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      throw const LocationException('Location services are disabled.');
    }

    // Medium accuracy + a generous timeout is far more reliable on old phones
    // and indoors than a 15s high-accuracy GPS-only request (which times out).
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 30),
        ),
      );
    } catch (_) {
      // No fresh fix in time — fall back to the last known position.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      rethrow;
    }
  }

  /// Save last known position to persistent storage.
  Future<void> savePosition(Position pos, {String? address}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_savedLatKey, pos.latitude);
    await prefs.setDouble(_savedLngKey, pos.longitude);
    if (address != null) {
      await prefs.setString(_savedAddressKey, address);
    }
  }

  /// Load last known position from persistent storage.
  Future<Position?> getLastPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_savedLatKey);
    final lng = prefs.getDouble(_savedLngKey);
    if (lat != null && lng != null) {
      return Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }
    return null;
  }

  /// Get saved address label.
  Future<String?> getLastAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedAddressKey);
  }

  /// Clear saved position.
  Future<void> clearSavedPosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedLatKey);
    await prefs.remove(_savedLngKey);
    await prefs.remove(_savedAddressKey);
  }
}

/// Custom exception for location errors.
class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
  @override
  String toString() => 'LocationException: $message';
}
