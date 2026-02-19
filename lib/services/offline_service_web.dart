import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:horizon/services/offline_registry.dart';

class OfflineService {
  Future<List<OfflinePack>> listOfflinePacks() async {
    return const [];
  }

  Future<void> uninstallPackById(String id) async {}

  Future<String> downloadPMTiles(String url, String fileName) async {
    return url;
  }

  Future<void> uninstallPmtilesPack({required String fileName}) async {}

  Future<Uri?> startPmtilesServer({
    required String pmtilesFilePath,
    String tilesPathPrefix = '/tiles',
  }) async {
    return null;
  }

  Future<void> stopPmtilesServer() async {}

  Future<String> buildStyleFileForPmtiles({
    required Uri tilesBaseUri,
    String vectorSourceName = 'protomaps',
  }) async {
    throw Exception('PMTiles offline not supported on Web');
  }

  Stream<DownloadRegionStatus> downloadRegion({
    required String regionName,
    required LatLngBounds bounds,
    double minZoom = 10,
    double maxZoom = 14,
  }) {
    final controller = StreamController<DownloadRegionStatus>();
    controller.close();
    return controller.stream;
  }

  Future<List<OfflineRegion>> listRegions() async {
    return [];
  }

  Future<void> deleteRegion(int id) async {
    return;
  }
}
