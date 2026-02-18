import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:app/services/analytics_service.dart';
import 'package:app/services/horizon_scheduler.dart';
import 'package:app/services/perf_metrics.dart';
import 'package:app/services/weather_engine_sota.dart';
import 'package:app/services/weather_models.dart';
import 'package:app/services/weather_service.dart';

class WeatherProvider with ChangeNotifier {
  final WeatherService _weatherService;
  final WeatherEngineSota _weatherEngine;
  final HorizonScheduler _scheduler;
  final PerfMetrics _metrics;
  final AnalyticsService _analytics;

  MaplibreMapController? _mapController;
  bool _styleLoaded = false;

  double _timeOffset = 0.0;
  bool _lowPowerMode = false;
  bool _appInForeground = true;
  bool? _isOnline;
  bool _navigationActive = false;

  Timer? _weatherRefreshTimer;
  LatLng? _lastWeatherPosition;

  WeatherDecision? _weatherDecision;
  bool _weatherLoading = false;
  String? _weatherError;

  bool _expertWeatherMode = false;
  bool _expertWindLayer = true;
  bool _expertRainLayer = true;
  bool _expertCloudLayer = false;

  WeatherDecision? get weatherDecision => _weatherDecision;
  bool get weatherLoading => _weatherLoading;
  String? get weatherError => _weatherError;

  bool get expertWeatherMode => _expertWeatherMode;
  bool get expertWindLayer => _expertWindLayer;
  bool get expertRainLayer => _expertRainLayer;
  bool get expertCloudLayer => _expertCloudLayer;

  WeatherProvider({
    required WeatherService weatherService,
    required WeatherEngineSota weatherEngine,
    required HorizonScheduler scheduler,
    required PerfMetrics metrics,
    required AnalyticsService analytics,
  })  : _weatherService = weatherService,
        _weatherEngine = weatherEngine,
        _scheduler = scheduler,
        _metrics = metrics,
        _analytics = analytics;

  void setController(MaplibreMapController controller) {
    _mapController = controller;
    if (_styleLoaded) {
      _weatherService.initWeather(controller: controller);
      _startWeatherAutoRefresh();
      unawaited(_ensureExpertWeatherLayers());
    }
  }

  void setStyleLoaded(bool loaded) {
    _styleLoaded = loaded;
    if (loaded && _mapController != null) {
      _weatherService.initWeather(controller: _mapController!);
      _startWeatherAutoRefresh();
      unawaited(_ensureExpertWeatherLayers());
    }
  }

  void syncTimeOffset(double value) {
    _timeOffset = value;
    _weatherService.updateTimeOffset(value);
  }

  void syncLowPowerMode(bool enabled) {
    _lowPowerMode = enabled;
  }

  void syncAppInForeground(bool fg) {
    _appInForeground = fg;
  }

  void syncIsOnline(bool? isOnline) {
    _isOnline = isOnline;
  }

  void syncNavigationActive(bool active) {
    _navigationActive = active;
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

  String? get currentWeatherReliabilityLabel {
    final c = _weatherDecision?.confidence;
    if (c == null) return null;
    return confidenceLabel(c);
  }

  Future<void> refreshWeatherAt(LatLng position, {bool userInitiated = true}) async {
    _lastWeatherPosition = position;
    _weatherLoading = true;
    _weatherError = null;
    notifyListeners();

    final snap = SchedulerSnapshot(
      appInForeground: _appInForeground,
      isOnline: _isOnline ?? true,
      lowPowerMode: _lowPowerMode,
      navigationActive: _navigationActive,
      speedMps: null,
    );
    if (!_scheduler.shouldComputeWeather(snap, userInitiated: userInitiated)) {
      _weatherLoading = false;
      notifyListeners();
      return;
    }

    try {
      final sw = Stopwatch()..start();
      final decision = await _weatherEngine.getDecisionForPointAtTime(
        position,
        at: _forecastBaseUtc(),
      );
      sw.stop();
      _weatherDecision = decision;
      _weatherLoading = false;
      notifyListeners();

      _metrics.recordDuration('weather_decision_ms', sw.elapsedMilliseconds);
      _metrics.inc('weather_refresh');
      unawaited(_metrics.flush());
      unawaited(_analytics.record('weather_refreshed', props: {'trigger': userInitiated ? 'user' : 'auto'}));
    } catch (e) {
      _weatherLoading = false;
      _weatherError = e.toString();
      notifyListeners();

      _metrics.inc('weather_error');
      unawaited(_metrics.flush());
    }
  }

  Future<void> _ensureExpertWeatherLayers() async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.addSource('expert-weather', GeojsonSourceProperties(data: _emptyFeatureCollection()));
    } catch (_) {}

    try {
      await controller.addCircleLayer(
        'expert-weather',
        'expert-wind-layer',
        const CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['get', 'windKmh'],
            0,
            2.0,
            25,
            5.0,
            55,
            9.0,
          ],
          circleColor: [
            'interpolate',
            ['linear'],
            ['get', 'windKmh'],
            0,
            '#ABC9D3',
            25,
            '#4A90A0',
            55,
            '#2E2E2E',
          ],
          circleOpacity: 0.55,
          circleBlur: 0.2,
        ),
      );
    } catch (_) {}

    try {
      await controller.addCircleLayer(
        'expert-weather',
        'expert-rain-layer',
        const CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['get', 'rainMmH'],
            0,
            1.0,
            1,
            4.0,
            5,
            9.0,
          ],
          circleColor: [
            'interpolate',
            ['linear'],
            ['get', 'rainMmH'],
            0,
            '#ffffff',
            1,
            '#5AA6B5',
            5,
            '#2B4C9A',
          ],
          circleOpacity: 0.42,
          circleBlur: 0.35,
        ),
      );
    } catch (_) {}

    try {
      await controller.addCircleLayer(
        'expert-weather',
        'expert-cloud-layer',
        const CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['get', 'cloudPct'],
            0,
            1.0,
            100,
            8.0,
          ],
          circleColor: [
            'interpolate',
            ['linear'],
            ['get', 'cloudPct'],
            0,
            '#B4C6D6',
            100,
            '#808A94',
          ],
          circleOpacity: 0.28,
          circleBlur: 0.25,
        ),
      );
    } catch (_) {}

    await _renderExpertWeatherLayers();
  }

  Future<void> _renderExpertWeatherLayers() async {
    final controller = _mapController;
    if (controller == null) return;
    if (!_styleLoaded) return;

    if (!_expertWeatherMode) {
      try {
        await controller.setGeoJsonSource('expert-weather', _emptyFeatureCollection());
      } catch (_) {}
      return;
    }

    final points = <Map<String, Object?>>[];
    if (_lastWeatherPosition != null && _weatherDecision != null) {
      final p = _lastWeatherPosition!;
      final s = _weatherDecision!.now;
      points.add({
        'type': 'Feature',
        'properties': {
          'windKmh': s.windSpeed * 3.6,
          'rainMmH': s.precipitation,
          'cloudPct': (s.cloudCover * 100).clamp(0, 100),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [p.longitude, p.latitude],
        },
      });
    }

    try {
      await controller.setGeoJsonSource('expert-weather', {
        'type': 'FeatureCollection',
        'features': points,
      });
    } catch (_) {}

    try {
      await controller.setPaintProperty('expert-wind-layer', 'circle-opacity', _expertWindLayer ? 0.55 : 0.0);
      await controller.setPaintProperty('expert-rain-layer', 'circle-opacity', _expertRainLayer ? 0.42 : 0.0);
      await controller.setPaintProperty('expert-cloud-layer', 'circle-opacity', _expertCloudLayer ? 0.28 : 0.0);
    } catch (_) {}
  }

  void setExpertWeatherMode(bool enabled) {
    _expertWeatherMode = enabled;
    notifyListeners();
    unawaited(_renderExpertWeatherLayers());
  }

  void setExpertWindLayer(bool enabled) {
    _expertWindLayer = enabled;
    notifyListeners();
    unawaited(_renderExpertWeatherLayers());
  }

  void setExpertRainLayer(bool enabled) {
    _expertRainLayer = enabled;
    notifyListeners();
    unawaited(_renderExpertWeatherLayers());
  }

  void setExpertCloudLayer(bool enabled) {
    _expertCloudLayer = enabled;
    notifyListeners();
    unawaited(_renderExpertWeatherLayers());
  }

  Map<String, dynamic> _emptyFeatureCollection() => const {
        'type': 'FeatureCollection',
        'features': [],
      };

  void _startWeatherAutoRefresh() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      final pos = _lastWeatherPosition;
      if (pos == null) return;
      if (!_appInForeground) return;
      unawaited(refreshWeatherAt(pos, userInitiated: false));
    });
  }

  @override
  void dispose() {
    _weatherRefreshTimer?.cancel();
    super.dispose();
  }
}
