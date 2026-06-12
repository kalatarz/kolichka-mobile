/// Open an external maps app (Google Maps / browser) for navigation.
library;

import 'package:url_launcher/url_launcher.dart';

Future<void> openInMaps(double lat, double lng, [String? label]) async {
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {/* no maps app / no browser */}
}
