import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app/providers/map_provider.dart';
import 'package:app/widgets/horizon_map.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  runApp(const HorizonApp());
}

class HorizonApp extends StatelessWidget {
  const HorizonApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFABC9D3);
    const radius = 22.0;

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
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF6F7F8),
        cardTheme: CardTheme(
          color: Colors.white.withOpacity(0.9),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.92),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: seed.withOpacity(0.35), width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 1.5,
          backgroundColor: Colors.white.withOpacity(0.92),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
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
  static const _glassRadius = 22.0;

  BoxDecoration _glassDecoration({double opacity = 0.62}) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(_glassRadius),
      border: Border.all(color: Colors.white.withOpacity(0.32)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

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
                    borderRadius: BorderRadius.circular(_glassRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: _glassDecoration(),
                        child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF88D3A2),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          mapProvider.weatherError != null
                              ? Icons.cloud_off_rounded
                              : (mapProvider.weatherLoading
                                  ? Icons.cloud_sync_rounded
                                  : Icons.wb_sunny_rounded),
                          size: 18,
                          color: mapProvider.weatherError != null
                              ? const Color(0xFFB55A5A)
                              : (mapProvider.weatherLoading
                                  ? const Color(0xFF4A90A0)
                                  : const Color(0xFFFFC56E)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          mapProvider.weatherError != null
                              ? 'Météo indisponible'
                              : (mapProvider.weatherDecision == null
                                  ? 'Météo…'
                                  : '${mapProvider.weatherDecision!.now.temperature.round()}°C  •  confort ${mapProvider.weatherDecision!.comfortScore.toStringAsFixed(1)}/10  •  conf ${(mapProvider.weatherDecision!.confidence * 100).round()}%'),
                          style: const TextStyle(
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
                          url: 'https://r2-public.protomaps.com/protomaps-sample-datasets/cb_2018_us_zcta510_500k.pmtiles',
                          fileName: 'horizon.pmtiles',
                          regionNameForUi: 'Pack offline',
                        );
                      }
                    },
                    child: Icon(
                      mapProvider.pmtilesEnabled
                          ? Icons.storage_rounded
                          : Icons.storage_outlined,
                      color: mapProvider.pmtilesEnabled ? const Color(0xFF2E2E2E) : Colors.black87,
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
                    child: const Icon(Icons.my_location, color: Colors.blueAccent),
                  ),
                ),

                // Timeline Slider SOTA 2026
                ClipRRect(
                  borderRadius: BorderRadius.circular(_glassRadius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: _glassDecoration(),
                      child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Maintenant",
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black.withOpacity(0.70)),
                          ),
                          Text(
                            "+${mapProvider.timeOffset.toInt()}h",
                            style: const TextStyle(fontSize: 10, color: Color(0xFF4A90A0), fontWeight: FontWeight.w700),
                          ),
                          Text(
                            "+24h",
                            style: TextStyle(fontSize: 10, color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: const Color(0xFF4A90A0),
                          inactiveTrackColor: const Color(0xFF4A90A0).withOpacity(0.25),
                          thumbColor: const Color(0xFF4A90A0),
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
                  decoration: _glassDecoration(opacity: 0.85),
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
                borderRadius: BorderRadius.circular(_glassRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: _glassDecoration(opacity: 0.78),
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
                                          color: const Color(0xFF4A90A0),
                                          backgroundColor: const Color(0xFF4A90A0).withOpacity(0.18),
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
