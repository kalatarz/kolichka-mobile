/// Open an external maps/navigation app for a place.
///
/// For coordinates ("lat, lng") we fire a `geo:` intent, which makes Android
/// show the app chooser (Google Maps, Waze, organic maps, …) so the user can
/// pick which app guides them. Falls back to a Google Maps web URL.
library;

import 'package:url_launcher/url_launcher.dart';

Future<void> openInMaps(String query) async {
  final q = query.trim();
  final isCoords =
      RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$').hasMatch(q);
  if (isCoords) {
    final c = q.replaceAll(' ', '');
    try {
      // geo: → Android shows a chooser of installed navigation apps.
      if (await launchUrl(Uri.parse('geo:$c?q=$c'),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
  }
  try {
    await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}'),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}
}
