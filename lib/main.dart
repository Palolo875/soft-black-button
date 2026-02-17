import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:app/providers/map_provider.dart';
import 'package:app/services/routing_models.dart';
import 'package:app/widgets/horizon_map.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const HorizonApp());
}

String _formatBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * kb;
  const gb = 1024 * mb;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}

class _RouteChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RouteChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A90A0).withOpacity(0.16) : Colors.white.withOpacity(0.0),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF4A90A0).withOpacity(0.45) : Colors.black.withOpacity(0.10),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF2E2E2E) : Colors.black54,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onLongPress: () async {
                          final report = await mapProvider.computeLocalDataReport();
                          if (!context.mounted) return;
                          await showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            builder: (ctx) {
                              return SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Confiance & confidentialité', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 12),
                                      Text('Stockage sécurisé : ${_formatBytes(report.secureStoreBytes)}', style: const TextStyle(fontSize: 12)),
                                      Text('Cache itinéraires (legacy) : ${_formatBytes(report.routeCacheBytes)}', style: const TextStyle(fontSize: 12)),
                                      Text('Cache météo (legacy) : ${_formatBytes(report.weatherCacheBytes)}', style: const TextStyle(fontSize: 12)),
                                      Text('Packs offline : ${_formatBytes(report.offlinePacksBytes)}', style: const TextStyle(fontSize: 12)),
                                      const SizedBox(height: 8),
                                      Text('Total : ${_formatBytes(report.totalBytes)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 14),
                                      const Text(
                                        'HORIZON fonctionne sans compte. Les données restent sur l’appareil.\nLong-press ici pour gérer/effacer rapidement.',
                                        style: TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => Navigator.of(ctx).pop(),
                                              child: const Text('Fermer'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: FilledButton(
                                              onPressed: () async {
                                                final ok = await showDialog<bool>(
                                                  context: ctx,
                                                  builder: (dctx) {
                                                    return AlertDialog(
                                                      title: const Text('Effacement rapide ?'),
                                                      content: const Text('Supprime caches, packs offline et clés locales. Action irréversible.'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.of(dctx).pop(false),
                                                          child: const Text('Annuler'),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () => Navigator.of(dctx).pop(true),
                                                          child: const Text('Effacer'),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                                if (ok == true) {
                                                  await mapProvider.panicWipeAllLocalData();
                                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                                }
                                              },
                                              child: const Text('Panic wipe'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
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
                                        : (mapProvider.weatherLoading ? Icons.cloud_sync_rounded : Icons.wb_sunny_rounded),
                                    size: 18,
                                    color: mapProvider.weatherError != null
                                        ? const Color(0xFFB55A5A)
                                        : (mapProvider.weatherLoading ? const Color(0xFF4A90A0) : const Color(0xFFFFC56E)),
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
                                  if (mapProvider.isOnline == false) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      'Offline',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black.withOpacity(0.55),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (mapProvider.selectedRouteWeatherSample != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(_glassRadius),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: _glassDecoration(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Builder(
                                      builder: (context) {
                                        final s = mapProvider.selectedRouteWeatherSample!;
                                        final t = s.snapshot.apparentTemperature.isFinite ? s.snapshot.apparentTemperature : s.snapshot.temperature;
                                        final rain = s.snapshot.precipitation;
                                        final wind = s.snapshot.windSpeed;
                                        final confPct = (s.confidence * 100).round();
                                        final hh = s.eta.toLocal().hour.toString().padLeft(2, '0');
                                        final mm = s.eta.toLocal().minute.toString().padLeft(2, '0');
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Point météo • ETA $hh:$mm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 4),
                                            Text(
                                              'T ${t.toStringAsFixed(0)}°C • pluie ${rain.toStringAsFixed(1)} mm • vent ${wind.toStringAsFixed(1)} m/s • conf $confPct%',
                                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () => mapProvider.clearSelectedRouteWeatherSample(),
                                    child: const Icon(Icons.close_rounded, size: 18, color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
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
                // Routing controls
                Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_glassRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: _glassDecoration(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              mapProvider.routingLoading
                                  ? 'Route…'
                                  : (mapProvider.routingError != null
                                      ? 'Route indisponible'
                                      : (mapProvider.routeVariants.isEmpty
                                          ? 'Long-press: départ puis arrivée'
                                          : 'Variante')),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            if (mapProvider.routeVariants.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              _RouteChip(
                                label: 'Rapide',
                                selected: mapProvider.selectedVariant.name == 'fast',
                                onTap: () => mapProvider.selectRouteVariant(RouteVariantKind.fast),
                              ),
                              const SizedBox(width: 6),
                              _RouteChip(
                                label: 'Sûre',
                                selected: mapProvider.selectedVariant.name == 'safe',
                                onTap: () => mapProvider.selectRouteVariant(RouteVariantKind.safe),
                              ),
                              const SizedBox(width: 6),
                              _RouteChip(
                                label: 'Calme',
                                selected: mapProvider.selectedVariant.name == 'scenic',
                                onTap: () => mapProvider.selectRouteVariant(RouteVariantKind.scenic),
                              ),
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () => mapProvider.clearRoute(),
                                child: const Icon(Icons.close_rounded, size: 18, color: Colors.black54),
                              ),
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () async {
                                  final selected = mapProvider.currentRouteExplanation;
                                  if (selected == null) return;
                                  final all = mapProvider.routeExplanations;
                                  await showModalBottomSheet<void>(
                                    context: context,
                                    showDragHandle: true,
                                    builder: (ctx) {
                                      final entries = all.entries.toList();
                                      entries.sort((a, b) => a.key.index.compareTo(b.key.index));

                                      return SafeArea(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Pourquoi cette route ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                              const SizedBox(height: 10),
                                              Text(selected.headline, style: const TextStyle(fontWeight: FontWeight.w700)),
                                              if (selected.caveat != null) ...[
                                                const SizedBox(height: 6),
                                                Text(selected.caveat!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                              ],
                                              const SizedBox(height: 12),
                                              if (selected.factors.isEmpty)
                                                const Text('Aucun facteur dominant détecté.', style: TextStyle(color: Colors.black54))
                                              else
                                                ...selected.factors.map((f) {
                                                  return Padding(
                                                    padding: const EdgeInsets.only(bottom: 8),
                                                    child: Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Container(
                                                          width: 8,
                                                          height: 8,
                                                          margin: const EdgeInsets.only(top: 6),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF4A90A0).withOpacity(0.75),
                                                            shape: BoxShape.circle,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 10),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(f.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                                              const SizedBox(height: 2),
                                                              Text(f.detail, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                              const SizedBox(height: 12),
                                              const Text('Comparaison rapide', style: TextStyle(fontWeight: FontWeight.w800)),
                                              const SizedBox(height: 8),
                                              ...entries.map((e) {
                                                final ex = e.value;
                                                final label = e.key == RouteVariantKind.fast
                                                    ? 'Rapide'
                                                    : (e.key == RouteVariantKind.safe ? 'Sûre' : 'Calme');
                                                final selectedMark = e.key == mapProvider.selectedVariant ? ' • sélectionnée' : '';
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 6),
                                                  child: Text(
                                                    '$label$selectedMark — vent ${ex.metrics.avgWind.toStringAsFixed(1)} m/s, pluie ~${ex.metrics.rainKm.toStringAsFixed(1)} km, conf ${(ex.metrics.avgConfidence * 100).round()}%',
                                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                                child: Text(
                                  'Pourquoi ?'.toUpperCase(),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF4A90A0)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                if (mapProvider.routingError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_glassRadius),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: _glassDecoration(),
                            child: Text(
                              mapProvider.routingError!,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7A2D2D)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (mapProvider.routeExplanation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_glassRadius),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: _glassDecoration(opacity: 0.54),
                            child: Text(
                              mapProvider.routeExplanation!,
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

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
                    onLongPress: mapProvider.pmtilesEnabled
                        ? () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) {
                                return AlertDialog(
                                  title: const Text('Supprimer le pack offline ?'),
                                  content: const Text('Le pack PMTiles sera supprimé de l’appareil.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: const Text('Annuler'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(true),
                                      child: const Text('Supprimer'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (ok == true) {
                              await mapProvider.uninstallCurrentPmtilesPack();
                            }
                          }
                        : null,
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
                    onLongPress: () async {
                      final packs = await mapProvider.listOfflinePacks();
                      if (!context.mounted) return;

                      await showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (ctx) {
                          return SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Packs offline',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 12),
                                  if (packs.isEmpty)
                                    const Text(
                                      'Aucun pack installé.',
                                      style: TextStyle(color: Colors.black54),
                                    )
                                  else
                                    Flexible(
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: packs.length,
                                        separatorBuilder: (_, __) => const Divider(height: 16),
                                        itemBuilder: (c, i) {
                                          final p = packs[i];
                                          return Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      p.id,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '${p.type.name} • ${_formatBytes(p.sizeBytes)}',
                                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              IconButton(
                                                onPressed: () async {
                                                  final ok = await showDialog<bool>(
                                                    context: ctx,
                                                    builder: (dctx) {
                                                      return AlertDialog(
                                                        title: const Text('Supprimer ce pack ?'),
                                                        content: Text(p.id),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(dctx).pop(false),
                                                            child: const Text('Annuler'),
                                                          ),
                                                          TextButton(
                                                            onPressed: () => Navigator.of(dctx).pop(true),
                                                            child: const Text('Supprimer'),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  );
                                                  if (ok == true) {
                                                    await mapProvider.uninstallOfflinePackById(p.id);
                                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                                  }
                                                },
                                                icon: const Icon(Icons.delete_outline_rounded),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
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
