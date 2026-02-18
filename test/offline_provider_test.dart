import 'dart:async';

import 'package:horizon/providers/offline_provider.dart';
import 'package:horizon/services/offline_registry.dart';
import 'package:horizon/services/offline_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class _FakeOfflineService implements OfflineService {
  final StreamController<DownloadRegionStatus> controller = StreamController<DownloadRegionStatus>.broadcast();

  bool stopServerCalled = false;
  bool startServerCalled = false;
  bool buildStyleCalled = false;

  @override
  Future<List<OfflinePack>> listOfflinePacks() async => const [];

  @override
  Future<void> uninstallPackById(String id) async {}

  @override
  Future<String> downloadPMTiles(String url, String fileName) async => 'C:/tmp/$fileName';

  @override
  Future<void> uninstallPmtilesPack({required String fileName}) async {}

  @override
  Future<Uri?> startPmtilesServer({required String pmtilesFilePath, String tilesPathPrefix = '/tiles'}) async {
    startServerCalled = true;
    return Uri.parse('http://127.0.0.1:1234$tilesPathPrefix');
  }

  @override
  Future<void> stopPmtilesServer() async {
    stopServerCalled = true;
  }

  @override
  Future<String> buildStyleFileForPmtiles({required Uri tilesBaseUri, String vectorSourceName = 'protomaps'}) async {
    buildStyleCalled = true;
    return 'assets/styles/horizon_style.json';
  }

  @override
  Stream<DownloadRegionStatus> downloadRegion({
    required String regionName,
    required LatLngBounds bounds,
    double minZoom = 10,
    double maxZoom = 14,
  }) {
    return controller.stream;
  }

  @override
  Future<List<OfflineRegion>> listRegions() async => const [];

  @override
  Future<void> deleteRegion(int id) async {}
}

class _FakeMapController implements MaplibreMapController {
  bool setStyleCalled = false;
  @override
  Future<void> setStyle(String styleString) async {
    setStyleCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('OfflineProvider downloadVisibleRegion updates progress and completes', () async {
    final svc = _FakeOfflineService();
    final provider = OfflineProvider(offlineService: svc);
    provider.setController(_FakeMapController());

    expect(provider.offlineDownloadProgress, isNull);

    await provider.downloadVisibleRegion(regionName: 'x');

    svc.controller.add(InProgress(0.4));
    await Future<void>.delayed(Duration.zero);
    expect(provider.offlineDownloadProgress, 0.4);

    svc.controller.add(Success());
    await Future<void>.delayed(Duration.zero);
    expect(provider.offlineDownloadProgress, 1.0);
  });

  test('OfflineProvider enablePmtilesPack toggles enabled when setStyle succeeds', () async {
    final svc = _FakeOfflineService();
    final provider = OfflineProvider(offlineService: svc);
    final controller = _FakeMapController();
    provider.setController(controller);

    await provider.enablePmtilesPack(url: 'https://example.com/x.pmtiles', fileName: 'x.pmtiles');

    expect(svc.startServerCalled, isTrue);
    expect(svc.buildStyleCalled, isTrue);
    expect(controller.setStyleCalled, isTrue);
    expect(provider.pmtilesEnabled, isTrue);
  });
}
