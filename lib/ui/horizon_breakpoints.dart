import 'package:flutter/material.dart';

class HorizonBreakpoints {
  static const double compact = 600;
  static const double medium = 1024;

  static bool isCompact(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w < compact;
  }

  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= compact && w < medium;
  }

  static bool isExpanded(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= medium;
  }
}

class HorizonResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) compact;
  final Widget Function(BuildContext context)? medium;
  final Widget Function(BuildContext context)? expanded;

  const HorizonResponsiveBuilder({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w >= HorizonBreakpoints.medium) {
          return (expanded ?? medium ?? compact)(context);
        }
        if (w >= HorizonBreakpoints.compact) {
          return (medium ?? compact)(context);
        }
        return compact(context);
      },
    );
  }
}
