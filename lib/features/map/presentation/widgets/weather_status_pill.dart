import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:horizon/providers/map_provider.dart';
import 'package:horizon/providers/weather_provider.dart';
import 'package:horizon/ui/horizon_card.dart';
import 'package:horizon/ui/horizon_bottom_sheet.dart';
import 'package:horizon/features/map/presentation/utils/format_utils.dart';
import 'package:horizon/features/map/presentation/widgets/expert_weather_sheet.dart';
import 'package:horizon/features/map/presentation/widgets/settings_sheet.dart';

/// Top status pill showing current weather summary.
class WeatherStatusPill extends StatelessWidget {
  const WeatherStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final weather = Provider.of<WeatherProvider>(context);
    final mapProvider = Provider.of<MapProvider>(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurfaceStrong = scheme.onSurface.withOpacity(0.88);
    final onSurfaceMuted = scheme.onSurface.withOpacity(0.60);

    return GestureDetector(
      onLongPress: () => SettingsSheet.show(context),
      child: HorizonCard(
        blur: false,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        onTap: () => _showWeatherDetail(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF8FAE8B).withOpacity(0.85),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              weather.weatherError != null
                  ? Icons.cloud_off_rounded
                  : (weather.weatherLoading
                      ? Icons.cloud_sync_rounded
                      : Icons.wb_sunny_rounded),
              size: 18,
              color: weather.weatherError != null
                  ? const Color(0xFFC88B6E)
                  : (weather.weatherLoading
                      ? scheme.primary
                      : const Color(0xFFD2B48C)),
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
                        : (weather.weatherDecision == null
                            ? 'Météo…'
                            : '${weather.weatherDecision!.now.temperature.round()}°C'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: onSurfaceStrong,
                    ),
                  ),
                  if (weather.weatherDecision != null &&
                      weather.weatherError == null)
                    Text(
                      'confort ${weather.weatherDecision!.comfortScore.toStringAsFixed(1)}/10  •  conf ${(weather.weatherDecision!.confidence * 100).round()}%'
                      '${mapProvider.isOnline == false ? '  •  offline' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurfaceMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (mapProvider.isOnline == false)
                    Text(
                      'offline',
                      style: theme.textTheme.bodySmall?.copyWith(
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
              onTap: () => ExpertWeatherSheet.show(context),
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
    );
  }

  Future<void> _showWeatherDetail(BuildContext context) async {
    final weather = Provider.of<WeatherProvider>(context, listen: false);
    final mapProvider = Provider.of<MapProvider>(context, listen: false);

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
          final t = now.apparentTemperature.isFinite
              ? now.apparentTemperature
              : now.temperature;
          final confPct = (decision.confidence * 100).round();
          final confLabel = weather.currentWeatherReliabilityLabel;
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${t.toStringAsFixed(0)}°C',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: body,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'vent ${msToKmh(now.windSpeed).toStringAsFixed(0)} km/h  •  pluie ${now.precipitation.toStringAsFixed(1)} mm',
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
                  style: textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
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
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              content,
            ],
          ),
        );
      },
    );
  }
}
