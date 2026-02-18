import 'dart:async';
import 'dart:math';

import 'package:horizon/core/constants/cycling_constants.dart';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:horizon/core/log/app_log.dart';
import 'package:horizon/services/analytics_service.dart';
import 'package:horizon/services/explainability_engine.dart';
import 'package:horizon/services/gpx_import_service.dart';
import 'package:horizon/services/horizon_scheduler.dart';
import 'package:horizon/services/perf_metrics.dart';
import 'package:horizon/services/route_cache.dart';
import 'package:horizon/services/route_compare_service.dart';
import 'package:horizon/services/route_weather_projector.dart';
import 'package:horizon/services/routing_engine.dart';
import 'package:horizon/services/notification_service.dart';
import 'package:horizon/services/routing_map_renderer.dart';
import 'package:horizon/core/format/confidence_label.dart';

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
  final RoutingMapRenderer _mapRenderer;

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
    RoutingMapRenderer mapRenderer = const RoutingMapRenderer(),
  })  : _routingEngine = routingEngine,
        _routeCache = routeCache,
        _scheduler = scheduler,
        _metrics = metrics,
        _analytics = analytics,
        _routeCompare = routeCompare,
        _gpxImport = gpxImport,
        _routeWeatherProjector = routeWeatherProjector,
        _explainability = explainability,
        _notifications = notifications,
        _mapRenderer = mapRenderer;

  void setController(MaplibreMapController controller) {
    _mapController = controller;
    if (_styleLoaded) {
      unawaited(_mapRenderer.initLayers(controller).then((_) {
        _renderRouteMarkers();
        _renderSelectedRoute();
      }));
    }
  }

  void setStyleLoaded(bool loaded) {
    _styleLoaded = loaded;
    if (loaded && _mapController != null) {
      unawaited(_mapRenderer.initLayers(_mapController!).then((_) {
        _renderRouteMarkers();
        _renderSelectedRoute();
      }));
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
    return confidenceLabelFr(confidence);
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
    _departureCompareCache = null;
    _departureWindowCache = null;
    notifyListeners();
    _renderRouteMarkers();
    _routeDebounce?.cancel();
    _routeDebounce = Timer(CyclingConstants.routePointDebounce, () {
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
    _selectedVariant = RouteVariantKind.fast;
    _departureCompareCache = null;
    _departureWindowCache = null;
    notifyListeners();
    _mapRenderer.clearMarkers(_mapController);
    _mapRenderer.clear(_mapController);
  }

  void selectRouteVariant(RouteVariantKind kind) {
    if (_selectedVariant == kind) return;
    _selectedVariant = kind;
    _selectedRouteWeatherSample = null;
    _routeExplanation = currentRouteExplanation?.headline;
    notifyListeners();
    _renderSelectedRoute();
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

    final now = DateTime.now();
    final last = _lastRouteComputeAt;
    if (last != null && now.difference(last) < CyclingConstants.routeComputeThrottle) {
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
      } catch (e, st) {
        assert(() {
          AppLog.w('routing.offline cache load failed', error: e, stackTrace: st);
          return true;
        }());
      }

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
        speedMetersPerSecond: CyclingConstants.defaultSpeedMps,
        sampleEveryMeters: _lowPowerMode ? CyclingConstants.sampleIntervalMetersLowPower : CyclingConstants.sampleIntervalMeters,
        maxSamples: _lowPowerMode ? CyclingConstants.maxSamplesLowPower : CyclingConstants.maxSamples,
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
    _renderRouteMarkers();
    await _renderSelectedRoute();
    unawaited(_evaluateAndNotifyContextual());
  }

  Future<void> importGpxRoute() async {
    if (_gpxImportLoading) return;
    _gpxImportLoading = true;
    _gpxImportError = null;
    notifyListeners();

    try {
      final resObj = await _gpxImport.pickAndParse();
      if (resObj.isFailure) {
        _gpxImportLoading = false;
        _gpxImportError = resObj.errorOrNull.toString();
        notifyListeners();
        return;
      }
      final res = resObj.valueOrNull;
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
        speedMetersPerSecond: CyclingConstants.defaultSpeedMps,
        sampleEveryMeters: _lowPowerMode ? CyclingConstants.sampleIntervalMetersLowPower : CyclingConstants.sampleIntervalMeters,
        maxSamples: _lowPowerMode ? CyclingConstants.maxSamplesLowPower : CyclingConstants.maxSamples,
      );

      _routeStart = shape.first;
      _routeEnd = shape.last;
      final v = RouteVariant(
        kind: RouteVariantKind.imported,
        shape: shape,
        lengthKm: lenMeters / 1000.0,
        timeSeconds: (lenMeters / CyclingConstants.defaultSpeedMps),
        weatherSamples: weatherSamples,
      );
      final explanation = _explainability.explain(v: v, allMetrics: {v.kind: _explainability.metricsFor(v)});
      _routeVariants = [v];
      _selectedVariant = RouteVariantKind.imported;
      _routeExplanation = null;
      _routeExplanations = {RouteVariantKind.imported: explanation};
      _gpxRouteName = res.fileName;
      _departureCompareCache = null;
      _departureWindowCache = null;

      _gpxImportLoading = false;
      notifyListeners();

      _renderRouteMarkers();
      _renderSelectedRoute();
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
    if (cache != null && cache.kind == v.kind && now.difference(cache.at) < CyclingConstants.departureCompareCacheTtl) {
      return cache.items;
    }

    return _routeCompare.compareDepartures(
      variant: v,
      baseDepartureUtc: _forecastBaseUtc(),
      speedMetersPerSecond: CyclingConstants.defaultSpeedMps,
      offsets: CyclingConstants.departureCompareOffsets,
      sampleEveryMeters: _lowPowerMode ? CyclingConstants.sampleIntervalMetersLowPower : CyclingConstants.sampleIntervalMeters,
      maxSamples: _lowPowerMode ? CyclingConstants.maxSamplesLowPower : CyclingConstants.maxSamples,
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
    if (cache != null && cache.kind == v.kind && now.difference(cache.at) < CyclingConstants.departureWindowCacheTtl) {
      return cache.item;
    }

    final rec = await _routeCompare.recommendDepartureWindow(
      variant: v,
      baseDepartureUtc: _forecastBaseUtc(),
      speedMetersPerSecond: CyclingConstants.defaultSpeedMps,
      horizon: CyclingConstants.departureWindowHorizon,
      step: CyclingConstants.departureWindowStep,
      sampleEveryMeters: _lowPowerMode ? CyclingConstants.sampleIntervalMetersLowPower : CyclingConstants.sampleIntervalMeters,
      maxSamples: _lowPowerMode ? CyclingConstants.maxSamplesLowPower : CyclingConstants.maxSamples,
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
    if (last != null && now.difference(last) < CyclingConstants.notificationCooldown) return;

    // Find first reasonably confident rain risk in the next 45 minutes.
    final horizon = now.toUtc().add(CyclingConstants.weatherAlertHorizon);
    for (final s in v.weatherSamples) {
      if (s.eta.isAfter(horizon)) break;
      if (s.confidence < CyclingConstants.rainAlertMinConfidence) continue;
      if (s.snapshot.precipitation < CyclingConstants.rainAlertThresholdMm) continue;

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
    await _mapRenderer.render(
      controller: _mapController,
      styleLoaded: _styleLoaded,
      start: _routeStart,
      end: _routeEnd,
      selectedVariant: _currentVariant(),
      weatherSegmentsGeoJson: null, // Markers only update
    );
  }

  Future<void> _renderSelectedRoute() async {
    final v = _currentVariant();
    if (v == null) return;
    final geo = _routeWeatherProjector.buildSegments(v);
    await _mapRenderer.render(
      controller: _mapController,
      styleLoaded: _styleLoaded,
      start: _routeStart,
      end: _routeEnd,
      selectedVariant: v,
      weatherSegmentsGeoJson: geo,
    );
  }

  String _routeCacheKey(LatLng start, LatLng end) {
    double round(double v) => (v * CyclingConstants.routeCacheGridFactor).roundToDouble() / CyclingConstants.routeCacheGridFactor;
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
