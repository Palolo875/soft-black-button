import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:app/services/weather_service.dart';
import 'package:app/services/offline_service.dart';
import 'package:app/services/weather_engine_sota.dart';
import 'package:app/services/weather_models.dart';
import 'package:app/services/routing_engine.dart';
import 'package:app/services/routing_models.dart';
import 'package:app/services/route_cache.dart';
import 'package:app/services/offline_registry.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app/services/explainability_engine.dart';
import 'package:app/services/privacy_service.dart';

class MapProvider with ChangeNotifier {
  MaplibreMapController? _mapController;
  bool _isStyleLoaded = false;
  final WeatherService _weatherService = WeatherService();
  final WeatherEngineSota _weatherEngine = WeatherEngineSota();
  final RoutingEngine _routingEngine = RoutingEngine();
  final RouteCache _routeCache = RouteCache(encrypted: true);
  final OfflineService _offlineService = OfflineService();
  final PrivacyService _privacyService = const PrivacyService();
  final ExplainabilityEngine _explainability = const ExplainabilityEngine();
  double _timeOffset = 0.0;

  Timer? _weatherRefreshTimer;
  LatLng? _lastWeatherPosition;

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

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool? _isOnline;

  WeatherDecision? _weatherDecision;
  bool _weatherLoading = false;
  String? _weatherError;

  double? _offlineDownloadProgress;
  String? _offlineDownloadError;

  bool _pmtilesEnabled = false;
  double? _pmtilesProgress;
  String? _pmtilesError;
  String _pmtilesFileName = 'horizon.pmtiles';

  MaplibreMapController? get mapController => _mapController;
  bool get isStyleLoaded => _isStyleLoaded;
  WeatherDecision? get weatherDecision => _weatherDecision;
  bool get weatherLoading => _weatherLoading;
  String? get weatherError => _weatherError;
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
  double? get offlineDownloadProgress => _offlineDownloadProgress;
  String? get offlineDownloadError => _offlineDownloadError;
  bool get pmtilesEnabled => _pmtilesEnabled;
  double? get pmtilesProgress => _pmtilesProgress;
  String? get pmtilesError => _pmtilesError;
  String get pmtilesFileName => _pmtilesFileName;
  bool? get isOnline => _isOnline;

  Future<void> refreshWeatherAt(LatLng position) async {
    _lastWeatherPosition = position;
    _weatherLoading = true;
    _weatherError = null;
    notifyListeners();

    try {
      final decision = await _weatherEngine.getDecisionForPoint(position);
      _weatherDecision = decision;
      _weatherLoading = false;
      notifyListeners();
    } catch (e) {
      _weatherLoading = false;
      _weatherError = e.toString();
      notifyListeners();
    }

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
    _startConnectivityMonitor();
  }

  double get timeOffset => _timeOffset;

  void setTimeOffset(double value) {
    _timeOffset = value;
    _weatherService.updateTimeOffset(value);
    notifyListeners();
  }

  void setStyleLoaded(bool loaded) {
    _isStyleLoaded = loaded;
    notifyListeners();
    if (loaded) {
      _weatherService.initWeather(controller: _mapController!);
      _startWeatherAutoRefresh();
      _startConnectivityMonitor();
    }
  }

  void _startConnectivityMonitor() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      final has = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      final next = has ? true : false;
      if (_isOnline == next) return;
      _isOnline = next;
      notifyListeners();
    });
    unawaited(() async {
      final results = await Connectivity().checkConnectivity();
      final has = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      final next = has ? true : false;
      if (_isOnline == next) return;
      _isOnline = next;
      notifyListeners();
    }());
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
      unawaited(computeRouteVariants());
    });
  }

  Future<void> computeRouteVariants() async {
    final controller = _mapController;
    final start = _routeStart;
    final end = _routeEnd;
    if (controller == null || start == null || end == null) return;
    if (!_isStyleLoaded) return;

    final now = DateTime.now();
    final last = _lastRouteComputeAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastRouteComputeAt = now;

    _routingLoading = true;
    _routingError = null;
    notifyListeners();

    try {
      final variants = await _routingEngine.computeVariants(
        start: start,
        end: end,
        departureTime: DateTime.now().toUtc(),
        speedMetersPerSecond: 4.2,
      );
      _routeVariants = variants;
      _selectedVariant = _selectedVariant;
      _routeExplanations = _buildRouteExplanations(variants);
      _routeExplanation = currentRouteExplanation?.headline ?? _buildExplanationFor(_currentVariant());
      _routingLoading = false;
      notifyListeners();

      unawaited(_saveRouteCache(start, end, variants));

      await _renderSelectedRoute();
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
    notifyListeners();
    await _clearRouteLayers();
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
          lineOpacity: [
            'interpolate',
            ['linear'],
            ['get', 'confidence'],
            0.25,
            0.25,
            0.95,
            0.85,
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
  }

  Future<void> _clearRouteLayers() async {
    final controller = _mapController;
    if (controller == null) return;
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

  void _startWeatherAutoRefresh() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      final pos = _lastWeatherPosition;
      if (pos == null) return;
      unawaited(refreshWeatherAt(pos));
    });
  }

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
    final controller = _mapController;
    if (controller == null) return;

    _offlineDownloadError = null;
    _offlineDownloadProgress = 0.0;
    notifyListeners();

    try {
      final bounds = await controller.getVisibleRegion();
      _offlineService
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
        } else if (event is Error) {
          _offlineDownloadError = event.cause.message ?? event.cause.code;
          _offlineDownloadProgress = null;
        }
        notifyListeners();
      });
    } catch (e) {
      _offlineDownloadError = e.toString();
      _offlineDownloadProgress = null;
      notifyListeners();
    }
  }

  Future<List<OfflineRegion>> listOfflineRegions() {
    return _offlineService.listRegions();
  }

  Future<void> deleteOfflineRegionById(int id) {
    return _offlineService.deleteRegion(id);
  }

  @override
  void dispose() {
    _weatherService.dispose();
    _weatherRefreshTimer?.cancel();
    _routeDebounce?.cancel();
    unawaited(_connectivitySub?.cancel());
    unawaited(_offlineService.stopPmtilesServer());
    super.dispose();
  }

  void centerOnUser(LatLng position) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 14.0),
    );
    unawaited(refreshWeatherAt(position));
  }
}
