# Horizon - Flutter Web Map Application

## Overview
A Flutter web application featuring an interactive map powered by MapLibre GL, weather information, offline tile support via PMTiles, and location-based features. The UI is in French.

## Project Architecture
- **Framework**: Flutter (Dart) targeting web
- **Flutter SDK**: 3.29.3 (installed at `/home/runner/flutter`)
- **Dart SDK**: 3.7.2
- **Map Engine**: MapLibre GL (via maplibre_gl package)
- **State Management**: Provider pattern
- **Offline Tiles**: PMTiles support

## Project Structure
```
lib/
  main.dart              - App entry point and main UI (MapScreen)
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
serve.dart               - Simple Dart HTTP server for serving built app
```

## Key Dependencies
- maplibre_gl: ^0.25.0
- provider: ^6.1.5+1
- http: ^1.6.0
- path_provider: ^2.1.5
- geolocator: ^14.0.2
- pmtiles: ^1.3.0

## Build & Run
- Build: `export PATH="/home/runner/flutter/bin:$PATH" && flutter build web --release --base-href "/"`
- Serve: `export PATH="/home/runner/flutter/bin:$PATH" && dart run serve.dart` (port 5000)

## Deployment
- Static deployment serving `build/web` directory

## Recent Changes
- 2026-02-19: Migrated to Replit environment
  - Installed Flutter SDK 3.29.3 (pre-built archive)
  - Downgraded SDK constraint to ^3.7.0 and flutter_lints to ^5.0.0
  - Fixed compilation errors (missing imports, API compatibility with Dart 3.7.2)
  - Successfully built Flutter web app
- 2026-02-17: Initial Replit setup
  - Installed Flutter SDK 3.41.1
  - Fixed compilation errors (missing imports for LatLng, unawaited, updated PmTilesArchive API)
  - Created serve.dart for static file serving on port 5000
  - Configured static deployment
