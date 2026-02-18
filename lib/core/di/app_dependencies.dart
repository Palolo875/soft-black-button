import 'package:app/services/analytics_service.dart';
import 'package:app/services/explainability_engine.dart';
import 'package:app/services/gpx_import_service.dart';
import 'package:app/services/horizon_scheduler.dart';
import 'package:app/services/notification_service.dart';
import 'package:app/services/notification_settings_store.dart';
import 'package:app/services/offline_service.dart';
import 'package:app/services/perf_metrics.dart';
import 'package:app/services/privacy_service.dart';
import 'package:app/services/route_cache.dart';
import 'package:app/services/route_compare_service.dart';
import 'package:app/services/route_weather_projector.dart';
import 'package:app/services/routing_engine.dart';
import 'package:app/services/theme_settings_store.dart';
import 'package:app/services/weather_engine_sota.dart';
import 'package:app/services/weather_service.dart';

class AppDependencies {
  final WeatherService weatherService;
  final WeatherEngineSota weatherEngine;
  final RoutingEngine routingEngine;
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
  final ThemeSettingsStore themeStore;
  final ExplainabilityEngine explainability;

  const AppDependencies({
    required this.weatherService,
    required this.weatherEngine,
    required this.routingEngine,
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
    required this.themeStore,
    required this.explainability,
  });

  factory AppDependencies.create() {
    return AppDependencies(
      weatherService: WeatherService(),
      weatherEngine: WeatherEngineSota(),
      routingEngine: RoutingEngine(),
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
      themeStore: ThemeSettingsStore(),
      explainability: const ExplainabilityEngine(),
    );
  }
}
