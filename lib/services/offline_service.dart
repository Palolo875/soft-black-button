import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pmtiles/pmtiles.dart' as pm;
import 'package:app/services/offline_core.dart';
import 'package:app/services/offline_registry.dart';
import 'package:app/services/secure_http_client.dart';

class OfflineService {
  HttpServer? _pmtilesServer;
  pm.PmTilesArchive? _pmtilesArchive;
  Uri? _proxyRemoteGlyphsBase;
  Uri? _proxyRemoteSpriteBase;
  Directory? _proxyCacheDir;

  final OfflineCore _offlineCore = OfflineCore();
  final SecureHttpClient _http = SecureHttpClient();

  Future<List<OfflinePack>> listOfflinePacks() async {
    await _offlineCore.registry.pruneMissingFiles();
    return _offlineCore.registry.listPacks();
  }

  Future<void> uninstallPackById(String id) {
    return _offlineCore.uninstallPackById(id);
  }

  Future<String> downloadPMTiles(String url, String fileName) async {
    if (kIsWeb) {
      return url; // Sur le web, on retourne l'URL directe (le navigateur gère le cache)
    }
    final root = await _offlineCore.registry.rootDir();
    final filePath = '${root.path}/$fileName';
    final file = File(filePath);
    if (await file.exists()) {
      await _offlineCore.registry.touch('pmtiles:$fileName');
      return filePath;
    }

    await _offlineCore.installFilePack(
      id: 'pmtiles:$fileName',
      type: OfflinePackType.pmtiles,
      url: Uri.parse(url),
      fileName: fileName,
    );
    return filePath;
  }

  Future<void> uninstallPmtilesPack({
    required String fileName,
  }) async {
    if (kIsWeb) return;

    try {
      if (_pmtilesServer != null) {
        await stopPmtilesServer();
      }
    } catch (_) {}

    await _offlineCore.uninstallPackById('pmtiles:$fileName');
  }

  Future<Uri?> startPmtilesServer({
    required String pmtilesFilePath,
    String tilesPathPrefix = '/tiles',
  }) async {
    if (kIsWeb) return null;

    final fileName = pmtilesFilePath.split(Platform.pathSeparator).last;
    unawaited(_offlineCore.registry.touch('pmtiles:$fileName'));

    if (_pmtilesServer != null) {
      return Uri.parse('http://127.0.0.1:${_pmtilesServer!.port}$tilesPathPrefix');
    }

    final archive = await pm.PmTilesArchive.fromFile(File(pmtilesFilePath));
    _pmtilesArchive = archive;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _pmtilesServer = server;

    final docsDir = await getApplicationDocumentsDirectory();
    _proxyCacheDir ??= Directory('${docsDir.path}/horizon_cache');
    if (!await _proxyCacheDir!.exists()) {
      await _proxyCacheDir!.create(recursive: true);
    }

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

          if (path.startsWith(tilesPathPrefix)) {
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
            continue;
          }

          if (path.startsWith('/glyphs/')) {
            await _handleProxyCached(request, base: _proxyRemoteGlyphsBase, kind: _ProxyKind.glyphs);
            continue;
          }

          if (path.startsWith('/sprites')) {
            await _handleProxyCached(request, base: _proxyRemoteSpriteBase, kind: _ProxyKind.sprites);
            continue;
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
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
    _proxyRemoteGlyphsBase = null;
    _proxyRemoteSpriteBase = null;
  }

  Future<String> buildStyleFileForPmtiles({
    required Uri tilesBaseUri,
    String vectorSourceName = 'protomaps',
  }) async {
    final styleJsonString = await rootBundle.loadString('assets/styles/horizon_style.json');
    final styleJson = json.decode(styleJsonString) as Map<String, dynamic>;

    // Capture remote endpoints so we can proxy+cache them via localhost.
    final glyphs = styleJson['glyphs'];
    if (glyphs is String && glyphs.startsWith('http')) {
      // Keep only base path up to /{fontstack}/{range}.pbf
      _proxyRemoteGlyphsBase = Uri.parse(glyphs.replaceAll('{fontstack}/{range}.pbf', ''));
    }
    final sprite = styleJson['sprite'];
    if (sprite is String && sprite.startsWith('http')) {
      _proxyRemoteSpriteBase = Uri.parse(sprite);
    }

    final sources = (styleJson['sources'] as Map<String, dynamic>?);
    if (sources == null || !sources.containsKey(vectorSourceName)) {
      throw Exception('Vector source "$vectorSourceName" not found in style');
    }

    final source = sources[vectorSourceName] as Map<String, dynamic>;
    source['tiles'] = ['${tilesBaseUri.toString()}/{z}/{x}/{y}.pbf'];

    // Patch glyphs/sprites to localhost (served via proxy+cache).
    if (_pmtilesServer != null) {
      final port = _pmtilesServer!.port;
      if (_proxyRemoteGlyphsBase != null) {
        styleJson['glyphs'] = 'http://127.0.0.1:$port/glyphs/{fontstack}/{range}.pbf';
      }
      if (_proxyRemoteSpriteBase != null) {
        styleJson['sprite'] = 'http://127.0.0.1:$port/sprites';
      }
    }

    final directory = await getApplicationDocumentsDirectory();
    final outFile = File('${directory.path}/horizon_style_pmtiles.json');
    await outFile.writeAsString(json.encode(styleJson));
    return outFile.path;
  }

  Future<void> _handleProxyCached(
    HttpRequest request, {
    required Uri? base,
    required _ProxyKind kind,
  }) async {
    if (base == null || _proxyCacheDir == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final relativePath = request.uri.path;
    final query = request.uri.hasQuery ? '?${request.uri.query}' : '';
    final cacheKey = base64Url.encode(utf8.encode('${base.toString()}$relativePath$query'));
    final cachedFile = File('${_proxyCacheDir!.path}/$cacheKey');

    if (await cachedFile.exists()) {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.add(await cachedFile.readAsBytes());
      await request.response.close();
      return;
    }

    final remoteUri = switch (kind) {
      _ProxyKind.glyphs => base.resolve(relativePath.replaceFirst(RegExp('^/glyphs/'), '')),
      _ProxyKind.sprites => Uri.parse('${base.toString()}${relativePath.replaceFirst(RegExp('^/sprites'), '')}'),
    };
    try {
      final response = await _http.get(remoteUri);
      if (response.statusCode != 200) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      await cachedFile.writeAsBytes(response.bodyBytes, flush: true);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.add(response.bodyBytes);
      await request.response.close();
    } catch (_) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
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

enum _ProxyKind { glyphs, sprites }
