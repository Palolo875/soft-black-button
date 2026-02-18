import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:app/providers/map_provider.dart';
import 'package:app/services/routing_models.dart';
import 'package:app/services/analytics_service.dart';
import 'package:app/services/route_compare_service.dart';
import 'package:app/widgets/horizon_map.dart';
import 'package:app/ui/horizon_theme.dart';
import 'package:app/ui/horizon_card.dart';
import 'package:app/ui/horizon_chip.dart';
import 'package:app/ui/horizon_bottom_sheet.dart';
import 'package:app/ui/horizon_breakpoints.dart';
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

double _msToKmh(double ms) => ms * 3.6;

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
    return HorizonChip(
      label: label,
      selected: selected,
      onTap: onTap,
    );
  }
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
      theme: HorizonTheme.light(),
      darkTheme: HorizonTheme.dark(),
      themeMode: ThemeMode.system,
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

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const _glassRadius = 22.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = Provider.of<MapProvider>(context, listen: false);
      unawaited(p.initTrustAndPerf());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = Provider.of<MapProvider>(context, listen: false);
    final fg = state == AppLifecycleState.resumed;
    p.setAppInForeground(fg);
  }

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
    final w = MediaQuery.sizeOf(context).width;
    final edgeInset = w >= HorizonBreakpoints.medium
        ? HorizonTokens.space32
        : (w >= HorizonBreakpoints.compact ? HorizonTokens.space24 : HorizonTokens.space20);

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
            left: edgeInset,
            right: edgeInset,
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
                              final theme = Theme.of(ctx);
                              final muted = theme.colorScheme.onSurface.withOpacity(0.60);
                              return SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Confiance & confidentialité', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          const Expanded(child: Text('Mode économie batterie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                          Switch(
                                            value: mapProvider.lowPowerMode,
                                            onChanged: (v) => mapProvider.setLowPowerMode(v),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          const Expanded(child: Text('Analytics anonymes (opt-in)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                          Switch(
                                            value: mapProvider.analyticsSettings.level == AnalyticsLevel.anonymous,
                                            onChanged: (v) => mapProvider.setAnalyticsLevel(v ? AnalyticsLevel.anonymous : AnalyticsLevel.off),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          const Expanded(child: Text('Notifications (opt-in)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                          Switch(
                                            value: mapProvider.notificationsEnabled,
                                            onChanged: (v) => mapProvider.setNotificationsEnabled(v),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Stockage sécurisé : ${_formatBytes(report.secureStoreBytes)}', style: const TextStyle(fontSize: 12)),
                                      Text('Cache itinéraires (legacy) : ${_formatBytes(report.routeCacheBytes)}', style: const TextStyle(fontSize: 12)),
                                      Text('Cache météo (legacy) : ${_formatBytes(report.weatherCacheBytes)}', style: const TextStyle(fontSize: 12)),
                                      Text('Packs offline : ${_formatBytes(report.offlinePacksBytes)}', style: const TextStyle(fontSize: 12)),
                                      const SizedBox(height: 8),
                                      Text('Total : ${_formatBytes(report.totalBytes)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 14),
                                      Text(
                                        'HORIZON fonctionne sans compte. Les données restent sur l’appareil.\nLong-press ici pour gérer/effacer rapidement.',
                                        style: TextStyle(fontSize: 12, color: muted),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () async {
                                                final json = await mapProvider.exportPerfMetricsJson();
                                                if (!ctx.mounted) return;
                                                await showDialog<void>(
                                                  context: ctx,
                                                  builder: (dctx) {
                                                    return AlertDialog(
                                                      title: const Text('Rapport perf (local)'),
                                                      content: SizedBox(
                                                        width: double.maxFinite,
                                                        child: SingleChildScrollView(
                                                          child: SelectableText(json, style: const TextStyle(fontSize: 11)),
                                                        ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.of(dctx).pop(),
                                                          child: const Text('Fermer'),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                              child: const Text('Perf'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () async {
                                                final json = await mapProvider.exportAnalyticsBufferJson();
                                                if (!ctx.mounted) return;
                                                await showDialog<void>(
                                                  context: ctx,
                                                  builder: (dctx) {
                                                    return AlertDialog(
                                                      title: const Text('Buffer analytics (local)'),
                                                      content: SizedBox(
                                                        width: double.maxFinite,
                                                        child: SingleChildScrollView(
                                                          child: SelectableText(json ?? 'Aucun événement.', style: const TextStyle(fontSize: 11)),
                                                        ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.of(dctx).pop(),
                                                          child: const Text('Fermer'),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                              child: const Text('Analytics'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
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
                                    Row(
                                      children: [
                                        const Expanded(child: Text('Analytics anonymes (opt-in)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                        Switch(
                                          value: mapProvider.analyticsSettings.level == AnalyticsLevel.anonymous,
                                          onChanged: (v) => mapProvider.setAnalyticsLevel(v ? AnalyticsLevel.anonymous : AnalyticsLevel.off),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Expanded(child: Text('Notifications (opt-in)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                        Switch(
                                          value: mapProvider.notificationsEnabled,
                                          onChanged: (v) => mapProvider.setNotificationsEnabled(v),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Stockage sécurisé : ${_formatBytes(report.secureStoreBytes)}', style: const TextStyle(fontSize: 12)),
                                    Text('Cache itinéraires (legacy) : ${_formatBytes(report.routeCacheBytes)}', style: const TextStyle(fontSize: 12)),
                                    Text('Cache météo (legacy) : ${_formatBytes(report.weatherCacheBytes)}', style: const TextStyle(fontSize: 12)),
                                    Text('Packs offline : ${_formatBytes(report.offlinePacksBytes)}', style: const TextStyle(fontSize: 12)),
                                    const SizedBox(height: 8),
                                    Text('Total : ${_formatBytes(report.totalBytes)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 14),
                                    Text(
                                      'HORIZON fonctionne sans compte. Les données restent sur l’appareil.\nLong-press ici pour gérer/effacer rapidement.',
                                      style: TextStyle(fontSize: 12, color: muted),
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () async {
                                              final json = await mapProvider.exportPerfMetricsJson();
                                              if (!ctx.mounted) return;
                                              await showDialog<void>(
                                                context: ctx,
                                                builder: (dctx) {
                                                  return AlertDialog(
                                                    title: const Text('Rapport perf (local)'),
                                                    content: SizedBox(
                                                      width: double.maxFinite,
                                                      child: SingleChildScrollView(
                                                        child: SelectableText(json, style: const TextStyle(fontSize: 11)),
                                                      ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.of(dctx).pop(),
                                                        child: const Text('Fermer'),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
                                            child: const Text('Perf'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () async {
                                              final json = await mapProvider.exportAnalyticsBufferJson();
                                              if (!ctx.mounted) return;
                                              await showDialog<void>(
                                                context: ctx,
                                                builder: (dctx) {
                                                  return AlertDialog(
                                                    title: const Text('Buffer analytics (local)'),
                                                    content: SizedBox(
                                                      width: double.maxFinite,
                                                      child: SingleChildScrollView(
                                                        child: SelectableText(json ?? 'Aucun événement.', style: const TextStyle(fontSize: 11)),
                                                      ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.of(dctx).pop(),
                                                        child: const Text('Fermer'),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
                                            child: const Text('Analytics'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
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
                        ),
                        child: HorizonCard(
                          blur: false,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
                                ),
                              ),
                              if (mapProvider.isOnline == false) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'Offline',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () async {
                                  await showModalBottomSheet<void>(
                                    context: context,
                                    showDragHandle: false,
                                    builder: (ctx) {
                                      final theme = Theme.of(ctx);
                                      final muted = theme.colorScheme.onSurface.withOpacity(0.60);
                                      return HorizonBottomSheet(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Couches météo (expert)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                const Expanded(child: Text('Mode expert', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                                Switch(
                                                  value: mapProvider.expertWeatherMode,
                                                  onChanged: (v) => mapProvider.setExpertWeatherMode(v),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                const Expanded(child: Text('Vent', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                                Switch(
                                                  value: mapProvider.expertWindLayer,
                                                  onChanged: mapProvider.expertWeatherMode ? (v) => mapProvider.setExpertWindLayer(v) : null,
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                const Expanded(child: Text('Pluie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                                Switch(
                                                  value: mapProvider.expertRainLayer,
                                                  onChanged: mapProvider.expertWeatherMode ? (v) => mapProvider.setExpertRainLayer(v) : null,
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                const Expanded(child: Text('Nuages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                                Switch(
                                                  value: mapProvider.expertCloudLayer,
                                                  onChanged: mapProvider.expertWeatherMode ? (v) => mapProvider.setExpertCloudLayer(v) : null,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Ces couches restent locales et sont contextualisées par l’itinéraire quand il existe.',
                                              style: TextStyle(fontSize: 12, color: muted),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                                child: Icon(
                                  Icons.layers_outlined,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60),
                                ),
                              ),
                            ],
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
                                        final relLabel = mapProvider.selectedSampleReliabilityLabel;
                                        final hh = s.eta.toLocal().hour.toString().padLeft(2, '0');
                                        final mm = s.eta.toLocal().minute.toString().padLeft(2, '0');
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Point météo • ETA $hh:$mm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 4),
                                            Text(
                                              'T ${t.toStringAsFixed(0)}°C • pluie ${rain.toStringAsFixed(1)} mm • vent ${_msToKmh(wind).toStringAsFixed(0)} km/h • conf $confPct%${relLabel == null ? '' : ' ($relLabel)'}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Vent relatif : ${s.relativeWindKind.name} • impact ${s.relativeWindImpact.toStringAsFixed(0)}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60),
                                              ),
                                            ),
                                            if (s.comfortBreakdown != null && s.comfortBreakdown!.contributions.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                'Impact : ${s.comfortBreakdown!.contributions.take(2).map((c) => '${c.label} ${c.delta.toStringAsFixed(1)}').join(' • ')}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60),
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () => mapProvider.clearSelectedRouteWeatherSample(),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60),
                                    ),
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
            left: edgeInset,
            right: edgeInset,
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
                                          : (mapProvider.selectedVariant == RouteVariantKind.imported && mapProvider.gpxRouteName != null
                                              ? 'GPX: ${mapProvider.gpxRouteName}'
                                              : 'Variante')),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
                              ),
                            ),
                            if (mapProvider.routeVariants.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              if (mapProvider.routeVariants.any((v) => v.kind == RouteVariantKind.fast)) ...[
                                _RouteChip(
                                  label: 'Rapide',
                                  selected: mapProvider.selectedVariant == RouteVariantKind.fast,
                                  onTap: () => mapProvider.selectRouteVariant(RouteVariantKind.fast),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (mapProvider.routeVariants.any((v) => v.kind == RouteVariantKind.safe)) ...[
                                _RouteChip(
                                  label: 'Sûre',
                                  selected: mapProvider.selectedVariant == RouteVariantKind.safe,
                                  onTap: () => mapProvider.selectRouteVariant(RouteVariantKind.safe),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (mapProvider.routeVariants.any((v) => v.kind == RouteVariantKind.scenic)) ...[
                                _RouteChip(
                                  label: 'Calme',
                                  selected: mapProvider.selectedVariant == RouteVariantKind.scenic,
                                  onTap: () => mapProvider.selectRouteVariant(RouteVariantKind.scenic),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (mapProvider.routeVariants.any((v) => v.kind == RouteVariantKind.imported)) ...[
                                _RouteChip(
                                  label: 'GPX',
                                  selected: mapProvider.selectedVariant == RouteVariantKind.imported,
                                  onTap: () => mapProvider.selectRouteVariant(RouteVariantKind.imported),
                                ),
                                const SizedBox(width: 6),
                              ],
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () => mapProvider.clearRoute(),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60),
                                ),
                              ),
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () async {
                                  final selected = mapProvider.currentRouteExplanation;
                                  if (selected == null) return;
                                  final all = mapProvider.routeExplanations;
                                  await showModalBottomSheet<void>(
                                    context: context,
                                    showDragHandle: false,
                                    builder: (ctx) {
                                      final theme = Theme.of(ctx);
                                      final entries = all.entries.toList();
                                      entries.sort((a, b) => a.key.index.compareTo(b.key.index));

                                      final muted = theme.colorScheme.onSurface.withOpacity(0.60);
                                      final body = theme.colorScheme.onSurface.withOpacity(0.88);

                                      return HorizonBottomSheet(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Pourquoi cette route ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 10),
                                            Text(selected.headline, style: const TextStyle(fontWeight: FontWeight.w700)),
                                            if (selected.caveat != null) ...[
                                              const SizedBox(height: 6),
                                              Text(selected.caveat!, style: TextStyle(fontSize: 12, color: muted)),
                                            ],
                                            if (selected.metrics.avgConfidence > 0) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                'Fiabilité : ${mapProvider.confidenceLabel(selected.metrics.avgConfidence)} (confiance ${(selected.metrics.avgConfidence * 100).round()}%)',
                                                style: TextStyle(fontSize: 12, color: muted),
                                              ),
                                            ],
                                            const SizedBox(height: 12),
                                            if (selected.factors.isEmpty)
                                              Text('Aucun facteur dominant détecté.', style: TextStyle(color: muted))
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
                                                          color: theme.colorScheme.primary.withOpacity(0.65),
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
                                                            Text(f.detail, style: TextStyle(fontSize: 12, color: body)),
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
                                                  : (e.key == RouteVariantKind.safe
                                                      ? 'Sûre'
                                                      : (e.key == RouteVariantKind.scenic ? 'Calme' : 'GPX'));
                                              final selectedMark = e.key == mapProvider.selectedVariant ? ' • sélectionnée' : '';
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 6),
                                                child: Text(
                                                  '$label$selectedMark — vent ${_msToKmh(ex.metrics.avgWind).toStringAsFixed(0)} km/h, pluie ~${ex.metrics.rainKm.toStringAsFixed(1)} km, conf ${(ex.metrics.avgConfidence * 100).round()}%',
                                                  style: TextStyle(fontSize: 12, color: body),
                                                ),
                                              );
                                            }),
                                            const SizedBox(height: 14),
                                            const Text('Comparer départs', style: TextStyle(fontWeight: FontWeight.w800)),
                                            const SizedBox(height: 8),
                                            FutureBuilder(
                                              future: mapProvider.compareDeparturesForSelectedVariant(),
                                              builder: (context, snap) {
                                                final data = snap.data;
                                                if (snap.connectionState != ConnectionState.done) {
                                                  return const Padding(
                                                    padding: EdgeInsets.symmetric(vertical: 10),
                                                    child: LinearProgressIndicator(minHeight: 3),
                                                  );
                                                }
                                                if (data == null || data.isEmpty) {
                                                  return Text('Indisponible.', style: TextStyle(fontSize: 12, color: muted));
                                                }

                                                  RouteDepartureComparison best = data.first;
                                                  double bestScore = -999;
                                                  for (final c in data) {
                                                    final score = c.avgComfort - (c.rainKm * 0.35);
                                                    if (score > bestScore) {
                                                      bestScore = score;
                                                      best = c;
                                                    }
                                                  }

                                                  String labelFor(Duration d) {
                                                    if (d == Duration.zero) return 'T0';
                                                    final m = d.inMinutes;
                                                    return 'T+$m';
                                                  }

                                                  String windLabel(String k) {
                                                    if (k == 'head') return 'face';
                                                    if (k == 'tail') return 'dos';
                                                    return 'latéral';
                                                  }

                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      ...data.map((c) {
                                                        final conf = (c.avgConfidence * 100).round();
                                                        return Padding(
                                                          padding: const EdgeInsets.only(bottom: 6),
                                                          child: Text(
                                                            '${labelFor(c.offset)} — confort ${c.avgComfort.toStringAsFixed(1)}/10 (min ${c.minComfort.toStringAsFixed(1)}), pluie ~${c.rainKm.toStringAsFixed(1)} km, vent ${windLabel(c.dominantWind.name)}, conf $conf%',
                                                            style: TextStyle(fontSize: 12, color: body),
                                                          ),
                                                        );
                                                      }),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        'Recommandation : ${labelFor(best.offset)} (estimé)',
                                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: body),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 10),
                                              FutureBuilder(
                                                future: mapProvider.recommendDepartureWindowForSelectedVariant(),
                                                builder: (context, snap) {
                                                  final rec = snap.data;
                                                  if (snap.connectionState != ConnectionState.done) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  if (rec == null) return const SizedBox.shrink();

                                                  final when = DateTime.now().add(rec.bestOffset);
                                                  final hh = when.hour.toString().padLeft(2, '0');
                                                  final mm = when.minute.toString().padLeft(2, '0');
                                                  return Text(
                                                    'Fenêtre optimale : $hh:$mm (${rec.rationale})',
                                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                                  );
                                                },
                                              ),
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

                if (mapProvider.gpxImportLoading || mapProvider.gpxImportError != null)
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
                              mapProvider.gpxImportLoading
                                  ? 'Import…'
                                  : (mapProvider.gpxImportError ?? 'Import GPX'),
                              style: TextStyle(
                                fontSize: 12,
                                color: mapProvider.gpxImportError == null
                                    ? Theme.of(context).colorScheme.onSurface.withOpacity(0.88)
                                    : const Color(0xFF7A2D2D),
                                fontWeight: FontWeight.w600,
                              ),
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
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88)),
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
                      color: mapProvider.pmtilesEnabled
                          ? Theme.of(context).colorScheme.onSurface.withOpacity(0.88)
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
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
                                    Text(
                                      'Aucun pack installé.',
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60)),
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
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60),
                                                      ),
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
                    child: Icon(
                      Icons.download_for_offline_outlined,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
                    ),
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

                // Import GPX (privacy-first)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FloatingActionButton.small(
                    heroTag: 'gpx-import',
                    onPressed: () {
                      mapProvider.importGpxRoute();
                    },
                    child: Icon(
                      Icons.upload_file_rounded,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
                    ),
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
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                            ),
                          ),
                          Text(
                            "+${mapProvider.timeOffset.toInt()}h",
                            style: const TextStyle(fontSize: 10, color: Color(0xFF4A90A0), fontWeight: FontWeight.w700),
                          ),
                          Text(
                            "+24h",
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                              fontWeight: FontWeight.w600,
                            ),
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
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                        fontSize: 16,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60),
                      ),
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
