# 🌤️ HORIZON

**Weather-aware cycling navigation** — comfort scoring, route explainability, and full offline support.

---

## ✨ Features

| Feature | Description |
|---|---|
| **Multi-variant routing** | Fast, safe, scenic, and GPX-imported routes via Valhalla |
| **Weather-aware comfort** | Dual-source weather engine (Open-Meteo + Met.no fallback) with a parametric comfort model for cycling |
| **Explainability engine** | Transparent explanations for route recommendations (wind, rain, temperature, confidence) |
| **Departure window** | Recommends optimal departure time across a configurable horizon |
| **Offline support** | PMTiles-based offline maps, weather and route caching |
| **Privacy-first** | No account, no tracking, local-only encrypted storage, panic wipe |
| **Expert weather layers** | Wind, rain, and cloud overlay toggling |
| **Contextual notifications** | Opt-in rain alerts along the planned route |

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── constants/       # Centralized magic numbers & thresholds
│   ├── di/              # Dependency injection container (AppDependencies)
│   ├── format/          # Pure formatting utilities
│   └── log/             # Structured logging (AppLog)
├── features/
│   └── map/
│       └── presentation/
│           ├── map_screen.dart          # Main screen (layout + lifecycle)
│           ├── utils/                   # Glass decoration, format helpers
│           └── widgets/                 # Extracted UI components
│               ├── weather_status_pill   # Top weather summary
│               ├── route_info_card       # Route metrics card
│               ├── route_chip            # Variant selector chips
│               ├── settings_sheet        # Privacy & data management
│               ├── expert_weather_sheet  # Expert weather layers
│               └── offline_progress_bar  # Download progress overlay
├── providers/           # ChangeNotifier state management
│   ├── map_provider     # Map controller orchestration
│   ├── weather_provider # Weather state & expert layers
│   ├── routing_provider # Route computation, GPX import
│   ├── offline_provider # Offline packs & PMTiles
│   ├── connectivity_provider
│   ├── location_provider
│   └── app_settings_provider
├── services/            # Stateless business logic
│   ├── weather_engine_sota   # Dual-source weather with fallback
│   ├── routing_engine        # Valhalla multi-variant computation
│   ├── comfort_model         # Parametric cycling comfort scoring
│   ├── explainability_engine # Route recommendation explanations
│   ├── route_weather_projector # Weather sampling along routes
│   ├── route_compare_service   # Departure time comparison
│   ├── valhalla_client         # Valhalla API client
│   ├── secure_http_client      # HTTPS-only with certificate pinning
│   ├── offline_*               # Offline map management (IO/Web)
│   ├── privacy_service         # Local data management
│   └── analytics_service       # Opt-in local analytics
├── ui/                  # Design system
│   ├── horizon_theme    # Material3 light/dark themes + tokens
│   ├── horizon_card     # Glassmorphism card
│   ├── horizon_chip     # Selection chip
│   ├── horizon_bottom_sheet
│   └── horizon_breakpoints
└── widgets/
    └── horizon_map      # MapLibre GL wrapper
```

### Key Design Decisions

- **Provider** for state management — lightweight, sufficient for single-screen app
- **Conditional exports** (`_io.dart` / `_web.dart`) for platform-specific implementations
- **Constructor injection** via `AppDependencies` container — no DI framework needed at this scale
- **No domain layer** (yet) — services are thin enough that separate use cases would add boilerplate without benefit

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `^3.10.7`
- Dart SDK `^3.10.7`

### Run

```bash
# Install dependencies
flutter pub get

# Run on device/emulator
flutter run

# Run on web
flutter run -d chrome

# Run tests
flutter test
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `VALHALLA_BASE_URL` | `https://valhalla1.openstreetmap.de` | Valhalla routing server |
| `VALHALLA_TLS_PINS_B64` | _(empty)_ | Base64-encoded TLS certificate pins, semicolon-separated |
| `METNO_USER_AGENT` | — | User-Agent for Met.no API (required by their ToS) |

---

## 🧪 Testing

```bash
flutter test
```

Tests cover:
- `ComfortModel` — rain, wind, temperature, night penalties
- `ExplainabilityEngine` — factor generation, headline logic
- `RouteCompareService` — departure comparison metrics
- `RouteGeometry` — haversine, polyline length
- `SecureHttpClient` — HTTPS enforcement, certificate pinning
- `RoutingProvider` — state transitions, route computation
- `OfflineProvider` — pack management, PMTiles toggling
- `OfflineIntegrity` — file verification

---

## 📄 License

Private — all rights reserved.
