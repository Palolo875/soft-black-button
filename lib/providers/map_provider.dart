import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/privacy_service.dart';
import 'package:horizon/services/analytics_service.dart';
import 'package:horizon/services/perf_metrics.dart';
import 'package:horizon/providers/routing_provider.dart';
import 'package:horizon/providers/offline_provider.dart';
import 'package:horizon/core/log/app_log.dart';
import 'package:horizon/core/format/confidence_label.dart';
import 'package:horizon/services/explainability_engine.dart';
import 'package:horizon/services/geocoding_service.dart';
import 'package:horizon/services/weather_models.dart';

class MapProvider with ChangeNotifier {
  MaplibreMapController? _mapController;
  LatLng? _webCenter;
  bool _isStyleLoaded = false;
  RoutingProvider? _routing;
  OfflineProvider? _offline;
  final PrivacyService _privacyService;
  final AnalyticsService _analytics;
  final PerfMetrics _metrics;
  final GeocodingService _geocoding;

  MapProvider({
    PrivacyService? privacyService,
    AnalyticsService? analytics,
    PerfMetrics? metrics,
    GeocodingService? geocoding,
  })  : _privacyService = privacyService ?? const PrivacyService(),
        _analytics = analytics ?? AnalyticsService(),
        _metrics = metrics ?? PerfMetrics(),
        _geocoding = geocoding ?? GeocodingService();

  double _timeOffset = 0.0;
  bool? _isOnline;
  bool _lowPowerMode = false;
  bool _appInForeground = true;
  bool _notificationsEnabledForContextual = false;
  bool _geocodingLoading = false;

  MaplibreMapController? get mapController => _mapController;
  LatLng? get webCenter => _webCenter;
  bool get isStyleLoaded => _isStyleLoaded;
  LatLng? get routeStart => _routing?.routeStart;
  LatLng? get routeEnd => _routing?.routeEnd;
  bool get routingLoading => _routing?.routingLoading ?? false;
  String? get routingError => _routing?.routingError;
  List<RouteVariant> get routeVariants => _routing?.routeVariants ?? const [];
  RouteVariantKind get selectedVariant => _routing?.selectedVariant ?? RouteVariantKind.fast;
  String? get routeExplanation => _routing?.routeExplanation;
  Map<RouteVariantKind, RouteExplanation> get routeExplanations => _routing?.routeExplanations ?? const {};
  RouteExplanation? get currentRouteExplanation => _routing?.currentRouteExplanation;
  RouteWeatherSample? get selectedRouteWeatherSample => _routing?.selectedRouteWeatherSample;
  bool get gpxImportLoading => _routing?.gpxImportLoading ?? false;
  String? get gpxImportError => _routing?.gpxImportError;
  String? get gpxRouteName => _routing?.gpxRouteName;
  double? get offlineDownloadProgress => _offline?.offlineDownloadProgress;
  String? get offlineDownloadError => _offline?.offlineDownloadError;
  bool get pmtilesEnabled => _offline?.pmtilesEnabled ?? false;
  double? get pmtilesProgress => _offline?.pmtilesProgress;
  String? get pmtilesError => _offline?.pmtilesError;
  String get pmtilesFileName => _offline?.pmtilesFileName ?? 'horizon.pmtiles';
  bool? get isOnline => _isOnline;
  bool get lowPowerMode => _lowPowerMode;
  bool get geocodingLoading => _geocodingLoading;

  String confidenceLabel(double confidence) {
    return confidenceLabelFr(confidence);
  }

  void syncIsOnlineFromConnectivity(bool? isOnline) {
    if (_isOnline == isOnline) return;
    _isOnline = isOnline;
    _routing?.syncIsOnline(isOnline);
    notifyListeners();
  }

  void setAppInForeground(bool fg) {
    if (_appInForeground == fg) return;
    _appInForeground = fg;
    _routing?.syncAppInForeground(fg);
    notifyListeners();
  }

  void setLowPowerMode(bool enabled) {
    if (_lowPowerMode == enabled) return;
    _lowPowerMode = enabled;
    _routing?.syncLowPowerMode(enabled);
    notifyListeners();
  }

  void syncNotificationsEnabledFromSettings(bool enabled) {
    _notificationsEnabledForContextual = enabled;
    _routing?.syncNotificationsEnabledFromSettings(enabled);
  }

  void attachRouting(RoutingProvider routing) {
    if (identical(_routing, routing)) return;
    _routing = routing;
    _routing?.syncIsOnline(_isOnline);
    _routing?.syncLowPowerMode(_lowPowerMode);
    _routing?.syncAppInForeground(_appInForeground);
    _routing?.syncTimeOffset(_timeOffset);
    _routing?.syncNotificationsEnabledFromSettings(_notificationsEnabledForContextual);
  }

  void attachOffline(OfflineProvider offline) {
    if (identical(_offline, offline)) return;
    _offline = offline;
  }

  Future<String> exportPerfMetricsJson() {
    return _metrics.exportJson();
  }

  Future<String?> exportAnalyticsBufferJson() {
    return _analytics.exportBufferJson();
  }

  Future<LocalDataReport> computeLocalDataReport() {
    return _privacyService.computeReport();
  }

  Future<void> panicWipeAllLocalData() async {
    await clearRoute();
    await _privacyService.panicWipeAllLocalData();
  }

  Future<void> uninstallCurrentPmtilesPack() async {
    final o = _offline;
    if (o != null) {
      await o.uninstallCurrentPmtilesPack();
      return;
    }
  }

  void clearOfflineDownloadState() {
    final o = _offline;
    if (o != null) {
      o.clearOfflineDownloadState();
      return;
    }
  }

  void clearPmtilesState() {
    final o = _offline;
    if (o != null) {
      o.clearPmtilesState();
      return;
    }
  }

  void setController(MaplibreMapController controller) {
    _mapController = controller;
    _offline?.setController(controller);
    notifyListeners();
  }

  double get timeOffset => _timeOffset;

  void setTimeOffset(double value) {
    _timeOffset = value;
    _routing?.syncTimeOffset(value);
    notifyListeners();
  }

  void setStyleLoaded(bool loaded) {
    _isStyleLoaded = loaded;
    _routing?.setStyleLoaded(loaded);
    notifyListeners();
  }

  void setRoutePoint(LatLng point) {
    final r = _routing;
    if (r != null) {
      r.setRoutePoint(point);
      return;
    }
    AppLog.w('map.setRoutePoint called without RoutingProvider attached');
  }

  Future<void> computeRouteVariants() async {
    final r = _routing;
    if (r != null) {
      await r.computeRouteVariants();
      return;
    }
    AppLog.w('map.computeRouteVariants called without RoutingProvider attached');
  }

  void selectRouteVariant(RouteVariantKind kind) {
    final r = _routing;
    if (r != null) {
      r.selectRouteVariant(kind);
      return;
    }
    AppLog.w('map.selectRouteVariant called without RoutingProvider attached', props: {'kind': kind.name});
  }

  Future<void> clearRoute() async {
    final r = _routing;
    if (r != null) {
      await r.clearRoute();
      return;
    }
  }

  Future<void> importGpxRoute() async {
    final r = _routing;
    if (r != null) {
      await r.importGpxRoute();
      return;
    }
    AppLog.w('map.importGpxRoute called without RoutingProvider attached');
  }

  void clearSelectedRouteWeatherSample() {
    final r = _routing;
    if (r != null) {
      r.clearSelectedRouteWeatherSample();
      return;
    }
  }

  void onMapTap(LatLng tap) {
    final r = _routing;
    if (r != null) {
      r.onMapTap(tap);
      return;
    }
  }

  @override
  void dispose() {
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
  
  Future<List<GeocodingResult>> searchLocation(String query) async {
    if (query.trim().isEmpty) return const [];
    
    _geocodingLoading = true;
    notifyListeners();
    _analytics.record('search_initiated', props: {'query': query});
    
    try {
      final results = await _geocoding.search(query, count: 10);
      if (results.isNotEmpty) {
        if (results.length == 1) {
          final target = results.first.location;
          centerOnUser(target);
        }
        AppLog.i('Search for "$query" found ${results.length} results.');
      } else {
        AppLog.i('Search for "$query" - No results found.');
      }
      return results;
    } catch (e, st) {
      AppLog.e('Search failed', error: e, stackTrace: st);
      return const [];
    } finally {
      _geocodingLoading = false;
      notifyListeners();
    }
  }

}
