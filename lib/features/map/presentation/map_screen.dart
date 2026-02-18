import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import 'package:app/providers/map_provider.dart';
import 'package:app/providers/app_settings_provider.dart';
import 'package:app/providers/connectivity_provider.dart';
import 'package:app/providers/location_provider.dart';
import 'package:app/providers/weather_provider.dart';
import 'package:app/providers/routing_provider.dart';
import 'package:app/providers/offline_provider.dart';
import 'package:app/services/analytics_service.dart';
import 'package:app/services/route_compare_service.dart';
import 'package:app/services/routing_models.dart';
import 'package:app/ui/horizon_bottom_sheet.dart';
import 'package:app/ui/horizon_breakpoints.dart';
import 'package:app/ui/horizon_card.dart';
import 'package:app/ui/horizon_chip.dart';
import 'package:app/widgets/horizon_map.dart';

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

String _formatDurationFromSeconds(double seconds) {
  final total = seconds.isFinite ? seconds.round() : 0;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  if (h <= 0) return '${m} min';
  return '${h} h ${m.toString().padLeft(2, '0')}';
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
    return Semantics(
      button: true,
      selected: selected,
      label: 'Variante $label${selected ? ', sélectionnée' : ''}',
      child: HorizonChip(
        label: label,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const _glassRadius = 22.0;

  ConnectivityProvider? _connectivity;
  VoidCallback? _connectivityListener;
  WeatherProvider? _weather;
  RoutingProvider? _routing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = Provider.of<AppSettingsProvider>(context, listen: false);
      unawaited(s.load().then((_) {
        if (!mounted) return;
        final map = Provider.of<MapProvider>(context, listen: false);
        map.syncNotificationsEnabledFromSettings(s.notificationsEnabled);
      }));

      final weather = Provider.of<WeatherProvider>(context, listen: false);
      _weather = weather;

      final routing = Provider.of<RoutingProvider>(context, listen: false);
      _routing = routing;

      final conn = Provider.of<ConnectivityProvider>(context, listen: false);
      _connectivity = conn;
      _connectivityListener = () {
        final map = Provider.of<MapProvider>(context, listen: false);
        map.syncIsOnlineFromConnectivity(conn.isOnline);
        weather.syncIsOnline(conn.isOnline);
        routing.syncIsOnline(conn.isOnline);
      };
      conn.addListener(_connectivityListener!);
      _connectivityListener!();
    });
  }

  @override
  void dispose() {
    final conn = _connectivity;
    final listener = _connectivityListener;
    if (conn != null && listener != null) {
      conn.removeListener(listener);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = Provider.of<MapProvider>(context, listen: false);
    final fg = state == AppLifecycleState.resumed;
    p.setAppInForeground(fg);

    final w = _weather;
    if (w != null) {
      w.syncAppInForeground(fg);
    }

    final r = _routing;
    if (r != null) {
      r.syncAppInForeground(fg);
    }
  }

  BoxDecoration _glassDecoration({double opacity = 0.62}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return BoxDecoration(
      color: scheme.surface.withOpacity(opacity),
      borderRadius: BorderRadius.circular(_glassRadius),
      border: Border.all(color: scheme.outlineVariant.withOpacity(theme.brightness == Brightness.dark ? 0.22 : 0.32)),
      boxShadow: [
        BoxShadow(
          color: scheme.shadow.withOpacity(theme.brightness == Brightness.dark ? 0.22 : 0.06),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  Future<void> _recenterOnUser(MapProvider mapProvider) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Localisation limitée sur Web. Autorise la permission navigateur puis réessaie.')),
      );
      return;
    }

    try {
      final loc = Provider.of<LocationProvider>(context, listen: false);
      final position = await loc.getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);
      mapProvider.centerOnUser(target);
      final weather = Provider.of<WeatherProvider>(context, listen: false);
      unawaited(weather.refreshWeatherAt(target, userInitiated: true));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de récupérer la position. Vérifie les permissions et le GPS.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = Provider.of<MapProvider>(context);
    final settings = Provider.of<AppSettingsProvider>(context);
    final weather = Provider.of<WeatherProvider>(context);
    final routing = Provider.of<RoutingProvider>(context);
    final offline = Provider.of<OfflineProvider>(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurfaceStrong = scheme.onSurface.withOpacity(0.88);
    final onSurfaceMuted = scheme.onSurface.withOpacity(0.60);
    final onSurfaceSubtle = scheme.onSurface.withOpacity(0.55);
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
              weather.setController(controller);
              routing.setController(controller);
              offline.setController(controller);
            },
          ),
          if (!mapProvider.isStyleLoaded)
            const Center(
              child: CircularProgressIndicator(),
            ),
          Positioned(
            top: 60,
            left: edgeInset,
            right: edgeInset,
            child: Center(
              child: Hero(
                tag: 'status-pill',
                child: Material(
                  color: scheme.surface.withOpacity(0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onLongPress: () async {
                          final report = await mapProvider.computeLocalDataReport();
                          if (!context.mounted) return;
                          await showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: false,
                            builder: (ctx) {
                              final theme = Theme.of(ctx);
                              final scheme = theme.colorScheme;
                              final muted = scheme.onSurface.withOpacity(0.60);
                              final textTheme = theme.textTheme;
                              return HorizonBottomSheet(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Confiance & confidentialité',
                                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Thème',
                                      style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 8),
                                    Semantics(
                                      label: 'Sélection du thème',
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: SegmentedButton<AppThemeMode>(
                                          segments: const [
                                            ButtonSegment(value: AppThemeMode.system, label: Text('Système'), icon: Icon(Icons.settings_suggest_outlined)),
                                            ButtonSegment(value: AppThemeMode.light, label: Text('Clair'), icon: Icon(Icons.light_mode_outlined)),
                                            ButtonSegment(value: AppThemeMode.dark, label: Text('Sombre'), icon: Icon(Icons.dark_mode_outlined)),
                                          ],
                                          selected: <AppThemeMode>{settings.appThemeMode},
                                          onSelectionChanged: (s) {
                                            final next = s.isEmpty ? AppThemeMode.system : s.first;
                                            unawaited(settings.setAppThemeMode(next));
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Mode économie batterie',
                                            style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        Switch(
                                          value: mapProvider.lowPowerMode,
                                          onChanged: (v) {
                                            mapProvider.setLowPowerMode(v);
                                            weather.syncLowPowerMode(v);
                                            routing.syncLowPowerMode(v);
                                          },
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Analytics anonymes (opt-in)',
                                            style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        Switch(
                                          value: settings.analyticsSettings.level == AnalyticsLevel.anonymous,
                                          onChanged: (v) => settings.setAnalyticsLevel(v ? AnalyticsLevel.anonymous : AnalyticsLevel.off),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Notifications (opt-in)',
                                            style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        Switch(
                                          value: settings.notificationsEnabled,
                                          onChanged: (v) {
                                            unawaited(settings.setNotificationsEnabled(v).then((_) {
                                              mapProvider.syncNotificationsEnabledFromSettings(settings.notificationsEnabled);
                                              routing.syncNotificationsEnabledFromSettings(settings.notificationsEnabled);
                                            }));
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Stockage sécurisé : ${_formatBytes(report.secureStoreBytes)}', style: textTheme.bodySmall),
                                    Text('Cache itinéraires (legacy) : ${_formatBytes(report.routeCacheBytes)}', style: textTheme.bodySmall),
                                    Text('Cache météo (legacy) : ${_formatBytes(report.weatherCacheBytes)}', style: textTheme.bodySmall),
                                    Text('Packs offline : ${_formatBytes(report.offlinePacksBytes)}', style: textTheme.bodySmall),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Total : ${_formatBytes(report.totalBytes)}',
                                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'HORIZON fonctionne sans compte. Les données restent sur l’appareil.\nLong-press ici pour gérer/effacer rapidement.',
                                      style: textTheme.bodySmall?.copyWith(color: muted),
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
                                                        child: SelectableText(
                                                          json,
                                                          style: Theme.of(ctx).textTheme.bodySmall,
                                                        ),
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
                                                        child: SelectableText(
                                                          json ?? 'Aucun événement.',
                                                          style: Theme.of(ctx).textTheme.bodySmall,
                                                        ),
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
                              );
                            },
                          );
                        },
                        child: HorizonCard(
                          blur: false,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          onTap: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: false,
                              builder: (ctx) {
                                final theme = Theme.of(ctx);
                                final scheme = theme.colorScheme;
                                final muted = scheme.onSurface.withOpacity(0.60);
                                final body = scheme.onSurface.withOpacity(0.88);
                                final textTheme = theme.textTheme;

                                final decision = weather.weatherDecision;
                                final loading = weather.weatherLoading;
                                final error = weather.weatherError;
                                final offline = mapProvider.isOnline == false;

                                String title;
                                if (error != null) {
                                  title = 'Météo indisponible';
                                } else if (loading || decision == null) {
                                  title = 'Météo…';
                                } else {
                                  title = 'Météo locale';
                                }

                                Widget content;
                                if (error != null) {
                                  content = Text(
                                    error,
                                    style: textTheme.bodySmall?.copyWith(color: muted),
                                  );
                                } else if (loading || decision == null) {
                                  content = Text(
                                    offline ? 'Calcul local (offline)…' : 'Chargement…',
                                    style: textTheme.bodySmall?.copyWith(color: muted),
                                  );
                                } else {
                                  final now = decision.now;
                                  final t = now.apparentTemperature.isFinite ? now.apparentTemperature : now.temperature;
                                  final confPct = (decision.confidence * 100).round();
                                  final confLabel = weather.currentWeatherReliabilityLabel;
                                  content = Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${t.toStringAsFixed(0)}°C',
                                        style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: body, letterSpacing: -0.6),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'vent ${_msToKmh(now.windSpeed).toStringAsFixed(0)} km/h  •  pluie ${now.precipitation.toStringAsFixed(1)} mm',
                                        style: textTheme.bodySmall?.copyWith(color: body),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'confort ${decision.comfortScore.toStringAsFixed(1)}/10  •  confiance $confPct%${confLabel == null ? '' : ' ($confLabel)'}',
                                        style: textTheme.bodySmall?.copyWith(color: muted),
                                      ),
                                      if (offline) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'offline',
                                          style: textTheme.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ],
                                  );
                                }

                                return HorizonBottomSheet(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(height: 12),
                                      content,
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: HorizonTokens.sage.withOpacity(0.85),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                weather.weatherError != null
                                    ? Icons.cloud_off_rounded
                                    : (weather.weatherLoading ? Icons.cloud_sync_rounded : Icons.wb_sunny_rounded),
                                size: 18,
                                color: weather.weatherError != null
                                    ? HorizonTokens.terracotta
                                    : (weather.weatherLoading ? scheme.primary : HorizonTokens.sand),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      weather.weatherError != null
                                          ? 'Météo indisponible'
                                          : (weather.weatherDecision == null ? 'Météo…' : '${weather.weatherDecision!.now.temperature.round()}°C'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.4,
                                            color: onSurfaceStrong,
                                          ),
                                    ),
                                    if (weather.weatherDecision != null && weather.weatherError == null)
                                      Text(
                                        'confort ${weather.weatherDecision!.comfortScore.toStringAsFixed(1)}/10  •  conf ${(weather.weatherDecision!.confidence * 100).round()}%'
                                        '${mapProvider.isOnline == false ? '  •  offline' : ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: onSurfaceMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      )
                                    else if (mapProvider.isOnline == false)
                                      Text(
                                        'offline',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: onSurfaceMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.chevron_right_rounded, size: 18, color: onSurfaceMuted),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () async {
                                  await showModalBottomSheet<void>(
                                    context: context,
                                    showDragHandle: false,
                                    builder: (ctx) {
                                      final theme = Theme.of(ctx);
                                      final scheme = theme.colorScheme;
                                      final muted = scheme.onSurface.withOpacity(0.60);
                                      final textTheme = theme.textTheme;
                                      return HorizonBottomSheet(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Couches météo (expert)',
                                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                            ),
                                            if (kIsWeb) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                'Non disponible sur Web pour le moment.',
                                                style: textTheme.bodySmall?.copyWith(color: muted),
                                              ),
                                            ],
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Mode expert',
                                                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                                Switch(
                                                  value: weather.expertWeatherMode,
                                                  onChanged: kIsWeb ? null : (v) => weather.setExpertWeatherMode(v),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Vent',
                                                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                                Switch(
                                                  value: weather.expertWindLayer,
                                                  onChanged: (!kIsWeb && weather.expertWeatherMode) ? (v) => weather.setExpertWindLayer(v) : null,
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Pluie',
                                                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                                Switch(
                                                  value: weather.expertRainLayer,
                                                  onChanged: (!kIsWeb && weather.expertWeatherMode) ? (v) => weather.setExpertRainLayer(v) : null,
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Nuages',
                                                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                                Switch(
                                                  value: weather.expertCloudLayer,
                                                  onChanged: (!kIsWeb && weather.expertWeatherMode) ? (v) => weather.setExpertCloudLayer(v) : null,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Ces couches restent locales et sont contextualisées par l’itinéraire quand il existe.',
                                              style: textTheme.bodySmall?.copyWith(color: muted),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                                child: Tooltip(
                                  message: 'Couches météo',
                                  child: Semantics(
                                    button: true,
                                    label: 'Ouvrir les couches météo',
                                    child: Icon(
                                      Icons.layers_outlined,
                                      size: 18,
                                      color: onSurfaceMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (routing.routeVariants.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final theme = Theme.of(context);
                            final scheme = theme.colorScheme;
                            final onSurfaceStrong = scheme.onSurface.withOpacity(0.88);
                            final onSurfaceMuted = scheme.onSurface.withOpacity(0.60);

                            final variant = routing.routeVariants.firstWhere(
                              (v) => v.kind == routing.selectedVariant,
                              orElse: () => routing.routeVariants.first,
                            );
                            final ex = routing.currentRouteExplanation;

                            final title = variant.kind == RouteVariantKind.fast
                                ? 'Route rapide'
                                : (variant.kind == RouteVariantKind.safe
                                    ? 'Route sûre'
                                    : (variant.kind == RouteVariantKind.scenic
                                        ? 'Route calme'
                                        : (variant.kind == RouteVariantKind.imported ? 'Route GPX' : 'Route')));

                            final distance = '${variant.lengthKm.toStringAsFixed(1)} km';
                            final duration = _formatDurationFromSeconds(variant.timeSeconds);

                            String? line2;
                            if (ex != null && ex.metrics.avgConfidence > 0) {
                              final wind = _msToKmh(ex.metrics.avgWind).toStringAsFixed(0);
                              final rain = ex.metrics.rainKm.toStringAsFixed(1);
                              final conf = (ex.metrics.avgConfidence * 100).round();
                              final minComfort = ex.metrics.minComfort.toStringAsFixed(1);
                              line2 = 'min confort $minComfort/10  •  conf $conf%  •  pluie ~${rain} km  •  vent ${wind} km/h';
                            }

                            return HorizonCard(
                              blur: false,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              onTap: () async {
                                final selected = ex;
                                if (selected == null) return;

                                await showModalBottomSheet<void>(
                                  context: context,
                                  showDragHandle: false,
                                  builder: (ctx) {
                                    final theme = Theme.of(ctx);
                                    final scheme = theme.colorScheme;
                                    final muted = scheme.onSurface.withOpacity(0.60);
                                    final body = scheme.onSurface.withOpacity(0.88);
                                    final textTheme = theme.textTheme;

                                    final windKmh = _msToKmh(selected.metrics.avgWind).toStringAsFixed(0);
                                    final rainKm = selected.metrics.rainKm.toStringAsFixed(1);
                                    final conf = (selected.metrics.avgConfidence * 100).round();
                                    final confLabel = mapProvider.confidenceLabel(selected.metrics.avgConfidence);
                                    final minComfort = selected.metrics.minComfort.toStringAsFixed(1);

                                    return HorizonBottomSheet(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Résumé itinéraire',
                                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            title,
                                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: body),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$distance  •  $duration',
                                            style: textTheme.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            selected.headline,
                                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: body),
                                          ),
                                          if (selected.caveat != null) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              selected.caveat!,
                                              style: textTheme.bodySmall?.copyWith(color: muted),
                                            ),
                                          ],
                                          const SizedBox(height: 12),
                                          Text(
                                            'Min confort $minComfort/10  •  Pluie ~${rainKm} km  •  Vent ${windKmh} km/h',
                                            style: textTheme.bodySmall?.copyWith(color: body),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Fiabilité : $confLabel (confiance $conf%)',
                                            style: textTheme.bodySmall?.copyWith(color: muted),
                                          ),
                                          if (selected.factors.isNotEmpty) ...[
                                            const SizedBox(height: 14),
                                            Text(
                                              'Facteurs dominants',
                                              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: body),
                                            ),
                                            const SizedBox(height: 8),
                                            ...selected.factors.map((f) {
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 10),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      f.title,
                                                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: body),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      f.detail,
                                                      style: textTheme.bodySmall?.copyWith(color: muted),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.2,
                                            color: onSurfaceStrong,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(Icons.chevron_right_rounded, size: 18, color: onSurfaceMuted),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$distance  •  $duration',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: onSurfaceMuted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (line2 != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      line2,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: onSurfaceStrong,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: edgeInset,
            right: edgeInset,
            child: Builder(
              builder: (context) {
                Widget routingControls = Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_glassRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: _glassDecoration(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      String title;
                                      String? subtitle;

                                      if (routing.routingLoading) {
                                        title = 'Route…';
                                      } else if (routing.routingError != null) {
                                        title = 'Route indisponible';
                                      } else if (routing.routeVariants.isEmpty) {
                                        title = 'Itinéraire';
                                        subtitle = 'Long-press: départ puis arrivée';
                                      } else if (routing.selectedVariant == RouteVariantKind.imported && routing.gpxRouteName != null) {
                                        title = 'GPX';
                                        subtitle = routing.gpxRouteName;
                                      } else {
                                        title = 'Variante';
                                        subtitle = routing.selectedVariant == RouteVariantKind.fast
                                            ? 'Rapide'
                                            : (routing.selectedVariant == RouteVariantKind.safe
                                                ? 'Sûre'
                                                : (routing.selectedVariant == RouteVariantKind.scenic
                                                    ? 'Calme'
                                                    : (routing.selectedVariant == RouteVariantKind.imported ? 'GPX' : null)));
                                      }

                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: -0.2,
                                                  color: onSurfaceStrong,
                                                ),
                                          ),
                                          if (subtitle != null)
                                            Text(
                                              subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color: onSurfaceMuted,
                                                  ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                if (routing.routeVariants.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () => routing.clearRoute(),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      child: Tooltip(
                                        message: 'Effacer l’itinéraire',
                                        child: Semantics(
                                          button: true,
                                          label: 'Effacer l’itinéraire',
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: onSurfaceMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  TextButton(
                                    onPressed: () async {
                                      final selected = routing.currentRouteExplanation;
                                      if (selected == null) return;
                                      final all = routing.routeExplanations;
                                      await showModalBottomSheet<void>(
                                        context: context,
                                        showDragHandle: false,
                                        builder: (ctx) {
                                          final theme = Theme.of(ctx);
                                          final entries = all.entries.toList();
                                          entries.sort((a, b) => a.key.index.compareTo(b.key.index));

                                          final scheme = theme.colorScheme;
                                          final muted = scheme.onSurface.withOpacity(0.60);
                                          final body = scheme.onSurface.withOpacity(0.88);
                                          final textTheme = theme.textTheme;

                                          return HorizonBottomSheet(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Pourquoi cette route ?',
                                                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  selected.headline,
                                                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                                ),
                                                if (selected.caveat != null) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    selected.caveat!,
                                                    style: textTheme.bodySmall?.copyWith(color: muted),
                                                  ),
                                                ],
                                                if (selected.metrics.avgConfidence > 0) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'Fiabilité : ${routing.confidenceLabel(selected.metrics.avgConfidence)} (confiance ${(selected.metrics.avgConfidence * 100).round()}%)',
                                                    style: textTheme.bodySmall?.copyWith(color: muted),
                                                  ),
                                                ],
                                                const SizedBox(height: 12),
                                                if (selected.factors.isEmpty)
                                                  Text('Aucun facteur dominant détecté.', style: textTheme.bodySmall?.copyWith(color: muted))
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
                                                                Text(
                                                                  f.title,
                                                                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                                                                ),
                                                                const SizedBox(height: 2),
                                                                Text(
                                                                  f.detail,
                                                                  style: textTheme.bodySmall?.copyWith(color: body),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }),
                                                const SizedBox(height: 12),
                                                Text(
                                                  'Comparaison rapide',
                                                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                                                ),
                                                const SizedBox(height: 8),
                                                ...entries.map((e) {
                                                  final ex = e.value;
                                                  final label = e.key == RouteVariantKind.fast
                                                      ? 'Rapide'
                                                      : (e.key == RouteVariantKind.safe
                                                          ? 'Sûre'
                                                          : (e.key == RouteVariantKind.scenic ? 'Calme' : 'GPX'));
                                                  final selectedMark = e.key == routing.selectedVariant ? ' • sélectionnée' : '';
                                                  return Padding(
                                                    padding: const EdgeInsets.only(bottom: 6),
                                                    child: Text(
                                                      '$label$selectedMark — vent ${_msToKmh(ex.metrics.avgWind).toStringAsFixed(0)} km/h, pluie ~${ex.metrics.rainKm.toStringAsFixed(1)} km, conf ${(ex.metrics.avgConfidence * 100).round()}%',
                                                      style: textTheme.bodySmall?.copyWith(color: body),
                                                    ),
                                                  );
                                                }),
                                                const SizedBox(height: 12),
                                                FutureBuilder<DepartureWindowRecommendation?>(
                                                  future: routing.recommendDepartureWindowForSelectedVariant(),
                                                  builder: (context, snap) {
                                                    final rec = snap.data;
                                                    if (snap.connectionState != ConnectionState.done) {
                                                      return Text('Calcul…', style: textTheme.bodySmall?.copyWith(color: muted));
                                                    }
                                                    if (rec == null) return const SizedBox.shrink();

                                                    final when = DateTime.now().add(rec.bestOffset);
                                                    final hh = when.hour.toString().padLeft(2, '0');
                                                    final mm = when.minute.toString().padLeft(2, '0');
                                                    return Text(
                                                      'Fenêtre optimale : $hh:$mm (${rec.rationale})',
                                                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    child: Tooltip(
                                      message: 'Pourquoi cette route ?',
                                      child: Semantics(
                                        button: true,
                                        label: 'Afficher pourquoi cette route est recommandée',
                                        child: Text(
                                          'Pourquoi ?'.toUpperCase(),
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                color: scheme.primary,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (routing.routeVariants.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (routing.routeVariants.any((v) => v.kind == RouteVariantKind.fast))
                                    _RouteChip(
                                      label: 'Rapide',
                                      selected: routing.selectedVariant == RouteVariantKind.fast,
                                      onTap: () => routing.selectRouteVariant(RouteVariantKind.fast),
                                    ),
                                  if (routing.routeVariants.any((v) => v.kind == RouteVariantKind.safe))
                                    _RouteChip(
                                      label: 'Sûre',
                                      selected: routing.selectedVariant == RouteVariantKind.safe,
                                      onTap: () => routing.selectRouteVariant(RouteVariantKind.safe),
                                    ),
                                  if (routing.routeVariants.any((v) => v.kind == RouteVariantKind.scenic))
                                    _RouteChip(
                                      label: 'Calme',
                                      selected: routing.selectedVariant == RouteVariantKind.scenic,
                                      onTap: () => routing.selectRouteVariant(RouteVariantKind.scenic),
                                    ),
                                  if (routing.routeVariants.any((v) => v.kind == RouteVariantKind.imported))
                                    _RouteChip(
                                      label: 'GPX',
                                      selected: routing.selectedVariant == RouteVariantKind.imported,
                                      onTap: () => routing.selectRouteVariant(RouteVariantKind.imported),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                Widget routingMessages = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (routing.routingError != null)
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
                                  routing.routingError!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HorizonTokens.terracotta),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (routing.gpxImportLoading || routing.gpxImportError != null)
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
                                  routing.gpxImportLoading ? 'Import…' : (routing.gpxImportError ?? 'Import GPX'),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: routing.gpxImportError == null ? onSurfaceStrong : HorizonTokens.terracotta,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (routing.routeExplanation != null)
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
                                  routing.routeExplanation!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: onSurfaceStrong,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );

                Widget actionColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: FloatingActionButton.small(
                          heroTag: 'pmtiles-pack',
                          onPressed: kIsWeb
                              ? null
                              : () {
                                  if (offline.pmtilesEnabled) {
                                    offline.disablePmtilesPack();
                                  } else {
                                    offline.enablePmtilesPack(
                                      url: 'https://r2-public.protomaps.com/protomaps-sample-datasets/cb_2018_us_zcta510_500k.pmtiles',
                                      fileName: 'horizon.pmtiles',
                                      regionNameForUi: 'Pack offline',
                                    );
                                  }
                                },
                          onLongPress: (!kIsWeb && offline.pmtilesEnabled)
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
                                    await offline.uninstallCurrentPmtilesPack();
                                  }
                                }
                              : null,
                          child: Tooltip(
                            message: kIsWeb
                                ? 'Pack offline indisponible sur Web'
                                : (offline.pmtilesEnabled ? 'Désactiver le pack offline' : 'Activer le pack offline'),
                            child: Semantics(
                              button: true,
                              label: kIsWeb
                                  ? 'Pack offline indisponible sur Web'
                                  : (offline.pmtilesEnabled ? 'Désactiver le pack offline' : 'Activer le pack offline'),
                              child: Icon(
                                offline.pmtilesEnabled ? Icons.storage_rounded : Icons.storage_outlined,
                                color: onSurfaceStrong,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
                        child: FloatingActionButton.small(
                          heroTag: 'offline-download',
                          onPressed: kIsWeb
                              ? null
                              : () {
                                  offline.downloadVisibleRegion(regionName: 'Visible region');
                                },
                          onLongPress: kIsWeb
                              ? null
                              : () async {
                                  final packs = await offline.listOfflinePacks();
                                  if (!context.mounted) return;

                                  await showModalBottomSheet<void>(
                                    context: context,
                                    showDragHandle: false,
                                    builder: (ctx) {
                                      final theme = Theme.of(ctx);
                                      final scheme = theme.colorScheme;
                                      final onSurfaceMuted = scheme.onSurface.withOpacity(0.60);
                                      return HorizonBottomSheet(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Packs offline',
                                              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                            ),
                                            const SizedBox(height: 12),
                                            if (packs.isEmpty)
                                              Text(
                                                'Aucun pack installé.',
                                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                                      color: onSurfaceMuted,
                                                    ),
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
                                                                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                                              ),
                                                              const SizedBox(height: 4),
                                                              Text(
                                                                '${p.type.name} • ${_formatBytes(p.sizeBytes)}',
                                                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                                                  color: onSurfaceMuted,
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
                                                              await offline.uninstallOfflinePackById(p.id);
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
                                      );
                                    },
                                  );
                                },
                          child: Tooltip(
                            message: kIsWeb ? 'Offline indisponible sur Web' : 'Télécharger la région visible',
                            child: Semantics(
                              button: true,
                              label: kIsWeb ? 'Offline indisponible sur Web' : 'Télécharger la région visible',
                              child: Icon(
                                Icons.cloud_download_outlined,
                                color: onSurfaceStrong,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(4),
                        child: FloatingActionButton.small(
                          heroTag: 'recenter',
                          onPressed: () => _recenterOnUser(mapProvider),
                          child: Tooltip(
                            message: 'Me recentrer',
                            child: Semantics(
                              button: true,
                              label: 'Me recentrer',
                              child: Icon(
                                Icons.my_location,
                                color: onSurfaceStrong,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(5),
                        child: FloatingActionButton.small(
                          heroTag: 'import-gpx',
                          onPressed: () {
                            routing.importGpxRoute();
                          },
                          child: Tooltip(
                            message: 'Importer GPX',
                            child: Semantics(
                              button: true,
                              label: 'Importer GPX',
                              child: Icon(
                                Icons.file_open_outlined,
                                color: onSurfaceStrong,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(7),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: _glassDecoration(opacity: 0.85),
                        child: TextField(
                          semanticsLabel: 'Recherche de destination',
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Où allez-vous ?',
                            hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: onSurfaceSubtle,
                                ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: onSurfaceMuted,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                );

                Widget compactLayout = SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          routingControls,
                          routingMessages,
                          actionColumn,
                        ],
                      ),
                    ),
                  ),
                );

                Widget expandedLayout = SafeArea(
                  top: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              routingControls,
                              routingMessages,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.70,
                          ),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: actionColumn,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                return FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: HorizonResponsiveBuilder(
                    compact: (_) => compactLayout,
                    expanded: (_) => expandedLayout,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (offline.offlineDownloadProgress == null &&
              offline.offlineDownloadError == null &&
              offline.pmtilesProgress == null &&
              offline.pmtilesError == null)
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_glassRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Semantics(
                    container: true,
                    label: 'Progression offline',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: _glassDecoration(opacity: 0.78),
                      child: Row(
                        children: [
                          const Icon(Icons.offline_pin_outlined, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: offline.pmtilesError != null
                                ? Text(
                                    offline.pmtilesError!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                  )
                                : offline.offlineDownloadError != null
                                    ? Text(
                                        offline.offlineDownloadError!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            offline.pmtilesProgress != null ? 'Activation pack offline…' : 'Téléchargement offline…',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 6),
                                          LinearProgressIndicator(
                                            value: offline.pmtilesProgress ?? offline.offlineDownloadProgress,
                                            minHeight: 3,
                                            color: scheme.primary,
                                            backgroundColor: scheme.primary.withOpacity(0.18),
                                          ),
                                        ],
                                      ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () {
                              offline.clearOfflineDownloadState();
                              offline.clearPmtilesState();
                            },
                            icon: Tooltip(
                              message: 'Fermer',
                              child: Icon(Icons.close_rounded, color: scheme.onSurface.withOpacity(0.82), size: 18),
                            ),
                            label: 'Fermer l’état de téléchargement offline',
                            child: const Icon(Icons.close, size: 18),
                          ),
                          visualDensity: VisualDensity.compact,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
