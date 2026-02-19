import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:horizon/providers/offline_provider.dart';
import 'package:horizon/features/map/presentation/utils/glass_decoration.dart';

/// Floating progress bar for offline downloads and PMTiles activation.
class OfflineProgressBar extends StatelessWidget {
  const OfflineProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    final offline = Provider.of<OfflineProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    final showBar = offline.offlineDownloadProgress != null ||
        offline.offlineDownloadError != null ||
        offline.pmtilesProgress != null ||
        offline.pmtilesError != null;

    if (!showBar) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Semantics(
            container: true,
            label: 'Progression offline',
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: glassDecoration(context, opacity: 0.78),
              child: Row(
                children: [
                  const Icon(Icons.offline_pin_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: _content(context, offline, scheme)),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () {
                      offline.clearOfflineDownloadState();
                      offline.clearPmtilesState();
                    },
                    visualDensity: VisualDensity.compact,
                    icon: Tooltip(
                      message: 'Fermer',
                      child: Icon(
                        Icons.close_rounded,
                        color: scheme.onSurface.withOpacity(0.82),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
      BuildContext context,
      OfflineProvider offline,
      ColorScheme scheme) {
    final textStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(fontWeight: FontWeight.w600);

    if (offline.pmtilesError != null) {
      return Text(
        offline.pmtilesError!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }
    if (offline.offlineDownloadError != null) {
      return Text(
        offline.offlineDownloadError!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          offline.pmtilesProgress != null
              ? 'Activation pack offline…'
              : 'Téléchargement offline…',
          style: textStyle,
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: offline.pmtilesProgress ??
              offline.offlineDownloadProgress,
          minHeight: 3,
          color: scheme.primary,
          backgroundColor: scheme.primary.withOpacity(0.18),
        ),
      ],
    );
  }
}
