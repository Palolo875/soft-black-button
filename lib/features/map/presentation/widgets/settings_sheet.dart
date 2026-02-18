import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:horizon/providers/app_settings_provider.dart';
import 'package:horizon/providers/map_provider.dart';
import 'package:horizon/providers/weather_provider.dart';
import 'package:horizon/providers/routing_provider.dart';
import 'package:horizon/services/analytics_service.dart';
import 'package:horizon/ui/horizon_bottom_sheet.dart';
import 'package:horizon/features/map/presentation/utils/format_utils.dart';

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
