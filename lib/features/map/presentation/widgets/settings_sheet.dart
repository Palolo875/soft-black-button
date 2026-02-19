import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import 'package:horizon/providers/app_settings_provider.dart';
import 'package:horizon/providers/home_today_provider.dart';
import 'package:horizon/providers/location_provider.dart';
import 'package:horizon/providers/mobility_provider.dart';
import 'package:horizon/providers/map_provider.dart';
import 'package:horizon/providers/weather_provider.dart';
import 'package:horizon/providers/routing_provider.dart';
import 'package:horizon/providers/trip_provider.dart';
import 'package:horizon/services/analytics_service.dart';
import 'package:horizon/services/home_today_store.dart';
import 'package:horizon/services/trip_models.dart';
import 'package:horizon/ui/horizon_bottom_sheet.dart';
import 'package:horizon/features/map/presentation/utils/format_utils.dart';
import 'package:horizon/core/mobility/travel_mode.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/theme_settings_store.dart';

/// Bottom sheet for privacy/settings/data management.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (_) => const SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.60);
    final textTheme = theme.textTheme;
    final settings = Provider.of<AppSettingsProvider>(context);
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final weather = Provider.of<WeatherProvider>(context, listen: false);
    final routing = Provider.of<RoutingProvider>(context, listen: false);
    final loc = Provider.of<LocationProvider>(context, listen: false);

    return HorizonBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confiance & confidentialité',
            style: textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Text(
            'Thème',
            style: textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Sélection du thème',
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text('Système'),
                    icon: Icon(Icons.settings_suggest_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text('Clair'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text('Sombre'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: <AppThemeMode>{settings.appThemeMode},
                onSelectionChanged: (s) {
                  final next =
                      s.isEmpty ? AppThemeMode.system : s.first;
                  unawaited(settings.setAppThemeMode(next));
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Consumer<MobilityProvider>(
            builder: (ctx, mobility, _) {
              final speedMps = mobility.speedMetersPerSecond;
              final speedKmh = msToKmh(speedMps);
              final hasOverride = mobility.speedOverrideMetersPerSecond != null;

              final minMps = switch (mobility.mode) {
                TravelMode.stay => 0.0,
                TravelMode.walking => 0.6,
                TravelMode.cycling => 2.0,
                TravelMode.car => 5.0,
                TravelMode.motorbike => 5.0,
              };
              final maxMps = switch (mobility.mode) {
                TravelMode.stay => 1.0,
                TravelMode.walking => 2.8,
                TravelMode.cycling => 12.0,
                TravelMode.car => 40.0,
                TravelMode.motorbike => 40.0,
              };

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mode',
                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<TravelMode>(
                      segments: const [
                        ButtonSegment(value: TravelMode.walking, label: Text('Marche')),
                        ButtonSegment(value: TravelMode.cycling, label: Text('Vélo')),
                        ButtonSegment(value: TravelMode.car, label: Text('Auto')),
                        ButtonSegment(value: TravelMode.motorbike, label: Text('Moto')),
                      ],
                      selected: <TravelMode>{mobility.mode},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        unawaited(mobility.setMode(s.first));
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Vitesse',
                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${speedKmh.toStringAsFixed(0)} km/h',
                          style: textTheme.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: hasOverride ? () => unawaited(mobility.setSpeedMetersPerSecond(null)) : null,
                        child: const Text('Auto'),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => unawaited(mobility.resetToDefaults()),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  Slider(
                    value: speedMps.clamp(minMps, maxMps),
                    min: minMps,
                    max: maxMps,
                    divisions: ((maxMps - minMps) / 0.5).round().clamp(1, 200),
                    onChanged: mobility.mode == TravelMode.stay
                        ? null
                        : (v) {
                            unawaited(mobility.setSpeedMetersPerSecond(v));
                          },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Consumer<HomeTodayProvider>(
            builder: (ctx, home, _) {
              final enabled = home.settings.enabled;
              final places = home.settings.places;
              final summary = home.summary;

              Future<void> addFromCurrentLocation() async {
                try {
                  await loc.ensurePermission();
                  final pos = await loc.getCurrentPosition();
                  if (!context.mounted) return;

                  final nameCtrl = TextEditingController(text: 'Maison');
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dctx) {
                      return AlertDialog(
                        title: const Text('Nouveau lieu'),
                        content: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Nom'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Ajouter'),
                          ),
                        ],
                      );
                    },
                  );
                  if (ok != true) return;
                  final name = nameCtrl.text.trim().isEmpty ? 'Lieu' : nameCtrl.text.trim();
                  final id = DateTime.now().microsecondsSinceEpoch.toString();
                  await home.upsertPlace(
                    FavoritePlace(
                      id: id,
                      name: name,
                      location: LatLng(pos.latitude, pos.longitude),
                    ),
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Impossible d\'ajouter un lieu depuis la position.')),
                  );
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Home / Today',
                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Résumé local et fenêtres favorables (opt-in)',
                          style: textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                      Switch(
                        value: enabled,
                        onChanged: (v) => unawaited(home.setEnabled(v)),
                      ),
                    ],
                  ),
                  if (enabled) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => unawaited(addFromCurrentLocation()),
                            child: const Text('Ajouter lieu (GPS)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: places.isEmpty ? null : () => unawaited(home.refresh()),
                            child: const Text('Refresh'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (places.isEmpty)
                      Text(
                        'Aucun lieu. Ajoute un endroit pour activer le résumé.',
                        style: textTheme.bodySmall?.copyWith(color: muted),
                      )
                    else
                      ...places.map((p) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                onPressed: () => unawaited(home.removePlace(p.id)),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                            ],
                          ),
                        );
                      }),
                    if (summary != null && summary.now.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Résumé',
                        style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      ...summary.now.map((n) {
                        final rain = n.decision.now.precipitation;
                        final conf = (n.decision.confidence * 100).round();
                        final comfort = n.decision.comfortScore.toStringAsFixed(1);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${n.place.name}  •  confort $comfort/10  •  conf $conf%  •  pluie ${rain.toStringAsFixed(1)} mm',
                            style: textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.88)),
                          ),
                        );
                      }),
                      if (summary.bestWindows.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Meilleures fenêtres',
                          style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        ...summary.bestWindows.map((w) {
                          final t = w.atUtc.toLocal();
                          final hh = t.hour.toString().padLeft(2, '0');
                          final mm = t.minute.toString().padLeft(2, '0');
                          final comfort = w.decision.comfortScore.toStringAsFixed(1);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${w.place.name}  •  $hh:$mm  •  confort $comfort/10',
                              style: textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.88)),
                            ),
                          );
                        }),
                      ],
                    ],
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Consumer<TripProvider>(
            builder: (ctx, trip, _) {
              final plans = trip.plans;
              final current = trip.currentPlan;
              final loading = trip.loading;
              final err = trip.error;
              final variants = trip.variants;
              final selectedKind = trip.selectedVariant;

              Future<void> createPlan() async {
                final nameCtrl = TextEditingController(text: 'Trajet');
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) {
                    return AlertDialog(
                      title: const Text('Nouveau trajet'),
                      content: TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nom'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dctx).pop(false),
                          child: const Text('Annuler'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(dctx).pop(true),
                          child: const Text('Créer'),
                        ),
                      ],
                    );
                  },
                );
                if (ok != true) return;
                final name = nameCtrl.text.trim().isEmpty ? 'Trajet' : nameCtrl.text.trim();
                final id = DateTime.now().microsecondsSinceEpoch.toString();
                final plan = TripPlan(id: id, name: name, mode: TravelMode.cycling, stops: const []);
                await trip.upsertPlan(plan, select: true);
              }

              Future<void> addStopFromGps({required bool isStart}) async {
                try {
                  await loc.ensurePermission();
                  final pos = await loc.getCurrentPosition();
                  if (!context.mounted) return;

                  final nameCtrl = TextEditingController(text: isStart ? 'Départ' : 'Arrivée');
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dctx) {
                      return AlertDialog(
                        title: Text(isStart ? 'Départ' : 'Arrivée'),
                        content: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Nom'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Ajouter'),
                          ),
                        ],
                      );
                    },
                  );
                  if (ok != true) return;
                  final name = nameCtrl.text.trim().isEmpty ? 'Stop' : nameCtrl.text.trim();
                  final stop = TripStop(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name,
                    location: LatLng(pos.latitude, pos.longitude),
                  );

                  final plan = trip.currentPlan;
                  if (plan == null) return;
                  final nextStops = [...plan.stops];
                  if (isStart) {
                    if (nextStops.isEmpty) {
                      nextStops.add(stop);
                    } else {
                      nextStops[0] = stop;
                    }
                  } else {
                    if (nextStops.length < 2) {
                      nextStops.add(stop);
                    } else {
                      nextStops[nextStops.length - 1] = stop;
                    }
                  }
                  if (nextStops.length < 2) {
                    final placeholder = TripStop(
                      id: 'placeholder',
                      name: isStart ? 'Arrivée' : 'Départ',
                      location: stop.location,
                    );
                    if (isStart) {
                      nextStops.add(placeholder);
                    } else {
                      nextStops.insert(0, placeholder);
                    }
                  }

                  final updated = TripPlan(id: plan.id, name: plan.name, mode: plan.mode, stops: nextStops);
                  await trip.upsertPlan(updated, select: true);
                  unawaited(trip.computeTripVariants(userInitiated: true));
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Impossible d\'ajouter un stop depuis la position.')),
                  );
                }
              }

              Future<void> addIntermediateStop() async {
                try {
                  await loc.ensurePermission();
                  final pos = await loc.getCurrentPosition();
                  if (!context.mounted) return;

                  final nameCtrl = TextEditingController(text: 'Stop');
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dctx) {
                      return AlertDialog(
                        title: const Text('Stop intermédiaire'),
                        content: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Nom'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Ajouter'),
                          ),
                        ],
                      );
                    },
                  );
                  if (ok != true) return;
                  final name = nameCtrl.text.trim().isEmpty ? 'Stop' : nameCtrl.text.trim();
                  final stop = TripStop(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name,
                    location: LatLng(pos.latitude, pos.longitude),
                    stay: const Duration(minutes: 5),
                  );

                  final plan = trip.currentPlan;
                  if (plan == null) return;
                  if (plan.stops.length < 2) return;
                  final nextStops = [...plan.stops];
                  nextStops.insert(nextStops.length - 1, stop);
                  final updated = TripPlan(id: plan.id, name: plan.name, mode: plan.mode, stops: nextStops);
                  await trip.upsertPlan(updated, select: true);
                  unawaited(trip.computeTripVariants(userInitiated: true));
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Impossible d\'ajouter un stop.')),
                  );
                }
              }

              Future<void> setStopStay(TripStop stop) async {
                final minutes = await showModalBottomSheet<int>(
                  context: context,
                  showDragHandle: true,
                  builder: (bctx) {
                    return SafeArea(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(title: const Text('0 min'), onTap: () => Navigator.of(bctx).pop(0)),
                          ListTile(title: const Text('5 min'), onTap: () => Navigator.of(bctx).pop(5)),
                          ListTile(title: const Text('10 min'), onTap: () => Navigator.of(bctx).pop(10)),
                          ListTile(title: const Text('15 min'), onTap: () => Navigator.of(bctx).pop(15)),
                          ListTile(title: const Text('30 min'), onTap: () => Navigator.of(bctx).pop(30)),
                          ListTile(title: const Text('60 min'), onTap: () => Navigator.of(bctx).pop(60)),
                        ],
                      ),
                    );
                  },
                );
                if (minutes == null) return;
                final plan = trip.currentPlan;
                if (plan == null) return;
                final nextStops = [...plan.stops];
                final idx = nextStops.indexWhere((s) => s.id == stop.id);
                if (idx < 0) return;
                nextStops[idx] = TripStop(id: stop.id, name: stop.name, location: stop.location, stay: Duration(minutes: minutes));
                final updated = TripPlan(id: plan.id, name: plan.name, mode: plan.mode, stops: nextStops);
                await trip.upsertPlan(updated, select: true);
                unawaited(trip.computeTripVariants(userInitiated: true));
              }

              Future<void> deleteStop(TripStop stop) async {
                final plan = trip.currentPlan;
                if (plan == null) return;
                if (plan.stops.length <= 2) return;
                final nextStops = plan.stops.where((s) => s.id != stop.id).toList();
                final updated = TripPlan(id: plan.id, name: plan.name, mode: plan.mode, stops: nextStops);
                await trip.upsertPlan(updated, select: true);
                unawaited(trip.computeTripVariants(userInitiated: true));
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trip',
                    style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: current?.id,
                          decoration: const InputDecoration(labelText: 'Trajet'),
                          items: plans
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (id) {
                            if (id == null) return;
                            final next = plans.firstWhere((p) => p.id == id);
                            unawaited(trip.setCurrentPlan(next));
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: () => unawaited(createPlan()),
                        icon: const Icon(Icons.add_rounded),
                      ),
                      IconButton(
                        onPressed: current == null ? null : () => unawaited(trip.removePlan(current.id)),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  if (current != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<TravelMode>(
                        segments: const [
                          ButtonSegment(value: TravelMode.walking, label: Text('Marche')),
                          ButtonSegment(value: TravelMode.cycling, label: Text('Vélo')),
                          ButtonSegment(value: TravelMode.car, label: Text('Auto')),
                          ButtonSegment(value: TravelMode.motorbike, label: Text('Moto')),
                        ],
                        selected: <TravelMode>{current.mode},
                        onSelectionChanged: (s) {
                          if (s.isEmpty) return;
                          final updated = TripPlan(id: current.id, name: current.name, mode: s.first, stops: current.stops);
                          unawaited(trip.upsertPlan(updated, select: true));
                          unawaited(trip.computeTripVariants(userInitiated: true));
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => unawaited(addStopFromGps(isStart: true)),
                            child: const Text('Départ (GPS)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => unawaited(addStopFromGps(isStart: false)),
                            child: const Text('Arrivée (GPS)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: current.stops.length < 2 ? null : () => unawaited(addIntermediateStop()),
                        child: const Text('Ajouter stop intermédiaire (GPS)'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (current.stops.length < 2)
                      Text(
                        'Définis un départ et une arrivée pour calculer un trip.',
                        style: textTheme.bodySmall?.copyWith(color: muted),
                      )
                    else
                      ...current.stops.asMap().entries.map((e) {
                        final idx = e.key;
                        final s = e.value;
                        final isIntermediate = idx > 0 && idx < current.stops.length - 1;
                        final stayMin = s.stay.inMinutes;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${idx + 1}. ${s.name}',
                                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (isIntermediate)
                                TextButton(
                                  onPressed: () => unawaited(setStopStay(s)),
                                  child: Text('${stayMin}m'),
                                ),
                              if (isIntermediate)
                                IconButton(
                                  onPressed: () => unawaited(deleteStop(s)),
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: current.stops.length < 2 ? null : () => unawaited(trip.computeTripVariants(userInitiated: true)),
                            child: loading ? const Text('Calcul...') : const Text('Calculer'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (variants.isNotEmpty) ...[
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<RouteVariantKind>(
                          segments: const [
                            ButtonSegment(value: RouteVariantKind.fast, label: Text('Fast')),
                            ButtonSegment(value: RouteVariantKind.safe, label: Text('Safe')),
                            ButtonSegment(value: RouteVariantKind.scenic, label: Text('Scenic')),
                          ],
                          selected: <RouteVariantKind>{selectedKind},
                          onSelectionChanged: (s) {
                            if (s.isEmpty) return;
                            trip.selectVariant(s.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            final v = variants.firstWhere(
                              (x) => x.kind == selectedKind,
                              orElse: () => variants.first,
                            );
                            routing.showExternalRoute(variant: v, name: current.name);
                          },
                          child: const Text('Afficher sur carte'),
                        ),
                      ),
                    ],
                    if (err != null)
                      Text(
                        err,
                        style: textTheme.bodySmall?.copyWith(color: scheme.error, fontWeight: FontWeight.w700),
                      )
                    else
                      Text(
                        'Variantes: ${variants.length}',
                        style: textTheme.bodySmall?.copyWith(color: muted),
                      ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _SwitchRow(
            label: 'Mode économie batterie',
            value: mapProvider.lowPowerMode,
            onChanged: (v) {
              mapProvider.setLowPowerMode(v);
              weather.syncLowPowerMode(v);
              routing.syncLowPowerMode(v);
            },
          ),
          _SwitchRow(
            label: 'Analytics anonymes (opt-in)',
            value: settings.analyticsSettings.level ==
                AnalyticsLevel.anonymous,
            onChanged: (v) => settings.setAnalyticsLevel(
                v ? AnalyticsLevel.anonymous : AnalyticsLevel.off),
          ),
          _SwitchRow(
            label: 'Notifications (opt-in)',
            value: settings.notificationsEnabled,
            onChanged: (v) {
              unawaited(
                  settings.setNotificationsEnabled(v).then((_) {
                mapProvider.syncNotificationsEnabledFromSettings(
                    settings.notificationsEnabled);
                routing.syncNotificationsEnabledFromSettings(
                    settings.notificationsEnabled);
              }));
            },
          ),
          const SizedBox(height: 8),
          _DataReportSection(mapProvider: mapProvider),
          const SizedBox(height: 14),
          Text(
            'HORIZON fonctionne sans compte. Les données restent sur l\'appareil.\nLong-press ici pour gérer/effacer rapidement.',
            style: textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 14),
          _ActionButtons(mapProvider: mapProvider),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _DataReportSection extends StatelessWidget {
  final MapProvider mapProvider;

  const _DataReportSection({required this.mapProvider});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: mapProvider.computeLocalDataReport(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }
        final report = snap.data!;
        final textTheme = Theme.of(ctx).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stockage sécurisé : ${formatBytes(report.secureStoreBytes)}',
              style: textTheme.bodySmall,
            ),
            Text(
              'Cache itinéraires (legacy) : ${formatBytes(report.routeCacheBytes)}',
              style: textTheme.bodySmall,
            ),
            Text(
              'Cache météo (legacy) : ${formatBytes(report.weatherCacheBytes)}',
              style: textTheme.bodySmall,
            ),
            Text(
              'Packs offline : ${formatBytes(report.offlinePacksBytes)}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Total : ${formatBytes(report.totalBytes)}',
              style: textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        );
      },
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final MapProvider mapProvider;

  const _ActionButtons({required this.mapProvider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final json = await mapProvider.exportPerfMetricsJson();
                  if (!context.mounted) return;
                  await _showTextDialog(context, 'Rapport perf (local)', json);
                },
                child: const Text('Perf'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final json =
                      await mapProvider.exportAnalyticsBufferJson();
                  if (!context.mounted) return;
                  await _showTextDialog(context, 'Buffer analytics (local)',
                      json ?? 'Aucun événement.');
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
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dctx) {
                      return AlertDialog(
                        title: const Text('Effacement rapide ?'),
                        content: const Text(
                          'Supprime caches, packs offline et clés locales. Action irréversible.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dctx).pop(false),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dctx).pop(true),
                            child: const Text('Effacer'),
                          ),
                        ],
                      );
                    },
                  );
                  if (ok == true) {
                    await mapProvider.panicWipeAllLocalData();
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
                child: const Text('Panic wipe'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showTextDialog(
      BuildContext context, String title, String text) async {
    await showDialog<void>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: Theme.of(context).textTheme.bodySmall,
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
  }
}
