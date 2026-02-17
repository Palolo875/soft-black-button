import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:app/services/weather_service.dart';
import 'package:app/services/offline_service.dart';
import 'package:app/services/weather_engine_sota.dart';
import 'package:app/services/weather_models.dart';

class MapProvider with ChangeNotifier {
  MaplibreMapController? _mapController;
  bool _isStyleLoaded = false;
  final WeatherService _weatherService = WeatherService();
  final WeatherEngineSota _weatherEngine = const WeatherEngineSota();
  final OfflineService _offlineService = OfflineService();
  double _timeOffset = 0.0;

  Timer? _weatherRefreshTimer;
  LatLng? _lastWeatherPosition;

  WeatherDecision? _weatherDecision;
  bool _weatherLoading = false;
  String? _weatherError;

  double? _offlineDownloadProgress;
  String? _offlineDownloadError;

  bool _pmtilesEnabled = false;
  double? _pmtilesProgress;
  String? _pmtilesError;

  MaplibreMapController? get mapController => _mapController;
  bool get isStyleLoaded => _isStyleLoaded;
  WeatherDecision? get weatherDecision => _weatherDecision;
  bool get weatherLoading => _weatherLoading;
  String? get weatherError => _weatherError;
  double? get offlineDownloadProgress => _offlineDownloadProgress;
  String? get offlineDownloadError => _offlineDownloadError;
  bool get pmtilesEnabled => _pmtilesEnabled;
  double? get pmtilesProgress => _pmtilesProgress;
  String? get pmtilesError => _pmtilesError;

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

  void setTimeOffset(double value) {
    _timeOffset = value;
    _weatherService.updateTimeOffset(value);
    notifyListeners();
  }

  void setStyleLoaded(bool loaded) {
    _isStyleLoaded = loaded;
    if (loaded && _mapController != null) {
      _weatherService.initWeather(_mapController!);
      unawaited(refreshWeatherAt(_lastWeatherPosition ?? const LatLng(48.8566, 2.3522)));
      _startWeatherAutoRefresh();
    }
    notifyListeners();
  }

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
