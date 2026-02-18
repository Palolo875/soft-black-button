import 'package:app/providers/routing_provider.dart';
import 'package:app/services/analytics_service.dart';
import 'package:app/services/explainability_engine.dart';
import 'package:app/services/gpx_import_service.dart';
import 'package:app/services/horizon_scheduler.dart';
import 'package:app/services/perf_metrics.dart';
import 'package:app/services/route_cache.dart';
import 'package:app/services/route_compare_service.dart';
import 'package:app/services/route_weather_projector.dart';
import 'package:app/services/routing_engine.dart';
import 'package:app/services/routing_models.dart';
import 'package:app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class _FakeRoutingEngine extends RoutingEngine {
  final List<RouteVariant> variants;
  _FakeRoutingEngine(this.variants);

  @override
  Future<List<RouteVariant>> computeVariants({
    required LatLng start,
    required LatLng end,
    required DateTime departureTime,
    required double speedMetersPerSecond,
    double sampleEveryMeters = 450,
    int maxSamples = 120,
  }) async {
    return variants;
  }
}

class _FakeProjector extends RouteWeatherProjector {
  @override
  Future<List<RouteWeatherSample>> projectAlongPolyline({
    required List<LatLng> polyline,
    required DateTime departureTime,
    required double speedMetersPerSecond,
    double sampleEveryMeters = 1000,
    int maxSamples = 60,
  }) async {
    return const [];
  }
}

class _FakeMapController implements MaplibreMapController {
  final Map<String, Object?> sources = {};

  @override
  Future<void> addSource(String sourceId, SourceProperties properties) async {
    sources[sourceId] = properties;
  }

  @override
  Future<void> setGeoJsonSource(String sourceId, Object geojson) async {
    sources[sourceId] = geojson;
  }

  @override
  Future<void> addLineLayer(String sourceId, String layerId, LineLayerProperties properties, {String? belowLayerId}) async {}

  @override
  Future<void> addCircleLayer(String sourceId, String layerId, CircleLayerProperties properties, {String? belowLayerId}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemRouteCache extends RouteCache {
  final Map<String, Map<String, dynamic>> mem = {};

  @override
  Future<RouteCacheEntry?> read(String key) async {
    final payload = mem[key];
    if (payload == null) return null;
    return RouteCacheEntry(savedAt: DateTime.now().toUtc(), payload: payload);
  }

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {
    mem[key] = payload;
  }
}

class _NoopGpx extends GpxImportService {
  @override
  Future<GpxImportResult?> pickAndParse() async => null;
}

void main() {
  test('RoutingProvider computeRouteVariants populates routeVariants and selects first variant', () async {
    final variants = <RouteVariant>[
      const RouteVariant(
        kind: RouteVariantKind.fast,
        shape: <LatLng>[LatLng(0, 0), LatLng(1, 1)],
        lengthKm: 1.0,
        timeSeconds: 10.0,
        weatherSamples: <RouteWeatherSample>[],
      ),
      const RouteVariant(
        kind: RouteVariantKind.safe,
        shape: <LatLng>[LatLng(0, 0), LatLng(2, 2)],
        lengthKm: 2.0,
        timeSeconds: 20.0,
        weatherSamples: <RouteWeatherSample>[],
      ),
    ];

    final provider = RoutingProvider(
      routingEngine: _FakeRoutingEngine(variants),
      routeCache: _MemRouteCache(),
      scheduler: HorizonScheduler(),
      metrics: PerfMetrics(),
      analytics: AnalyticsService(),
      routeCompare: RouteCompareService(projector: _FakeProjector()),
      gpxImport: _NoopGpx(),
      routeWeatherProjector: _FakeProjector(),
      explainability: const ExplainabilityEngine(),
      notifications: NotificationService(),
    );

    provider.setController(_FakeMapController());
    provider.setStyleLoaded(true);
    provider.syncIsOnline(true);

    provider.setRoutePoint(const LatLng(0, 0));
    provider.setRoutePoint(const LatLng(1, 1));

    await provider.computeRouteVariants();

    expect(provider.routeVariants, hasLength(2));
    expect(provider.selectedVariant, RouteVariantKind.fast);
  });
}
