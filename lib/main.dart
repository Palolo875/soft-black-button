import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app/providers/map_provider.dart';
import 'package:app/widgets/horizon_map.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const HorizonApp());
}

class HorizonApp extends StatelessWidget {
  const HorizonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MapProvider()),
      ],
      child: MaterialApp(
      title: 'Horizon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFabc9d3),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      home: const MapScreen(),
    ));
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Future<void> _recenterOnUser(MapProvider mapProvider) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      mapProvider.centerOnUser(LatLng(position.latitude, position.longitude));
    } catch (_) {
      // Permissions / service disabled / timeout.
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = Provider.of<MapProvider>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          HorizonMap(
            onMapCreated: (controller) {
              mapProvider.setController(controller);
            },
          ),

          if (!mapProvider.isStyleLoaded)
            const Center(
              child: CircularProgressIndicator(),
            ),

          // Header: Pilule météo / état
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Hero(
                tag: 'status-pill',
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.wb_sunny_rounded, size: 18, color: Color(0xFFFFB74D)),
                        const SizedBox(width: 8),
                        const Text(
                          "Paris — 22°C",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: Colors.black87,
                          ),
                        ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Search / Controls
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Bouton Pack PMTiles (offline robuste)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FloatingActionButton.small(
                    heroTag: 'pmtiles-pack',
                    onPressed: () {
                      if (mapProvider.pmtilesEnabled) {
                        mapProvider.disablePmtilesPack();
                      } else {
                        mapProvider.enablePmtilesPack(
                          url: 'https://example.com/horizon.pmtiles',
                          fileName: 'horizon.pmtiles',
                          regionNameForUi: 'Pack offline',
                        );
                      }
                    },
                    backgroundColor: Colors.white,
                    elevation: 2,
                    child: Icon(
                      mapProvider.pmtilesEnabled
                          ? Icons.storage_rounded
                          : Icons.storage_outlined,
                      color: Colors.black87,
                    ),
                  ),
                ),

                // Bouton Offline (download région visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FloatingActionButton.small(
                    heroTag: 'offline-download',
                    onPressed: () {
                      mapProvider.downloadVisibleRegion(regionName: 'Visible region');
                    },
                    backgroundColor: Colors.white,
                    elevation: 2,
                    child: const Icon(Icons.download_for_offline_outlined, color: Colors.black87),
                  ),
                ),

                // Bouton Localisation
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FloatingActionButton.small(
                    onPressed: () {
                      _recenterOnUser(mapProvider);
                    },
                    backgroundColor: Colors.white,
                    elevation: 2,
                    child: const Icon(Icons.my_location, color: Colors.blueAccent),
                  ),
                ),

                // Timeline Slider SOTA 2026
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Maintenant", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          Text("+${mapProvider.timeOffset.toInt()}h", style: const TextStyle(fontSize: 10, color: Colors.blue)),
                          const Text("+24h", style: TextStyle(fontSize: 10)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: mapProvider.timeOffset,
                          min: 0,
                          max: 24,
                          onChanged: (val) => mapProvider.setTimeOffset(val),
                        ),
                      ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Barre de recherche minimaliste
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Où allez-vous ?",
                      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

      // Overlay progression offline (minimal)
      floatingActionButton: (mapProvider.offlineDownloadProgress == null &&
              mapProvider.offlineDownloadError == null &&
              mapProvider.pmtilesProgress == null &&
              mapProvider.pmtilesError == null)
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.offline_pin_outlined, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: mapProvider.pmtilesError != null
                              ? Text(
                                  mapProvider.pmtilesError!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                )
                              : mapProvider.offlineDownloadError != null
                                  ? Text(
                                      mapProvider.offlineDownloadError!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mapProvider.pmtilesProgress != null
                                              ? 'Activation pack offline…'
                                              : 'Téléchargement offline…',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 6),
                                        LinearProgressIndicator(
                                          value: mapProvider.pmtilesProgress ?? mapProvider.offlineDownloadProgress,
                                          minHeight: 3,
                                        ),
                                      ],
                                    ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          onPressed: () {
                            // Minimal: juste masquer l'erreur/état.
                            // (On peut ajouter un vrai cancel quand on branchera l'API native.)
                            mapProvider.clearOfflineDownloadState();
                            mapProvider.clearPmtilesState();
                          },
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
