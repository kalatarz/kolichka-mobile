/// Open an external maps app (Google Maps / browser) for navigation.
library;

import 'package:url_launcher/url_launcher.dart';

Future<void> openInMaps(double lat, double lng, [String? label]) async {
  final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
  try {
    if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  try {
    await launchUrl(geo, mode: LaunchMode.externalApplication);
  } catch (_) {}
}
