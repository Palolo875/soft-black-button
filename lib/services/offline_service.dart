import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pmtiles/pmtiles.dart' as pm;

class OfflineService {
  HttpServer? _pmtilesServer;
  pm.PmTilesArchive? _pmtilesArchive;

  Future<String> downloadPMTiles(String url, String fileName) async {
    if (kIsWeb) {
      return url; // Sur le web, on retourne l'URL directe (le navigateur gère le cache)
    }

    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);

    if (await file.exists()) {
      return filePath;
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } else {
      throw Exception('Failed to download PMTiles');
    }
  }

  Future<Uri?> startPmtilesServer({
    required String pmtilesFilePath,
    String tilesPathPrefix = '/tiles',
  }) async {
    if (kIsWeb) return null;

    if (_pmtilesServer != null) {
      return Uri.parse('http://127.0.0.1:${_pmtilesServer!.port}$tilesPathPrefix');
    }

    final archive = await pm.PmTilesArchive.fromFile(File(pmtilesFilePath));
    _pmtilesArchive = archive;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _pmtilesServer = server;

    // Serve requests.
    unawaited(() async {
      await for (final request in server) {
        try {
          final path = request.uri.path;

          if (path == '/health') {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.text;
            request.response.write('ok');
            await request.response.close();
            continue;
          }

          if (!path.startsWith(tilesPathPrefix)) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            continue;
          }

          // Expected: /tiles/{z}/{x}/{y}.pbf
          final segments = path.split('/').where((s) => s.isNotEmpty).toList();
          if (segments.length != 4) {
            request.response.statusCode = HttpStatus.badRequest;
            await request.response.close();
            continue;
          }

          final z = int.tryParse(segments[1]);
          final x = int.tryParse(segments[2]);
          final yStr = segments[3];
          final y = int.tryParse(yStr.endsWith('.pbf') ? yStr.substring(0, yStr.length - 4) : yStr);

          if (z == null || x == null || y == null) {
            request.response.statusCode = HttpStatus.badRequest;
            await request.response.close();
            continue;
          }

          final tileId = pm.ZXY(z, x, y).toTileId();
          final tile = await archive.tile(tileId);

          // MapLibre expects raw MVT protobuf bytes.
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType('application', 'x-protobuf');
          request.response.headers.set('Access-Control-Allow-Origin', '*');
          request.response.add(tile.bytes());
          await request.response.close();
        } catch (e) {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        }
      }
    }());

    return Uri.parse('http://127.0.0.1:${server.port}$tilesPathPrefix');
  }

  Future<void> stopPmtilesServer() async {
    if (kIsWeb) return;

    final server = _pmtilesServer;
    _pmtilesServer = null;

    final archive = _pmtilesArchive;
    _pmtilesArchive = null;

    await archive?.close();
    await server?.close(force: true);
  }

  Future<String> buildStyleFileForPmtiles({
    required Uri tilesBaseUri,
    String vectorSourceName = 'protomaps',
  }) async {
    final styleJsonString = await rootBundle.loadString('assets/styles/horizon_style.json');
    final styleJson = json.decode(styleJsonString) as Map<String, dynamic>;

    final sources = (styleJson['sources'] as Map<String, dynamic>?);
    if (sources == null || !sources.containsKey(vectorSourceName)) {
      throw Exception('Vector source "$vectorSourceName" not found in style');
    }

    final source = sources[vectorSourceName] as Map<String, dynamic>;
    source['tiles'] = ['${tilesBaseUri.toString()}/{z}/{x}/{y}.pbf'];

    final directory = await getApplicationDocumentsDirectory();
    final outFile = File('${directory.path}/horizon_style_pmtiles.json');
    await outFile.writeAsString(json.encode(styleJson));
    return outFile.path;
  }

  // Note: Pour une implémentation SOTA, on utiliserait des range requests
  // pour ne pas télécharger tout le fichier si on n'en a pas besoin,
  // mais PMTiles est conçu pour être utilisé comme un fichier complet en offline.

  Stream<DownloadRegionStatus> downloadRegion({
    required String regionName,
    required LatLngBounds bounds,
    double minZoom = 10,
    double maxZoom = 14,
  }) {
    final controller = StreamController<DownloadRegionStatus>();

    if (kIsWeb) {
      controller.close();
      return controller.stream;
    }

    () async {
      try {
        final styleJson = await rootBundle.loadString('assets/styles/horizon_style.json');
        final definition = OfflineRegionDefinition(
          bounds: bounds,
          mapStyleUrl: styleJson,
          minZoom: minZoom,
          maxZoom: maxZoom,
          includeIdeographs: true,
        );

        await downloadOfflineRegion(
          definition,
          metadata: {'name': regionName},
          onEvent: (event) {
            if (controller.isClosed) return;
            controller.add(event);
            if (event is Success || event is Error) {
              controller.close();
            }
          },
        );

        if (!controller.isClosed) {
          await controller.close();
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.add(
            Error(
              PlatformException(code: 'offline_download_error', message: e.toString()),
            ),
          );
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  Future<List<OfflineRegion>> listRegions() async {
    if (kIsWeb) return [];
    return getListOfRegions();
  }

  Future<void> deleteRegion(int id) async {
    if (kIsWeb) return;
    await deleteOfflineRegion(id);
  }
}
