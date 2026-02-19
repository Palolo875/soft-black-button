import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:horizon/providers/home_today_provider.dart';
import 'package:horizon/ui/horizon_bottom_sheet.dart';
import 'package:horizon/ui/horizon_theme.dart';
import 'package:horizon/features/map/presentation/utils/format_utils.dart';

class HomeTodayDashboardSheet extends StatelessWidget {
  const HomeTodayDashboardSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => const HomeTodayDashboardSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = Provider.of<HomeTodayProvider>(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final summary = home.summary;

    if (!home.settings.enabled) {
      return HorizonBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Dashboard désactivé', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Activez Home/Today dans les réglages pour voir vos lieux favoris.'),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    return HorizonBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Ma Journée',
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
              const Spacer(),
              if (home.loaded)
                IconButton(
                  onPressed: () => home.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (summary == null || summary.now.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  home.settings.places.isEmpty 
                    ? 'Aucun lieu favori configuré.' 
                    : 'Chargement des prévisions...',
                  style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface.withOpacity(0.5)),
                ),
              ),
            )
          else ...[
          _buildBriefing(context, summary),
          const SizedBox(height: 24),
          Text('État actuel', style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: summary.now.length,
            itemBuilder: (ctx, i) {
              final n = summary.now[i];
              return _placeCard(context, n.place.name, n.decision.comfortScore, n.decision.now.temperature);
            },
          ),
            if (summary.bestWindows.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Meilleurs créneaux', style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
              const SizedBox(height: 12),
              ...summary.bestWindows.map((w) {
                final t = w.atUtc.toLocal();
                final hh = t.hour.toString().padLeft(2, '0');
                final mm = t.minute.toString().padLeft(2, '0');
                final rain = w.decision.now.precipitation;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$hh:$mm', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: scheme.primary)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.place.name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                              'Confort ${w.decision.comfortScore.toStringAsFixed(1)}/10${rain > 0 ? ' • Pluie ${rain.toStringAsFixed(1)}mm' : ''}',
                              style: textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.6)),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        w.decision.comfortScore >= 7.5 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                        color: w.decision.comfortScore >= 7.5 ? Colors.green : scheme.primary,
                        size: 20,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildBriefing(BuildContext context, dynamic summary) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    
    String briefing = "Chargement de ton briefing...";
    if (summary.bestWindows.isNotEmpty) {
      final best = summary.bestWindows.first;
      final t = best.atUtc.toLocal();
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      briefing = "Bonjour ! Ton partenaire Horizon te conseille de partir vers **${best.place.name}** aux alentours de **$hh:$mm** pour bénéficier d'un confort optimal (${best.decision.comfortScore.toStringAsFixed(1)}/10).";
    } else {
      briefing = "Les conditions actuelles sont stables. Consulte tes lieux favoris ci-dessous pour plus de détails.";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text('CONSEIL HORIZON', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900, color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(briefing, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
        ],
      ),
    );
  }

  Widget _placeCard(BuildContext context, String name, double comfort, double temp) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    Color statusColor = Colors.green;
    if (comfort < 7.0) statusColor = Colors.orange;
    if (comfort < 4.0) statusColor = Colors.red;

    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${temp.round()}°', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1)),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('${comfort.toStringAsFixed(1)}/10', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: statusColor)),
            ],
          ),
        ],
      ),
    );
  }
}
