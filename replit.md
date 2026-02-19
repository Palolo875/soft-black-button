# Horizon - Weather-Aware Cycling Navigation

## Overview
A Flutter web application for weather-aware cycling navigation with comfort scoring, route explainability, and offline support. Features an interactive map powered by MapLibre GL.

## Project Architecture
- **Framework**: Flutter (Dart) targeting web
- **Flutter SDK**: 3.32.0 (via nix)
- **Dart SDK**: 3.10.4
- **Map Engine**: MapLibre GL (via maplibre_gl package)
- **State Management**: Provider pattern
- **Offline Tiles**: PMTiles support

## Project Structure
```
lib/
  main.dart              - App entry point
  core/                  - Constants, DI, error handling, mobility models
  features/map/          - Map screen and presentation widgets
  providers/             - State management (ChangeNotifier providers)
  services/              - Business logic, APIs, caching, routing
  ui/                    - Design system (theme, breakpoints, cards, chips)
  widgets/
    horizon_map.dart     - MapLibre GL map widget
assets/
  styles/
    horizon_style.json   - Map style configuration
web/
  index.html             - Web entry point with PMTiles/MapLibre JS
build/web/               - Built Flutter web output (served in production)
serve.dart               - Simple Dart HTTP server for serving built app on port 5000
```

## Key Dependencies
- maplibre_gl: ^0.25.0
- flutter_map: ^8.2.2
- provider: ^6.1.5+1
- http: ^1.6.0
- path_provider: ^2.1.5
- geolocator: ^14.0.2
- pmtiles: ^1.3.0
- connectivity_plus: ^7.0.0
- flutter_secure_storage: ^10.0.0
- flutter_local_notifications: ^20.1.0

## Build & Run
- Build: `flutter build web --release --base-href "/"`
- Serve: `dart run serve.dart` (port 5000)
- The workflow runs `dart run serve.dart` to serve the pre-built Flutter web app

## Deployment
- Autoscale deployment
- Build step: `flutter build web --release --base-href /`
- Run step: `dart run serve.dart`

## Environment Variables
- `VALHALLA_BASE_URL` - Valhalla routing server (default: https://valhalla1.openstreetmap.de)
- `METNO_USER_AGENT` - User-Agent for Met.no API (required by their ToS)

## Recent Changes
- 2026-02-19: Full Upgrade of Dependencies & SDK
  - Upgraded Flutter dependencies to latest major versions (flutter_map 8.2.2, connectivity_plus 7.0.0, etc.)
  - Updated Dart SDK constraint to ^3.8.0 in pubspec.yaml
  - Refactored `NotificationService` to support breaking changes in `flutter_local_notifications` 20.1.0
  - Verified build and serving on port 5000
- 2026-02-19: Set up in Replit environment
  - Installed Dart 3.10 module and Flutter 3.32.0 via nix
  - Fixed CardTheme -> CardThemeData API compatibility
  - Built Flutter web app successfully
  - Configured serve.dart workflow on port 5000
  - Configured autoscale deployment
