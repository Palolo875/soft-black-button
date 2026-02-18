import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:app/core/log/app_log.dart';
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

class RoutingProvider with ChangeNotifier {
  final RoutingEngine _routingEngine;
  final RouteCache _routeCache;
  final HorizonScheduler _scheduler;
  final PerfMetrics _metrics;
  final AnalyticsService _analytics;
  final RouteCompareService _routeCompare;
  final GpxImportService _gpxImport;
  final RouteWeatherProjector _routeWeatherProjector;
  final ExplainabilityEngine _explainability;
  final NotificationService _notifications;

  MaplibreMapController? _mapController;
  bool _styleLoaded = false;

  double _timeOffset = 0.0;
  bool _lowPowerMode = false;
  bool _appInForeground = true;
  bool? _isOnline;

  LatLng? _routeStart;
  LatLng? _routeEnd;
  bool _routingLoading = false;
  String? _routingError;
  List<RouteVariant> _routeVariants = const [];
  RouteVariantKind _selectedVariant = RouteVariantKind.fast;

  Timer? _routeDebounce;
  DateTime? _lastRouteComputeAt;
  String? _routeExplanation;
  Map<RouteVariantKind, RouteExplanation> _routeExplanations = const {};
  RouteWeatherSample? _selectedRouteWeatherSample;

  bool _gpxImportLoading = false;
  String? _gpxImportError;
  String? _gpxRouteName;

  bool _notificationsEnabledForContextual = false;
  DateTime? _lastNotificationAt;

  _DepartureCompareCacheEntry? _departureCompareCache;
  _DepartureWindowCacheEntry? _departureWindowCache;

  LatLng? get routeStart => _routeStart;
  LatLng? get routeEnd => _routeEnd;
  bool get routingLoading => _routingLoading;
  String? get routingError => _routingError;
  List<RouteVariant> get routeVariants => _routeVariants;
  RouteVariantKind get selectedVariant => _selectedVariant;
  String? get routeExplanation => _routeExplanation;
  Map<RouteVariantKind, RouteExplanation> get routeExplanations => _routeExplanations;
  RouteExplanation? get currentRouteExplanation => _routeExplanations[_selectedVariant];
  RouteWeatherSample? get selectedRouteWeatherSample => _selectedRouteWeatherSample;

  bool get gpxImportLoading => _gpxImportLoading;
  String? get gpxImportError => _gpxImportError;
  String? get gpxRouteName => _gpxRouteName;

  RoutingProvider({
    required RoutingEngine routingEngine,
    required RouteCache routeCache,
    required HorizonScheduler scheduler,
    required PerfMetrics metrics,
    required AnalyticsService analytics,
    required RouteCompareService routeCompare,
    required GpxImportService gpxImport,
    required RouteWeatherProjector routeWeatherProjector,
    required ExplainabilityEngine explainability,
    required NotificationService notifications,
  })  : _routingEngine = routingEngine,
        _routeCache = routeCache,
        _scheduler = scheduler,
        _metrics = metrics,
        _analytics = analytics,
        _routeCompare = routeCompare,
        _gpxImport = gpxImport,
        _routeWeatherProjector = routeWeatherProjector,
        _explainability = explainability,
        _notifications = notifications;

  void setController(MaplibreMapController controller) {
    _mapController = controller;
  }

  void setStyleLoaded(bool loaded) {
    _styleLoaded = loaded;
    if (loaded) {
      unawaited(_ensureRouteLayers());
    }
  }

  void syncIsOnline(bool? isOnline) {
    _isOnline = isOnline;
  }

  void syncLowPowerMode(bool enabled) {
    _lowPowerMode = enabled;
  }

  void syncAppInForeground(bool fg) {
    _appInForeground = fg;
  }

  void syncTimeOffset(double value) {
    _timeOffset = value;
  }

  DateTime _forecastBaseUtc() {
    final minutes = (_timeOffset * 60).round();
    return DateTime.now().toUtc().add(Duration(minutes: minutes));
  }

  String confidenceLabel(double confidence) {
    if (confidence >= 0.75) return 'Fiable';
    if (confidence >= 0.50) return 'Variable';
    return 'Incertain';
  }

  String? get selectedSampleReliabilityLabel {
    final c = _selectedRouteWeatherSample?.confidence;
    if (c == null) return null;
    return confidenceLabel(c);
  }

  void syncNotificationsEnabledFromSettings(bool enabled) {
    _notificationsEnabledForContextual = enabled;
    if (enabled) {
      unawaited(_evaluateAndNotifyContextual());
    }
  }

  void setRoutePoint(LatLng point) {
    if (_routeStart == null || (_routeStart != null && _routeEnd != null)) {
      _routeStart = point;
      _routeEnd = null;
      _routeVariants = const [];
      _routingError = null;
      notifyListeners();
      unawaited(_renderRouteMarkers());
      return;
    }

    _routeEnd = point;
    _routeVariants = const [];
    _routingError = null;
    _routeExplanation = null;
    _routeExplanations = const {};
    _selectedRouteWeatherSample = null;
    notifyListeners();
    unawaited(_renderRouteMarkers());
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 450), () {
      final snap = SchedulerSnapshot(
        appInForeground: _appInForeground,
        isOnline: _isOnline ?? true,
        lowPowerMode: _lowPowerMode,
        navigationActive: true,
        speedMps: null,
      );
      if (_scheduler.shouldComputeRouting(snap, userInitiated: true)) {
        unawaited(computeRouteVariants());
      }
    });
  }

  Future<void> clearRoute() async {
    _routeStart = null;
    _routeEnd = null;
    _routeVariants = const [];
    _routingError = null;
    _routeExplanation = null;
    _routeExplanations = const {};
    _selectedRouteWeatherSample = null;
    _routeDebounce?.cancel();
    _gpxRouteName = null;
    notifyListeners();
    await _clearRouteLayers();
  }

  void selectRouteVariant(RouteVariantKind kind) {
    if (_selectedVariant == kind) return;
    _selectedVariant = kind;
    _selectedRouteWeatherSample = null;
    _routeExplanation = currentRouteExplanation?.headline;
    notifyListeners();
    unawaited(_renderSelectedRoute());
    unawaited(_evaluateAndNotifyContextual());
  }

  RouteVariant? _currentVariant() {
    if (_routeVariants.isEmpty) return null;
    for (final v in _routeVariants) {
      if (v.kind == _selectedVariant) return v;
    }
    return _routeVariants.first;
  }

  Future<void> computeRouteVariants() async {
    final start = _routeStart;
    final end = _routeEnd;
    if (start == null || end == null) return;
    if (!_styleLoaded) return;

    await _ensureRouteLayers();

    final now = DateTime.now();
    final last = _lastRouteComputeAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastRouteComputeAt = now;

    _routingError = null;
    _routingLoading = true;
    notifyListeners();

    if (_isOnline == false) {
      try {
        final cached = await _loadRouteCache(start, end);
        if (cached != null) {
          _routeVariants = cached;
          _routingError = 'Mode conservateur (offline)';
          _routingLoading = false;
          notifyListeners();
          await _afterVariantsUpdated();
          return;
        }
      } catch (_) {}

      _routingLoading = false;
      _routingError = 'Offline';
      notifyListeners();
      return;
    }

    try {
      final sw = Stopwatch()..start();
      final variants = await _routingEngine.computeVariants(
        start: start,
        end: end,
        departureTime: _forecastBaseUtc(),
        speedMetersPerSecond: 4.2,
        sampleEveryMeters: _lowPowerMode ? 900 : 450,
        maxSamples: _lowPowerMode ? 60 : 120,
      );
      sw.stop();

      _routeVariants = variants;
      if (_routeVariants.isNotEmpty) {
        _selectedVariant = _routeVariants.first.kind;
      }
      _routeExplanations = _buildRouteExplanations(_routeVariants);
      _routeExplanation = currentRouteExplanation?.headline;
      _routingLoading = false;
      notifyListeners();

      _metrics.recordDuration('routing_compute_ms', sw.elapsedMilliseconds);
      _metrics.inc('routing_compute');
      unawaited(_metrics.flush());
      unawaited(_analytics.record('route_computed', props: {'variants': variants.length}));

      await _saveRouteCache(start, end, variants);
      await _afterVariantsUpdated();
    } catch (e, st) {
      AppLog.e('routing.computeRouteVariants failed', error: e, stackTrace: st);
      final cached = await _loadRouteCache(start, end);
      if (cached != null) {
        _routeVariants = cached;
        _routingError = 'Mode conservateur (offline)';
        _routeExplanation = null;
        _routeExplanations = const {};
        _routingLoading = false;
        notifyListeners();
        await _renderSelectedRoute();
        return;
      }

      _routingLoading = false;
      _routingError = e.toString();
      notifyListeners();

      _metrics.inc('routing_error');
      unawaited(_metrics.flush());
    }
  }

  Future<void> _afterVariantsUpdated() async {
    unawaited(_renderRouteMarkers());
    await _renderSelectedRoute();
    unawaited(_evaluateAndNotifyContextual());
  }

  Future<void> importGpxRoute() async {
    if (_gpxImportLoading) return;
    _gpxImportLoading = true;
    _gpxImportError = null;
    notifyListeners();

    try {
      final res = await _gpxImport.pickAndParse();
      if (res == null) {
        _gpxImportLoading = false;
        notifyListeners();
        return;
      }

      final shape = res.points;
      if (shape.length < 2) {
        _gpxImportLoading = false;
        _gpxImportError = 'Trace GPX invalide.';
        notifyListeners();
        return;
      }

      final lenMeters = polylineLengthMeters(shape);
      final weatherSamples = await _routeWeatherProjector.projectAlongPolyline(
        polyline: shape,
        departureTime: _forecastBaseUtc(),
        speedMetersPerSecond: 4.2,
        sampleEveryMeters: _lowPowerMode ? 900 : 450,
        maxSamples: _lowPowerMode ? 60 : 120,
      );

      _routeStart = shape.first;
      _routeEnd = shape.last;
      _routeVariants = [
        RouteVariant(
          kind: RouteVariantKind.imported,
          shape: shape,
          lengthKm: lenMeters / 1000.0,
          timeSeconds: (lenMeters / 4.2),
          weatherSamples: weatherSamples,
        ),
      ];
      _selectedVariant = RouteVariantKind.imported;
      _routeExplanations = _buildRouteExplanations(_routeVariants);
      _routeExplanation = currentRouteExplanation?.headline;
      _gpxRouteName = res.fileName;

      _gpxImportLoading = false;
      notifyListeners();

      unawaited(_renderRouteMarkers());
      await _renderSelectedRoute();
      unawaited(_evaluateAndNotifyContextual());
    } catch (e, st) {
      AppLog.e('routing.importGpxRoute failed', error: e, stackTrace: st);
      _gpxImportLoading = false;
      _gpxImportError = e.toString();
      notifyListeners();
    }
  }

  Future<List<RouteDepartureComparison>> compareDeparturesForSelectedVariant() async {
    final v = _currentVariant();
    if (v == null) return const [];

    final cache = _departureCompareCache;
    final now = DateTime.now();
    if (cache != null && cache.kind == v.kind && now.difference(cache.at) < const Duration(seconds: 25)) {
      return cache.items;
    }

    return _routeCompare.compareDepartures(
      variant: v,
      baseDepartureUtc: _forecastBaseUtc(),
      speedMetersPerSecond: 4.2,
      offsets: const [
        Duration.zero,
        Duration(minutes: 30),
        Duration(minutes: 60),
      ],
      sampleEveryMeters: _lowPowerMode ? 900 : 450,
      maxSamples: _lowPowerMode ? 60 : 120,
    ).then((items) {
      _departureCompareCache = _DepartureCompareCacheEntry(kind: v.kind, at: DateTime.now(), items: items);
      return items;
    });
  }

  Future<DepartureWindowRecommendation?> recommendDepartureWindowForSelectedVariant() async {
    final v = _currentVariant();
    if (v == null) return null;

    final cache = _departureWindowCache;
    final now = DateTime.now();
    if (cache != null && cache.kind == v.kind && now.difference(cache.at) < const Duration(seconds: 45)) {
      return cache.item;
    }

    final rec = await _routeCompare.recommendDepartureWindow(
      variant: v,
      baseDepartureUtc: _forecastBaseUtc(),
      speedMetersPerSecond: 4.2,
      horizon: const Duration(hours: 6),
      step: const Duration(minutes: 20),
      sampleEveryMeters: _lowPowerMode ? 900 : 450,
      maxSamples: _lowPowerMode ? 60 : 120,
    );
    _departureWindowCache = _DepartureWindowCacheEntry(kind: v.kind, at: DateTime.now(), item: rec);
    return rec;
  }

  void clearSelectedRouteWeatherSample() {
    if (_selectedRouteWeatherSample == null) return;
    _selectedRouteWeatherSample = null;
    notifyListeners();
  }

  void onMapTap(LatLng tap) {
    final v = _currentVariant();
    if (v == null || v.weatherSamples.isEmpty) {
      clearSelectedRouteWeatherSample();
      return;
    }

    // Find closest sample.
    RouteWeatherSample? best;
    var bestDist = double.infinity;
    for (final s in v.weatherSamples) {
      final dLat = tap.latitude - s.location.latitude;
      final dLng = tap.longitude - s.location.longitude;
      final d = sqrt(dLat * dLat + dLng * dLng);
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }

    _selectedRouteWeatherSample = best;
    notifyListeners();
  }

  Map<RouteVariantKind, RouteExplanation> _buildRouteExplanations(List<RouteVariant> variants) {
    final metrics = <RouteVariantKind, RouteVariantMetrics>{};
    for (final v in variants) {
      metrics[v.kind] = _explainability.metricsFor(v);
    }
    final out = <RouteVariantKind, RouteExplanation>{};
    for (final v in variants) {
      out[v.kind] = _explainability.explain(v: v, allMetrics: metrics);
    }
    return out;
  }

  Future<void> _evaluateAndNotifyContextual() async {
    if (!_notificationsEnabledForContextual) return;
    if (kIsWeb) return;

    // Respect Module 7: no heavy work in background.
    if (!_appInForeground) return;

    final v = _currentVariant();
    if (v == null || v.weatherSamples.isEmpty) return;

    final now = DateTime.now();
    final last = _lastNotificationAt;
    if (last != null && now.difference(last) < const Duration(minutes: 30)) return;

    // Find first reasonably confident rain risk in the next 45 minutes.
    final horizon = now.toUtc().add(const Duration(minutes: 45));
    for (final s in v.weatherSamples) {
      if (s.eta.isAfter(horizon)) break;
      if (s.confidence < 0.5) continue;
      if (s.snapshot.precipitation < 2.0) continue;

      final etaLocal = s.eta.toLocal();
      final hh = etaLocal.hour.toString().padLeft(2, '0');
      final mm = etaLocal.minute.toString().padLeft(2, '0');
      await _notifications.show(
        title: 'Alerte météo sur ton trajet',
        body: 'Pluie probable vers $hh:$mm (estimé).',
      );
      _lastNotificationAt = DateTime.now();
      break;
    }
  }

  Future<void> _renderRouteMarkers() async {
    final controller = _mapController;
    if (controller == null) return;
    if (!_styleLoaded) return;

    await _ensureRouteLayers();

    final start = _routeStart;
    final end = _routeEnd;

    final features = <Map<String, Object?>>[];
    if (start != null) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'start'},
        'geometry': {
          'type': 'Point',
          'coordinates': [start.longitude, start.latitude],
        },
      });
    }
    if (end != null) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'end'},
        'geometry': {
          'type': 'Point',
          'coordinates': [end.longitude, end.latitude],
        },
      });
    }

    try {
      await controller.setGeoJsonSource('route-markers', {
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (_) {}
  }

  Future<void> _renderSelectedRoute() async {
    final controller = _mapController;
    if (controller == null) return;
    if (!_styleLoaded) return;

    await _ensureRouteLayers();

    final v = _currentVariant();
    if (v == null) return;

    try {
      await controller.setGeoJsonSource('route-source', {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {},
            'geometry': {
              'type': 'LineString',
              'coordinates': v.shape.map((p) => [p.longitude, p.latitude]).toList(),
            },
          },
        ],
      });
    } catch (_) {}

    try {
      final geo = _routeWeatherProjector.buildSegments(v);
      await controller.setGeoJsonSource('route-weather-segments', geo);

      final points = v.weatherSamples
          .map((s) => {
                'type': 'Feature',
                'properties': {
                  'comfort': s.comfortScore,
                  'confidence': s.confidence,
                  'windKind': s.relativeWindKind.name,
                  'windImpact': s.relativeWindImpact,
                },
                'geometry': {
                  'type': 'Point',
                  'coordinates': [s.location.longitude, s.location.latitude],
                }
              })
          .toList();
      await controller.setGeoJsonSource('route-weather', {
        'type': 'FeatureCollection',
        'features': points,
      });
    } catch (_) {}
  }

  Future<void> _clearRouteLayers() async {
    final controller = _mapController;
    if (controller == null) return;
    await _ensureRouteLayers();
    try {
      await controller.setGeoJsonSource('route-source', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-markers', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-weather-segments', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-weather', _emptyFeatureCollection());
    } catch (_) {}
  }

  Map<String, dynamic> _emptyFeatureCollection() => const {
        'type': 'FeatureCollection',
        'features': [],
      };

  String _routeCacheKey(LatLng start, LatLng end) {
    double round(double v) => (v * 200).roundToDouble() / 200;
    return 'v1_${round(start.latitude)}_${round(start.longitude)}__${round(end.latitude)}_${round(end.longitude)}';
  }

  Future<List<RouteVariant>?> _loadRouteCache(LatLng start, LatLng end) async {
    final key = _routeCacheKey(start, end);
    final entry = await _routeCache.read(key);
    if (entry == null) return null;
    final variantsRaw = entry.payload['variants'];
    if (variantsRaw is! List) return null;

    final out = <RouteVariant>[];
    for (final raw in variantsRaw) {
      if (raw is! Map) continue;
      final kindRaw = raw['kind'];
      final lengthRaw = raw['lengthKm'];
      final timeRaw = raw['timeSeconds'];
      final shapeRaw = raw['shape'];

      if (kindRaw is! String || lengthRaw is! num || timeRaw is! num || shapeRaw is! List) continue;
      RouteVariantKind? kind;
      for (final k in RouteVariantKind.values) {
        if (k.name == kindRaw) {
          kind = k;
          break;
        }
      }
      if (kind == null) continue;

      final shape = <LatLng>[];
      for (final p in shapeRaw) {
        if (p is! List || p.length != 2) continue;
        final lon = p[0];
        final lat = p[1];
        if (lon is! num || lat is! num) continue;
        shape.add(LatLng(lat.toDouble(), lon.toDouble()));
      }
      if (shape.length < 2) continue;

      out.add(RouteVariant(
        kind: kind,
        shape: shape,
        lengthKm: lengthRaw.toDouble(),
        timeSeconds: timeRaw.toDouble(),
        weatherSamples: const [],
      ));
    }

    if (out.isEmpty) return null;
    return out;
  }

  Future<void> _saveRouteCache(LatLng start, LatLng end, List<RouteVariant> variants) async {
    final key = _routeCacheKey(start, end);
    final payload = {
      'variants': variants
          .map((v) => {
                'kind': v.kind.name,
                'lengthKm': v.lengthKm,
                'timeSeconds': v.timeSeconds,
                'shape': v.shape.map((p) => [p.longitude, p.latitude]).toList(),
              })
          .toList(),
    };
    await _routeCache.write(key, payload);
  }

  Future<void> _ensureRouteLayers() async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.addSource('route-source', GeojsonSourceProperties(data: _emptyFeatureCollection()));
    } catch (_) {}
    try {
      await controller.addLineLayer(
        'route-source',
        'route-line',
        const LineLayerProperties(
          lineColor: '#4A90A0',
          lineWidth: 5.0,
          lineOpacity: 0.85,
          lineJoin: 'round',
          lineCap: 'round',
        ),
      );
    } catch (_) {}

    try {
      await controller.addSource('route-weather-segments', GeojsonSourceProperties(data: _emptyFeatureCollection()));
    } catch (_) {}
    try {
      await controller.addLineLayer(
        'route-weather-segments',
        'route-weather-segments-layer',
        const LineLayerProperties(
          lineWidth: 8.0,
          lineJoin: 'round',
          lineCap: 'round',
          lineColor: [
            'match',
            ['get', 'windKind'],
            'tail',
            '#88D3A2',
            'cross',
            '#FFC56E',
            'head',
            '#B55A5A',
            '#4A90A0',
          ],
          lineOpacity: [
            'interpolate',
            ['linear'],
            ['get', 'confidence'],
            0.25,
            0.25,
            0.95,
            0.92,
          ],
        ),
      );
    } catch (_) {}

    try {
      await controller.addSource('route-markers', GeojsonSourceProperties(data: _emptyFeatureCollection()));
    } catch (_) {}
    try {
      await controller.addCircleLayer(
        'route-markers',
        'route-markers-layer',
        const CircleLayerProperties(
          circleRadius: 7.5,
          circleColor: [
            'case',
            ['==', ['get', 'kind'], 'start'],
            '#88D3A2',
            '#B55A5A',
          ],
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2.0,
        ),
      );
    } catch (_) {}

    try {
      await controller.addSource('route-weather', GeojsonSourceProperties(data: _emptyFeatureCollection()));
    } catch (_) {}
    try {
      await controller.addCircleLayer(
        'route-weather',
        'route-weather-layer',
        const CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            3.0,
            14,
            6.0,
          ],
          circleColor: [
            'interpolate',
            ['linear'],
            ['get', 'comfort'],
            1,
            '#B55A5A',
            5,
            '#FFC56E',
            10,
            '#88D3A2',
          ],
          circleOpacity: [
            'interpolate',
            ['linear'],
            ['get', 'confidence'],
            0.25,
            0.25,
            0.95,
            0.9,
          ],
          circleBlur: 0.15,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 1.2,
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _routeDebounce?.cancel();
    super.dispose();
  }
}

class _DepartureCompareCacheEntry {
  final RouteVariantKind kind;
  final DateTime at;
  final List<RouteDepartureComparison> items;

  const _DepartureCompareCacheEntry({
    required this.kind,
    required this.at,
    required this.items,
  });
}

class _DepartureWindowCacheEntry {
  final RouteVariantKind kind;
  final DateTime at;
  final DepartureWindowRecommendation item;

  const _DepartureWindowCacheEntry({
    required this.kind,
    required this.at,
    required this.item,
  });
}
