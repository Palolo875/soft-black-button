import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:app/core/log/app_log.dart';
import 'package:app/services/offline_registry.dart';
import 'package:app/services/offline_service.dart';

class OfflineProvider with ChangeNotifier {
  final OfflineService _offlineService;

  MaplibreMapController? _mapController;

  double? _offlineDownloadProgress;
  String? _offlineDownloadError;

  bool _pmtilesEnabled = false;
  double? _pmtilesProgress;
  String? _pmtilesError;
  String _pmtilesFileName = 'horizon.pmtiles';

  StreamSubscription<DownloadRegionStatus>? _offlineDownloadSub;

  double? get offlineDownloadProgress => _offlineDownloadProgress;
  String? get offlineDownloadError => _offlineDownloadError;

  bool get pmtilesEnabled => _pmtilesEnabled;
  double? get pmtilesProgress => _pmtilesProgress;
  String? get pmtilesError => _pmtilesError;
  String get pmtilesFileName => _pmtilesFileName;

  OfflineProvider({required OfflineService offlineService}) : _offlineService = offlineService;

  void setController(MaplibreMapController controller) {
    _mapController = controller;
  }

  Future<List<OfflinePack>> listOfflinePacks() {
    return _offlineService.listOfflinePacks();
  }

  Future<void> uninstallOfflinePackById(String id) {
    return _offlineService.uninstallPackById(id);
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
    } catch (e, st) {
      AppLog.e('offline.uninstallCurrentPmtilesPack failed', error: e, stackTrace: st);
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

    _pmtilesFileName = fileName;
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

      await controller.setStyle(styleFilePath);

      _pmtilesEnabled = true;
      _pmtilesProgress = 1.0;
      notifyListeners();
    } catch (e, st) {
      AppLog.e('offline.enablePmtilesPack failed', error: e, stackTrace: st, props: {
        'fileName': fileName,
      });
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
      await controller.setStyle('assets/styles/horizon_style.json');
      _pmtilesEnabled = false;
      _pmtilesProgress = null;
      notifyListeners();
    } catch (e, st) {
      AppLog.e('offline.disablePmtilesPack failed', error: e, stackTrace: st);
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
    } catch (e, st) {
      AppLog.e('offline.downloadVisibleRegion failed', error: e, stackTrace: st);
      _offlineDownloadError = e.toString();
      _offlineDownloadProgress = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_offlineDownloadSub?.cancel());
    unawaited(_offlineService.stopPmtilesServer());
    super.dispose();
  }
}
