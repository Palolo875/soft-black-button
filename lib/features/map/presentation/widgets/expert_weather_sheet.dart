import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:horizon/providers/weather_provider.dart';
import 'package:horizon/ui/horizon_bottom_sheet.dart';

/// Bottom sheet for toggling expert weather layers (wind, rain, cloud).
class ExpertWeatherSheet extends StatelessWidget {
  const ExpertWeatherSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (_) => const ExpertWeatherSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weather = Provider.of<WeatherProvider>(context);
    final theme = Theme.of(context);
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
            style: textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _Toggle(
            label: 'Mode expert',
            value: weather.expertWeatherMode,
            onChanged: (v) => weather.setExpertWeatherMode(v),
          ),
          _Toggle(
            label: 'Vent',
            value: weather.expertWindLayer,
            onChanged: weather.expertWeatherMode
                ? (v) => weather.setExpertWindLayer(v)
                : null,
          ),
          _Toggle(
            label: 'Pluie',
            value: weather.expertRainLayer,
            onChanged: weather.expertWeatherMode
                ? (v) => weather.setExpertRainLayer(v)
                : null,
          ),
          _Toggle(
            label: 'Nuages',
            value: weather.expertCloudLayer,
            onChanged: weather.expertWeatherMode
                ? (v) => weather.setExpertCloudLayer(v)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Ces couches restent locales et sont contextualisées par l\'itinéraire quand il existe.',
            style: textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _Toggle({
    required this.label,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
