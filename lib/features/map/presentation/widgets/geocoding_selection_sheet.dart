import 'package:flutter/material.dart';
import 'package:horizon/services/geocoding_service.dart';
import 'package:horizon/ui/horizon_bottom_sheet.dart';

class GeocodingSelectionSheet extends StatelessWidget {
  final List<GeocodingResult> results;
  final Function(GeocodingResult) onSelected;

  const GeocodingSelectionSheet({
    super.key,
    required this.results,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required List<GeocodingResult> results,
    required Function(GeocodingResult) onSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (_) => GeocodingSelectionSheet(results: results, onSelected: onSelected),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            'Résultats de recherche',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final r = results[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${r.admin1 ?? ''}${r.admin1 != null && r.country != null ? ', ' : ''}${r.country ?? ''}',
                  style: textTheme.bodySmall?.copyWith(color: muted),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: muted),
                onTap: () {
                  onSelected(r);
                  Navigator.of(ctx).pop();
                },
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
