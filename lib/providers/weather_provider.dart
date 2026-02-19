import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:horizon/core/constants/horizon_constants.dart';
import 'package:horizon/core/format/confidence_label.dart';
import 'package:horizon/core/format/friendly_error.dart';
import 'package:horizon/core/log/app_log.dart';
import 'package:horizon/services/analytics_service.dart';
import 'package:horizon/services/horizon_scheduler.dart';
import 'package:horizon/services/perf_metrics.dart';
import 'package:horizon/services/weather_engine_sota.dart';
import 'package:horizon/services/weather_models.dart';
import 'package:horizon/services/weather_service.dart';

import 'package:horizon/services/weather_map_renderer.dart';
import 'package:horizon/providers/mobility_provider.dart';

class WeatherProvider with ChangeNotifier {
  final WeatherService _weatherService;
  final WeatherEngineSota _weatherEngine;
  final WeatherMapRenderer _mapRenderer;
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

  MobilityProvider? _mobility;

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
    WeatherMapRenderer mapRenderer = const WeatherMapRenderer(),
  })  : _weatherService = weatherService,
        _weatherEngine = weatherEngine,
        _scheduler = scheduler,
        _metrics = metrics,
        _analytics = analytics,
        _mapRenderer = mapRenderer;

  void attachMobility(MobilityProvider mobility) {
    if (identical(_mobility, mobility)) return;
    _mobility = mobility;
  }

  void setController(MaplibreMapController controller) {
    _mapController = controller;
    if (_styleLoaded) {
      _weatherService.initWeather(controller: controller);
      _startWeatherAutoRefresh();
      unawaited(_mapRenderer.initLayers(controller).then((_) => _renderExpertWeatherLayers()));
    }
  }

  void setStyleLoaded(bool loaded) {
    _styleLoaded = loaded;
    if (loaded && _mapController != null) {
      _weatherService.initWeather(controller: _mapController!);
      _startWeatherAutoRefresh();
      unawaited(_mapRenderer.initLayers(_mapController!).then((_) => _renderExpertWeatherLayers()));
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
    return confidenceLabelFr(confidence);
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
        comfortProfile: _mobility?.comfortProfile,
      );
      sw.stop();
      _weatherDecision = decision;
      _weatherLoading = false;
      notifyListeners();

      _metrics.recordDuration('weather_decision_ms', sw.elapsedMilliseconds);
      _metrics.inc('weather_refresh');
      unawaited(_metrics.flush());
      unawaited(_analytics.record('weather_refreshed', props: {'trigger': userInitiated ? 'user' : 'auto'}));
      unawaited(_renderExpertWeatherLayers());
    } catch (e, st) {
      AppLog.e('weather.refreshWeather failed', error: e, stackTrace: st, props: {
        'userInitiated': userInitiated,
      });
      _weatherLoading = false;
      _weatherError = friendlyError(e);
      notifyListeners();

      _metrics.inc('weather_error');
      unawaited(_metrics.flush());
    }
  }

  Future<void> _renderExpertWeatherLayers() async {
    await _mapRenderer.render(
      controller: _mapController,
      styleLoaded: _styleLoaded,
      expertWeatherMode: _expertWeatherMode,
      expertWindLayer: _expertWindLayer,
      expertRainLayer: _expertRainLayer,
      expertCloudLayer: _expertCloudLayer,
      lastPosition: _lastWeatherPosition,
      decision: _weatherDecision,
    );
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

  void _startWeatherAutoRefresh() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(HorizonConstants.weatherAutoRefreshInterval, (_) {
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
