import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:app/services/offline_service.dart';
import 'package:app/services/routing_engine.dart';
import 'package:app/services/routing_models.dart';
import 'package:app/services/route_cache.dart';
import 'package:app/services/offline_registry.dart';
import 'package:app/services/explainability_engine.dart';
import 'package:app/services/privacy_service.dart';
import 'package:app/services/analytics_service.dart';
import 'package:app/services/horizon_scheduler.dart';
import 'package:app/services/perf_metrics.dart';
import 'package:app/services/route_compare_service.dart';
import 'package:app/services/gpx_import_service.dart';
import 'package:app/services/route_geometry.dart';
import 'package:app/services/route_weather_projector.dart';
import 'package:app/services/notification_service.dart';

class MapProvider with ChangeNotifier {
  MaplibreMapController? _mapController;
  LatLng? _webCenter;
  bool _isStyleLoaded = false;
  final RoutingEngine _routingEngine;
  final RouteCache _routeCache;
  final OfflineService _offlineService;
  final PrivacyService _privacyService;
  final AnalyticsService _analytics;
  final HorizonScheduler _scheduler;
  final PerfMetrics _metrics;
  final RouteCompareService _routeCompare;
  final GpxImportService _gpxImport;
  final RouteWeatherProjector _routeWeatherProjector;
  final NotificationService _notifications;
  final ExplainabilityEngine _explainability;

  MapProvider({
    RoutingEngine? routingEngine,
    RouteCache? routeCache,
    OfflineService? offlineService,
    PrivacyService? privacyService,
    AnalyticsService? analytics,
    HorizonScheduler? scheduler,
    PerfMetrics? metrics,
    RouteCompareService? routeCompare,
    GpxImportService? gpxImport,
    RouteWeatherProjector? routeWeatherProjector,
    NotificationService? notifications,
    ExplainabilityEngine? explainability,
  })  : _routingEngine = routingEngine ?? RoutingEngine(),
        _routeCache = routeCache ?? RouteCache(encrypted: true),
        _offlineService = offlineService ?? OfflineService(),
        _privacyService = privacyService ?? const PrivacyService(),
        _analytics = analytics ?? AnalyticsService(),
        _scheduler = scheduler ?? HorizonScheduler(),
        _metrics = metrics ?? PerfMetrics(),
        _routeCompare = routeCompare ?? RouteCompareService(),
        _gpxImport = gpxImport ?? GpxImportService(),
        _routeWeatherProjector = routeWeatherProjector ?? RouteWeatherProjector(),
        _notifications = notifications ?? NotificationService(),
        _explainability = explainability ?? const ExplainabilityEngine();
  double _timeOffset = 0.0;

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
  bool? _isOnline;

  bool _lowPowerMode = false;
  bool _appInForeground = true;

  double? _offlineDownloadProgress;
  String? _offlineDownloadError;

  bool _pmtilesEnabled = false;
  double? _pmtilesProgress;
  String? _pmtilesError;
  String _pmtilesFileName = 'horizon.pmtiles';

  MaplibreMapController? get mapController => _mapController;
  LatLng? get webCenter => _webCenter;
  bool get isStyleLoaded => _isStyleLoaded;
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
  double? get offlineDownloadProgress => _offlineDownloadProgress;
  String? get offlineDownloadError => _offlineDownloadError;
  bool get pmtilesEnabled => _pmtilesEnabled;
  double? get pmtilesProgress => _pmtilesProgress;
  String? get pmtilesError => _pmtilesError;
  String get pmtilesFileName => _pmtilesFileName;
  bool? get isOnline => _isOnline;
  bool get lowPowerMode => _lowPowerMode;

  String confidenceLabel(double confidence) {
    if (confidence >= 0.75) return 'Fiable';
    if (confidence >= 0.50) return 'Variable';
    return 'Incertain';
  }

  void syncIsOnlineFromConnectivity(bool? isOnline) {
    if (_isOnline == isOnline) return;
    _isOnline = isOnline;
    notifyListeners();
  }

  String? get selectedSampleReliabilityLabel {
    final c = _selectedRouteWeatherSample?.confidence;
    if (c == null) return null;
    return confidenceLabel(c);
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

  Future<String> exportPerfMetricsJson() {
    return _metrics.exportJson();
  }

  Future<String?> exportAnalyticsBufferJson() {
    return _analytics.exportBufferJson();
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

  void setLowPowerMode(bool enabled) {
    _lowPowerMode = enabled;
    notifyListeners();
  }

  void syncNotificationsEnabledFromSettings(bool enabled) {
    _notificationsEnabledForContextual = enabled;
    if (enabled) {
      unawaited(_evaluateAndNotifyContextual());
    }
  }

  void setAppInForeground(bool fg) {
    _appInForeground = fg;
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

  Future<List<OfflinePack>> listOfflinePacks() {
    return _offlineService.listOfflinePacks();
  }

  Future<void> uninstallOfflinePackById(String id) {
    return _offlineService.uninstallPackById(id);
  }

  Future<LocalDataReport> computeLocalDataReport() {
    return _privacyService.computeReport();
  }

  _DepartureCompareCacheEntry? _departureCompareCache;
  _DepartureWindowCacheEntry? _departureWindowCache;

  Future<void> panicWipeAllLocalData() async {
    await clearRoute();
    await _privacyService.panicWipeAllLocalData();
  }

  Future<void> uninstallCurrentPmtilesPack() async {
    if (kIsWeb) return;
    _pmtilesError = null;
    _pmtilesProgress = 0.0;
    notifyListeners();
    try {
      if (_pmtilesEnabled) {
        await disablePmtilesPack();
      }
      await _offlineService.uninstallPmtilesPack(fileName: _pmtilesFileName);
      _pmtilesProgress = null;
      notifyListeners();
    } catch (e) {
      _pmtilesError = e.toString();
      _pmtilesProgress = null;
      notifyListeners();
    }
  }

  void clearOfflineDownloadState() {
    _offlineDownloadProgress = null;
    _offlineDownloadError = null;
    notifyListeners();
  }

  void clearPmtilesState() {
    _pmtilesProgress = null;
    _pmtilesError = null;
    notifyListeners();
  }

  void setController(MaplibreMapController controller) {
    _mapController = controller;
    notifyListeners();
  }

  double get timeOffset => _timeOffset;

  DateTime _forecastBaseUtc() {
    final minutes = (_timeOffset * 60).round();
    return DateTime.now().toUtc().add(Duration(minutes: minutes));
  }

  void setTimeOffset(double value) {
    _timeOffset = value;
    notifyListeners();
  }

  void setStyleLoaded(bool loaded) {
    _isStyleLoaded = loaded;
    notifyListeners();
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

  Future<void> computeRouteVariants() async {
    final start = _routeStart;
    final end = _routeEnd;
    if (start == null || end == null) return;
    if (!_isStyleLoaded) return;

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
      if (!_routeVariants.any((v) => v.kind == _selectedVariant)) {
        _selectedVariant = _routeVariants.first.kind;
      }
      _routeExplanations = _buildRouteExplanations(variants);
      _routeExplanation = currentRouteExplanation?.headline ?? _buildExplanationFor(_currentVariant());
      _routingLoading = false;
      notifyListeners();

      _metrics.recordDuration('routing_compute_ms', sw.elapsedMilliseconds);
      _metrics.inc('routing_compute');
      unawaited(_metrics.flush());
      unawaited(_analytics.record('route_computed', props: {'variants': variants.length}));

      unawaited(_saveRouteCache(start, end, variants));

      await _renderSelectedRoute();
      unawaited(_evaluateAndNotifyContextual());
    } catch (e) {
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

  String _routeCacheKey(LatLng start, LatLng end) {
    double round(double v) => (v * 200).roundToDouble() / 200;
    return 'v1_${round(start.latitude)}_${round(start.longitude)}__${round(end.latitude)}_${round(end.longitude)}';
  }

  Future<void> _saveRouteCache(LatLng start, LatLng end, List<RouteVariant> variants) async {
    final key = _routeCacheKey(start, end);
    final payload = {
      'variants': variants
          .map((v) => {
                'kind': v.kind.name,
                'lengthKm': v.lengthKm,
                'timeSeconds': v.timeSeconds,
                'shape': v.shape.map((p) => [p.latitude, p.longitude]).toList(),
              })
          .toList(),
    };
    await _routeCache.write(key, payload);
  }

  Future<List<RouteVariant>?> _loadRouteCache(LatLng start, LatLng end) async {
    final key = _routeCacheKey(start, end);
    final entry = await _routeCache.read(key);
    if (entry == null) return null;
    final variantsRaw = entry.payload['variants'];
    if (variantsRaw is! List) return null;

    final out = <RouteVariant>[];
    for (final item in variantsRaw) {
      if (item is! Map) continue;
      final kindRaw = item['kind'];
      final shapeRaw = item['shape'];
      final lengthRaw = item['lengthKm'];
      final timeRaw = item['timeSeconds'];
      if (kindRaw is! String || shapeRaw is! List || lengthRaw is! num || timeRaw is! num) continue;

      final kind = RouteVariantKind.values.firstWhere(
        (k) => k.name == kindRaw,
        orElse: () => RouteVariantKind.fast,
      );

      final shape = <LatLng>[];
      for (final c in shapeRaw) {
        if (c is! List || c.length < 2) continue;
        final lat = c[0];
        final lon = c[1];
        if (lat is! num || lon is! num) continue;
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

  void selectRouteVariant(RouteVariantKind kind) {
    _selectedVariant = kind;
    _routeExplanation = currentRouteExplanation?.headline ?? _buildExplanationFor(_currentVariant());
    _selectedRouteWeatherSample = null;
    // _routeExplanations already computed for all variants after routing.
    notifyListeners();
    unawaited(_renderSelectedRoute());
    unawaited(_evaluateAndNotifyContextual());
  }

  Future<void> clearRoute() async {
    _routeStart = null;
    _routeEnd = null;
    _routeVariants = const [];
    _routingLoading = false;
    _routingError = null;
    _routeExplanation = null;
    _routeExplanations = const {};
    _selectedRouteWeatherSample = null;
    _routeDebounce?.cancel();
    _gpxRouteName = null;
    notifyListeners();
    await _clearRouteLayers();
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
    } catch (e) {
      _gpxImportLoading = false;
      _gpxImportError = e.toString();
      notifyListeners();
    }
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

    RouteWeatherSample? best;
    double bestMeters = double.infinity;
    for (final s in v.weatherSamples) {
      final d = _haversineMeters(tap, s.location);
      if (d < bestMeters) {
        bestMeters = d;
        best = s;
      }
    }

    // Simple threshold to avoid accidental selections.
    const thresholdMeters = 110.0;
    if (best == null || bestMeters > thresholdMeters) {
      clearSelectedRouteWeatherSample();
      return;
    }

    _selectedRouteWeatherSample = best;
    notifyListeners();
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * 0.017453292519943295;
    final lat2 = b.latitude * 0.017453292519943295;
    final dLat = (b.latitude - a.latitude) * 0.017453292519943295;
    final dLon = (b.longitude - a.longitude) * 0.017453292519943295;
    final sinDLat = sin(dLat / 2);
    final sinDLon = sin(dLon / 2);
    final x = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLon * sinDLon;
    final c = 2 * atan2(sqrt(x), sqrt(1 - x));
    return r * c;
  }

  String? _buildExplanationFor(RouteVariant? variant) {
    if (variant == null) return null;
    if (variant.weatherSamples.isEmpty) return null;

    int rainCount = 0;
    int windCount = 0;
    int coldHotCount = 0;

    for (final s in variant.weatherSamples) {
      if (s.snapshot.precipitation >= 1.0) rainCount++;
      if (s.snapshot.windSpeed >= 10.0) windCount++;
      final t = s.snapshot.apparentTemperature.isFinite
          ? s.snapshot.apparentTemperature
          : s.snapshot.temperature;
      if (t <= 6.0 || t >= 30.0) coldHotCount++;
    }

    final parts = <String>[];
    if (rainCount > 0) parts.add('pluie');
    if (windCount > 0) parts.add('vent');
    if (coldHotCount > 0) parts.add('température');

    if (parts.isEmpty) return 'Conditions globalement confortables';
    return 'Pénalisée surtout par ${parts.join(', ')}';
  }

  RouteVariant? _currentVariant() {
    for (final v in _routeVariants) {
      if (v.kind == _selectedVariant) return v;
    }
    return _routeVariants.isNotEmpty ? _routeVariants.first : null;
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

  Future<void> _renderRouteMarkers() async {
    final controller = _mapController;
    if (controller == null) return;
    final features = <Map<String, dynamic>>[];
    if (_routeStart != null) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'start'},
        'geometry': {
          'type': 'Point',
          'coordinates': [_routeStart!.longitude, _routeStart!.latitude],
        }
      });
    }
    if (_routeEnd != null) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'end'},
        'geometry': {
          'type': 'Point',
          'coordinates': [_routeEnd!.longitude, _routeEnd!.latitude],
        }
      });
    }
    await controller.setGeoJsonSource('route-markers', {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  Future<void> _renderSelectedRoute() async {
    final controller = _mapController;
    if (controller == null) return;
    final variant = _currentVariant();
    if (variant == null) {
      await controller.setGeoJsonSource('route-source', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-weather-segments', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-weather', _emptyFeatureCollection());
      return;
    }

    final line = {
      'type': 'Feature',
      'properties': {
        'variant': variant.kind.name,
      },
      'geometry': {
        'type': 'LineString',
        'coordinates': variant.shape.map((p) => [p.longitude, p.latitude]).toList(),
      }
    };

    await controller.setGeoJsonSource('route-source', {
      'type': 'FeatureCollection',
      'features': [line],
    });

    final segFeatures = <Map<String, dynamic>>[];
    for (int i = 1; i < variant.weatherSamples.length; i++) {
      final a = variant.weatherSamples[i - 1];
      final b = variant.weatherSamples[i];
      segFeatures.add({
        'type': 'Feature',
        'properties': {
          'comfort': (a.comfortScore + b.comfortScore) / 2.0,
          'confidence': (a.confidence + b.confidence) / 2.0,
          'windKind': a.relativeWindKind.name,
          'windImpact': (a.relativeWindImpact + b.relativeWindImpact) / 2.0,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [a.location.longitude, a.location.latitude],
            [b.location.longitude, b.location.latitude],
          ],
        }
      });
    }
    await controller.setGeoJsonSource('route-weather-segments', {
      'type': 'FeatureCollection',
      'features': segFeatures,
    });

    final points = variant.weatherSamples
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

    await _renderExpertWeatherLayers();
  }

  Future<void> _clearRouteLayers() async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      await controller.setGeoJsonSource('route-source', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-markers', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-weather-segments', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-weather', _emptyFeatureCollection());
      await controller.setGeoJsonSource('expert-weather', _emptyFeatureCollection());
    } catch (_) {}
  }

  Map<String, dynamic> _emptyFeatureCollection() => const {
        'type': 'FeatureCollection',
        'features': [],
      };

  Future<void> enablePmtilesPack({
    required String url,
    String fileName = 'horizon.pmtiles',
    String regionNameForUi = 'Pack offline',
  }) async {
    if (kIsWeb) {
      _pmtilesError = 'PMTiles offline non supporté sur Web.';
      notifyListeners();
      return;
    }

    final controller = _mapController;
    if (controller == null) return;

    _pmtilesError = null;
    _pmtilesProgress = 0.0;
    notifyListeners();

    try {
      _pmtilesProgress = 0.1;
      notifyListeners();

      final pmtilesPath = await _offlineService.downloadPMTiles(url, fileName);
      _pmtilesProgress = 0.5;
      notifyListeners();

      final tilesBaseUri = await _offlineService.startPmtilesServer(pmtilesFilePath: pmtilesPath);
      if (tilesBaseUri == null) {
        throw Exception('Impossible de démarrer le serveur local');
      }
      _pmtilesProgress = 0.7;
      notifyListeners();

      final styleFilePath = await _offlineService.buildStyleFileForPmtiles(tilesBaseUri: tilesBaseUri);
      _pmtilesProgress = 0.9;
      notifyListeners();

      // Switching style will trigger style reload callbacks.
      _isStyleLoaded = false;
      notifyListeners();
      await controller.setStyle(styleFilePath);

      _pmtilesEnabled = true;
      _pmtilesProgress = 1.0;
      notifyListeners();
    } catch (e) {
      _pmtilesError = '$regionNameForUi: ${e.toString()}';
      _pmtilesProgress = null;
      notifyListeners();
    }
  }

  Future<void> disablePmtilesPack() async {
    if (kIsWeb) return;
    final controller = _mapController;
    if (controller == null) return;

    _pmtilesError = null;
    _pmtilesProgress = 0.0;
    notifyListeners();

    try {
      await _offlineService.stopPmtilesServer();
      _isStyleLoaded = false;
      notifyListeners();
      await controller.setStyle('assets/styles/horizon_style.json');
      _pmtilesEnabled = false;
      _pmtilesProgress = null;
      notifyListeners();
    } catch (e) {
      _pmtilesError = e.toString();
      _pmtilesProgress = null;
      notifyListeners();
    }
  }

  Future<void> downloadVisibleRegion({
    String regionName = 'Visible region',
    double minZoom = 10,
    double maxZoom = 14,
  }) async {
    if (kIsWeb) {
      _offlineDownloadError = 'Téléchargement offline non supporté sur Web.';
      _offlineDownloadProgress = null;
      notifyListeners();
      return;
    }

    final controller = _mapController;
    if (controller == null) return;

    _offlineDownloadError = null;
    _offlineDownloadProgress = 0.0;
    notifyListeners();

    try {
      final bounds = await controller.getVisibleRegion();
      await _offlineDownloadSub?.cancel();
      _offlineDownloadSub = _offlineService
          .downloadRegion(
            regionName: regionName,
            bounds: bounds,
            minZoom: minZoom,
            maxZoom: maxZoom,
          )
          .listen((event) {
        if (event is InProgress) {
          _offlineDownloadProgress = event.progress;
        } else if (event is Success) {
          _offlineDownloadProgress = 1.0;
          unawaited(_offlineDownloadSub?.cancel());
          _offlineDownloadSub = null;
        } else if (event is Error) {
          _offlineDownloadError = event.cause.message ?? event.cause.code;
          _offlineDownloadProgress = null;
          unawaited(_offlineDownloadSub?.cancel());
          _offlineDownloadSub = null;
        }
        notifyListeners();
      });
    } catch (e) {
      _offlineDownloadError = e.toString();
      _offlineDownloadProgress = null;
      notifyListeners();
    }
  }

  StreamSubscription<DownloadRegionStatus>? _offlineDownloadSub;

  Future<List<OfflineRegion>> listOfflineRegions() {
    return _offlineService.listRegions();
  }

  Future<void> deleteOfflineRegionById(int id) {
    return _offlineService.deleteRegion(id);
  }

  @override
  void dispose() {
    _routeDebounce?.cancel();
    unawaited(_offlineDownloadSub?.cancel());
    unawaited(_offlineService.stopPmtilesServer());
    super.dispose();
  }

  void centerOnUser(LatLng position) {
    if (kIsWeb) {
      _webCenter = position;
      notifyListeners();
      return;
    }
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 14.0),
    );
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
