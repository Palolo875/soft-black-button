import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:horizon/core/error/result.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:xml/xml.dart';

class GpxImportResult {
  final String fileName;
  final List<LatLng> points;

  const GpxImportResult({
    required this.fileName,
    required this.points,
  });
}

class GpxImportService {
  Future<Result<GpxImportResult?>> pickAndParse() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gpx'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return Result.success(null);

      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        return Result.failure('Fichier GPX inaccessible (bytes null).');
      }

      final xmlStr = utf8.decode(bytes, allowMalformed: true);
      final doc = XmlDocument.parse(xmlStr);

      final pts = <LatLng>[];

      // Prefer track points.
      for (final trkpt in doc.findAllElements('trkpt')) {
        final lat = double.tryParse(trkpt.getAttribute('lat') ?? '');
        final lon = double.tryParse(trkpt.getAttribute('lon') ?? '');
        if (lat == null || lon == null) continue;
        pts.add(LatLng(lat, lon));
      }

      // Fallback to route points.
      if (pts.length < 2) {
        for (final rtept in doc.findAllElements('rtept')) {
          final lat = double.tryParse(rtept.getAttribute('lat') ?? '');
          final lon = double.tryParse(rtept.getAttribute('lon') ?? '');
          if (lat == null || lon == null) continue;
          pts.add(LatLng(lat, lon));
        }
      }

      // Fallback to waypoints (rare).
      if (pts.length < 2) {
        for (final wpt in doc.findAllElements('wpt')) {
          final lat = double.tryParse(wpt.getAttribute('lat') ?? '');
          final lon = double.tryParse(wpt.getAttribute('lon') ?? '');
          if (lat == null || lon == null) continue;
          pts.add(LatLng(lat, lon));
        }
      }

      if (pts.length < 2) {
        return Result.failure('GPX invalide: aucun tracé exploitable (trkpt/rtept).');
      }

      final fileName = f.name.isNotEmpty ? f.name : 'import.gpx';
      return Result.success(GpxImportResult(fileName: fileName, points: pts));
    } catch (e, st) {
      return Result.failure(e, st);
    }
  }
}
