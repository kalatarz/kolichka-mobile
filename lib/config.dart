/// Application configuration.
///
/// The API base URL is read from the environment at runtime.
/// In production this is set via Info.plist / AndroidManifest.xml placeholders.
/// For local development, override with the LOCAL_API_BASE_URL constant below.
///
/// IMPORTANT: Never commit real credentials or tokens to this file.
/// All API endpoints are public and do not require authentication.
library;

/// Override for local development only. Set to null in production builds.
/// Example: 'http://192.168.x.x:3000'
const String? _localApiBaseUrl = null;

class Config {
  Config._();

  /// App version, set at startup from the build (see main.dart).
  static String appVersion = '1.0.0';
  static String appBuild = '1';

  /// User-Agent sent on every API call so the platform can see app traffic
  /// + which version is visiting (grep server logs for 'KolichkaApp').
  static String get userAgent =>
      'KolichkaApp/$appVersion (Android; build $appBuild)';

  /// Base URL for the Kolichka API.
  /// In production this points to the public domain.
  /// During development you can override via [_localApiBaseUrl].
  static String get apiBaseUrl {
    // Check if FLUTTER_API_BASE_URL is set (e.g., via --dart-define)
    return String.fromEnvironment(
      'FLUTTER_API_BASE_URL',
      defaultValue: _localApiBaseUrl ?? 'https://kolichka.gotvach.com',
    );
  }

  /// Default search radius in kilometres.
  static const double defaultRadiusKm = 3.0;

  /// Minimum search radius in kilometres.
  static const double minRadiusKm = 0.5;

  /// Maximum search radius in kilometres.
  static const double maxRadiusKm = 25.0;

  /// Step for radius slider.
  static const double radiusStep = 0.5;

  /// Max promotions per chain.
  static const int maxPromotionsPerChain = 15;

  /// Max stale days for promotions (exclude older).
  static const int maxStaleDays = 2;
}
