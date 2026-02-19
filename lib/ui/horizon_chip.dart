import 'package:flutter/material.dart';

class HorizonChip extends StatelessWidget {
  final Widget? icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const HorizonChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chipTheme = theme.chipTheme;

    final Widget labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: chipTheme.labelStyle,
    );

    final shape = chipTheme.shape ?? const StadiumBorder();

    final bg = selected ? (chipTheme.selectedColor ?? colorScheme.surface) : (chipTheme.backgroundColor ?? colorScheme.surface);

    final side = selected
        ? BorderSide(color: colorScheme.primary.withOpacity(theme.brightness == Brightness.dark ? 0.45 : 0.34), width: 1)
        : BorderSide(color: colorScheme.outlineVariant.withOpacity(theme.brightness == Brightness.dark ? 0.45 : 0.30), width: 1);

    final effectiveShape = shape is OutlinedBorder ? shape.copyWith(side: side) : shape;

    final chip = RawChip(
      label: labelWidget,
      avatar: icon,
      selected: selected,
      showCheckmark: false,
      padding: chipTheme.padding,
      backgroundColor: bg,
      selectedColor: bg,
      shape: effectiveShape,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: onTap,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    );

    return chip;
  }
}
