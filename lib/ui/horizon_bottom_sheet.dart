import 'package:flutter/material.dart';

import 'horizon_card.dart';

class HorizonBottomSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showHandle;

  const HorizonBottomSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 16),
    this.showHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: HorizonCard(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        padding: padding,
        blur: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHandle)
              Container(
                width: 42,
                height: 5,
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: theme.colorScheme.onSurface.withOpacity(theme.brightness == Brightness.dark ? 0.16 : 0.12),
                ),
              ),
            if (showHandle) const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
