import 'package:flutter/material.dart';

import 'package:horizon/ui/horizon_chip.dart';

/// A chip for selecting a route variant (Rapide, Sûre, Calme, GPX).
class RouteChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const RouteChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Variante $label${selected ? ', sélectionnée' : ''}',
      child: HorizonChip(
        label: label,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}
