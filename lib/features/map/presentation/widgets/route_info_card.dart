import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:horizon/providers/map_provider.dart';
import 'package:horizon/providers/routing_provider.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/ui/horizon_card.dart';
import 'package:horizon/ui/horizon_bottom_sheet.dart';
import 'package:horizon/features/map/presentation/utils/format_utils.dart';
import 'package:horizon/features/map/presentation/widgets/route_chip.dart';
import 'package:horizon/features/map/presentation/widgets/elevation_sparkline.dart';

/// Card showing routing summary, variant selector, and weather metrics.
class RouteInfoCard extends StatelessWidget {
  const RouteInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final routing = Provider.of<RoutingProvider>(context);
    if (routing.routeVariants.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurfaceStrong = scheme.onSurface.withOpacity(0.88);
    final onSurfaceMuted = scheme.onSurface.withOpacity(0.60);

    final variant = routing.routeVariants.firstWhere(
      (v) => v.kind == routing.selectedVariant,
      orElse: () => routing.routeVariants.first,
    );
    final ex = routing.currentRouteExplanation;

    final title = routeVariantTitle(variant.kind.name);
    final distance = '${variant.lengthKm.toStringAsFixed(1)} km';
    final duration = formatDurationFromSeconds(variant.timeSeconds);

    String? line2;
    if (ex != null && ex.metrics.avgConfidence > 0) {
      final wind = msToKmh(ex.metrics.avgWind).toStringAsFixed(0);
      final rain = ex.metrics.rainKm.toStringAsFixed(1);
      final minComfort = ex.metrics.minComfort.toStringAsFixed(1);
      final elev = ex.metrics.elevationGain.round();
      line2 =
          'min confort $minComfort/10  •  elev $elev m  •  pluie ~$rain km  •  vent $wind km/h';
    }

    return HorizonCard(
      blur: false,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onTap: () => _showRouteDetail(context, variant, ex, title, distance, duration),
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
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: onSurfaceMuted),
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
  }

  Future<void> _showRouteDetail(
    BuildContext context,
    RouteVariant variant,
    dynamic ex,
    String title,
    String distance,
    String duration,
  ) async {
    if (ex == null) return;
    final mapProvider =
        Provider.of<MapProvider>(context, listen: false);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        final muted = scheme.onSurface.withOpacity(0.60);
        final body = scheme.onSurface.withOpacity(0.88);
        final textTheme = theme.textTheme;

        final windKmh =
            msToKmh(ex.metrics.avgWind).toStringAsFixed(0);
        final rainKm = ex.metrics.rainKm.toStringAsFixed(1);
        final conf =
            (ex.metrics.avgConfidence * 100).round();
        final confLabel = mapProvider
            .confidenceLabel(ex.metrics.avgConfidence);
        final minComfort =
            ex.metrics.minComfort.toStringAsFixed(1);

        return HorizonBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Résumé itinéraire',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: body),
              ),
              const SizedBox(height: 4),
              Text(
                '$distance  •  $duration',
                style: textTheme.bodySmall?.copyWith(
                    color: muted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                ex.headline as String,
                style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: body),
              ),
              if (ex.caveat != null) ...[
                const SizedBox(height: 6),
                Text(
                  ex.caveat as String,
                  style:
                      textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
              const SizedBox(height: 12),
              _buildMetricGrid(context, ex),
              const SizedBox(height: 6),
              Text(
                'Fiabilité : $confLabel (confiance $conf%)',
                style:
                    textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 16),
              Consumer<RoutingProvider>(
                builder: (context, routing, _) {
                  return Column(
                    children: [
                      ElevationSparkline(
                        profile: variant.elevationProfile ?? [],
                        height: 80,
                        selectedIndex: routing.scrubIndex,
                        onSelected: (idx) => routing.setScrubIndex(idx),
                      ),
                      if (routing.scrubIndex != null && variant.elevationProfile != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Altitude : ${variant.elevationProfile![routing.scrubIndex!].round()}m',
                            style: textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Fais glisser pour explorer le relief',
                  style: textTheme.labelSmall?.copyWith(color: muted, fontSize: 9),
                ),
              ),
              if (ex.factors.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Facteurs dominants',
                  style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800, color: body),
                ),
                const SizedBox(height: 8),
                ...(ex.factors as List).map<Widget>((f) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.title as String,
                          style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: body),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f.detail as String,
                          style: textTheme.bodySmall
                              ?.copyWith(color: muted),
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
  }

  Widget _buildMetricGrid(BuildContext context, dynamic ex) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricTile(
          icon: Icons.terrain_rounded,
          label: 'Dénivelé',
          value: '+${ex.metrics.elevationGain.round()}m',
        ),
        _MetricTile(
          icon: Icons.air_rounded,
          label: 'Vent moy.',
          value: '${msToKmh(ex.metrics.avgWind).toStringAsFixed(0)} km/h',
        ),
        _MetricTile(
          icon: Icons.umbrella_rounded,
          label: 'Pluie',
          value: '~${ex.metrics.rainKm.toStringAsFixed(1)} km',
        ),
        _MetricTile(
          icon: Icons.speed_rounded,
          label: 'Confort min',
          value: '${ex.metrics.minComfort.toStringAsFixed(1)}/10',
          color: ex.metrics.minComfort < 5 ? Colors.orange : null,
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    
    return Container(
      width: (MediaQuery.sizeOf(context).width - 60) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurface.withOpacity(0.6))),
                Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
