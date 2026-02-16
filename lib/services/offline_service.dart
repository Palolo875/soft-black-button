import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class OfflineService {
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

  // Note: Pour une implémentation SOTA, on utiliserait des range requests
  // pour ne pas télécharger tout le fichier si on n'en a pas besoin,
  // mais PMTiles est conçu pour être utilisé comme un fichier complet en offline.

  Future<void> downloadRegion(String regionName, LatLngBounds bounds) async {
    if (kIsWeb) return;

    // Utilisation de l'OfflineManager natif de MapLibre
    // (Ceci ne fonctionne pas sur Web)
    // await downloadOfflineRegion(
    //   OfflineRegionDefinition(
    //     bounds: bounds,
    //     minZoom: 10,
    //     maxZoom: 14,
    //     mapStyleUrl: "assets/styles/horizon_style.json",
    //   ),
    //   metadata: {"name": regionName},
    // );
  }
}
