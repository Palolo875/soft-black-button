import 'dart:ui';

import 'package:flutter/material.dart';

class HorizonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool blur;
  final double blurSigma;
  final VoidCallback? onTap;

  const HorizonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.margin,
    this.blur = false,
    this.blurSigma = 10,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = theme.cardTheme.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(22));
    final color = theme.cardTheme.color ?? theme.colorScheme.surface;

    final content = Container(
      margin: margin,
      padding: padding,
      decoration: ShapeDecoration(
        shape: shape,
        color: color,
        shadows: [
          BoxShadow(
            color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.28 : 0.06),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );

    final clipped = ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: content,
            )
          : content,
    );

    if (onTap == null) return clipped;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: clipped,
      ),
    );
  }
}
