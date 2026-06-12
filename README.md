# Количка — Mobile App (Flutter)

[![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Сравни цени на хранителни продукти в магазините около теб.

## Features

- **Product Search** — Search for any grocery product and compare prices across nearby stores
- **Basket Comparison** — Add multiple items and see which store has the best total price
- **Promotions** — Browse current deals and discounts from all major chains
- **Map View** — See nearby stores on an interactive map
- **Radius Control** — Adjust search radius from 0.5 km to 25 km

## Architecture

```
lib/
├── main.dart              # App entry point
├── config.dart            # Runtime configuration (API URL via dart-define)
├── models/                # Data models matching API responses
│   ├── category.dart
│   ├── store.dart
│   ├── compare_result.dart
│   ├── basket_result.dart
│   ├── promotion_result.dart
│   └── geocode_result.dart
├── services/              # API and location services
│   ├── api_service.dart
│   └── location_service.dart
├── screens/               # UI screens
│   ├── home_screen.dart
│   ├── search_results_screen.dart
│   ├── basket_screen.dart
│   └── promotions_screen.dart
└── widgets/               # Reusable UI components
    └── app_theme.dart
```

## Prerequisites

- Flutter 3.29+ (Dart 3.7+)
- Xcode 15+ (for iOS builds)
- macOS host machine

## Getting Started

```bash
# Clone and install dependencies
git clone <repo-url>
cd kolichka-mobile
flutter pub get

# Run with production API (default)
flutter run

# Run with custom API URL
flutter run --dart-define=FLUTTER_API_BASE_URL=http://192.168.x.x:3000
```

## Configuration

The API base URL is configured at runtime via `--dart-define`:

```bash
flutter run --dart-define=FLUTTER_API_BASE_URL=https://kolichka.gotvach.com
```

**Never hardcode credentials or tokens.** All Kolichka API endpoints are public and do not require authentication.

## Backend API

This app connects to the Kolichka backend API documented at:
https://github.com/macrometa/matcho/blob/master/API.md

### Endpoints Used

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/categories` | GET | Product categories for quick search |
| `/api/compare` | GET | Price comparison for a product |
| `/api/basket` | GET | Multi-item basket comparison |
| `/api/promotions` | GET | Current promotions and deals |
| `/api/stores/nearby` | GET | Stores within a radius |
| `/api/geocode` | GET | Address geocoding |
| `/api/feedback` | POST | User feedback submission |

## Security

See [SECURITY.md](SECURITY.md) for responsible disclosure policy.

## License

This project is licensed under the GNU General Public License v3.0 — see the [LICENSE](LICENSE) file.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## Credits

Built with Flutter. Map tiles by OpenStreetMap contributors.

## Analytics (official builds only)

Optional, anonymous product analytics — **off by default**. Building from source
produces a build that sends **no** data. The official Google Play build turns it
on via build flags:

```
flutter build apk --release \
  --dart-define=ANALYTICS_ENABLED=true \
  --dart-define=UMAMI_WEBSITE_ID=<umami-website-uuid> \
  --dart-define=APP_VERSION=1.0.0
```

Events go to a self-hosted [Umami](https://umami.is) instance via `/api/send`.
No PII: only a random per-install id (not the device/ad id), the install-date
cohort, app version, and funnel events (`first_open`, `app_open`,
`location_ok`/`location_fail`, `search`, `saw_prices`, `add_to_basket`,
`favorite_add`/`favorite_remove`, `open_basket`, `compare_basket`,
`rating_submitted`). The drop-off between `app_open` and `saw_prices` is the
onboarding-leak signal. Actual installs/uninstalls and retention cohorts come
from Google Play Console.
