import 'package:horizon/services/analytics_service.dart';
import 'package:horizon/services/explainability_engine.dart';
import 'package:horizon/services/gpx_import_service.dart';
import 'package:horizon/services/horizon_scheduler.dart';
import 'package:horizon/services/notification_service.dart';
import 'package:horizon/services/notification_settings_store.dart';
import 'package:horizon/services/offline_service.dart';
import 'package:horizon/services/perf_metrics.dart';
import 'package:horizon/services/privacy_service.dart';
import 'package:horizon/services/home_today_engine.dart';
import 'package:horizon/services/home_today_store.dart';
import 'package:horizon/services/route_cache.dart';
import 'package:horizon/services/route_compare_service.dart';
import 'package:horizon/services/route_weather_projector.dart';
import 'package:horizon/services/routing_engine.dart';
import 'package:horizon/services/trip_engine.dart';
import 'package:horizon/services/trip_store.dart';
import 'package:horizon/services/mobility_settings_store.dart';
import 'package:horizon/services/theme_settings_store.dart';
import 'package:horizon/services/weather_engine_sota.dart';
import 'package:horizon/services/weather_service.dart';

class AppDependencies {
  final WeatherService weatherService;
  final WeatherEngineSota weatherEngine;
  final HomeTodayStore homeTodayStore;
  final HomeTodayEngine homeTodayEngine;
  final RoutingEngine routingEngine;
  final TripEngine tripEngine;
  final TripStore tripStore;
  final RouteCache routeCache;
  final OfflineService offlineService;
  final PrivacyService privacyService;
  final AnalyticsService analytics;
  final HorizonScheduler scheduler;
  final PerfMetrics metrics;
  final RouteCompareService routeCompare;
  final GpxImportService gpxImport;
  final RouteWeatherProjector routeWeatherProjector;
  final NotificationService notifications;
  final NotificationSettingsStore notificationStore;
  final MobilitySettingsStore mobilityStore;
  final ThemeSettingsStore themeStore;
  final ExplainabilityEngine explainability;

  const AppDependencies({
    required this.weatherService,
    required this.weatherEngine,
    required this.homeTodayStore,
    required this.homeTodayEngine,
    required this.routingEngine,
    required this.tripEngine,
    required this.tripStore,
    required this.routeCache,
    required this.offlineService,
    required this.privacyService,
    required this.analytics,
    required this.scheduler,
    required this.metrics,
    required this.routeCompare,
    required this.gpxImport,
    required this.routeWeatherProjector,
    required this.notifications,
    required this.notificationStore,
    required this.mobilityStore,
    required this.themeStore,
    required this.explainability,
  });

  factory AppDependencies.create() {
    final weatherEngine = WeatherEngineSota();
    final routingEngine = RoutingEngine();
    return AppDependencies(
      weatherService: WeatherService(),
      weatherEngine: weatherEngine,
      homeTodayStore: HomeTodayStore(),
      homeTodayEngine: HomeTodayEngine(weatherEngine: weatherEngine),
      routingEngine: routingEngine,
      tripEngine: TripEngine(routingEngine: routingEngine),
      tripStore: TripStore(),
      routeCache: RouteCache(encrypted: true),
      offlineService: OfflineService(),
      privacyService: const PrivacyService(),
      analytics: AnalyticsService(),
      scheduler: HorizonScheduler(),
      metrics: PerfMetrics(),
      routeCompare: RouteCompareService(),
      gpxImport: GpxImportService(),
      routeWeatherProjector: RouteWeatherProjector(),
      notifications: NotificationService(),
      notificationStore: NotificationSettingsStore(),
      mobilityStore: MobilitySettingsStore(),
      themeStore: ThemeSettingsStore(),
      explainability: const ExplainabilityEngine(),
    );
  }
}
