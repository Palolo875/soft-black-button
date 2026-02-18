import 'package:flutter/material.dart';

/// Glassmorphism-style decoration shared across map screen widgets.
BoxDecoration glassDecoration(BuildContext context, {double opacity = 0.62}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return BoxDecoration(
    color: scheme.surface.withOpacity(opacity),
    borderRadius: BorderRadius.circular(22.0),
    border: Border.all(
      color: scheme.outlineVariant.withOpacity(
        theme.brightness == Brightness.dark ? 0.22 : 0.32,
      ),
    ),
    boxShadow: [
      BoxShadow(
        color: scheme.shadow.withOpacity(
          theme.brightness == Brightness.dark ? 0.22 : 0.06,
        ),
        blurRadius: 30,
        offset: const Offset(0, 12),
      ),
    ],
  );
}
