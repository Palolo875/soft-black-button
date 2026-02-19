import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/ui/horizon_chip.dart';

void main() {
  group('HorizonChip', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HorizonChip(
              label: 'Test Chip',
              selected: false,
              onSelected: _noop,
            ),
          ),
        ),
      );

      expect(find.text('Test Chip'), findsOneWidget);
    });

    testWidgets('shows selected state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HorizonChip(
              label: 'Selected Chip',
              selected: true,
              onSelected: _noop,
            ),
          ),
        ),
      );

      expect(find.text('Selected Chip'), findsOneWidget);
    });

    testWidgets('calls onSelected when tapped', (tester) async {
      bool selected = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HorizonChip(
              label: 'Tappable Chip',
              selected: false,
              onSelected: (s) => selected = s,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tappable Chip'));
      await tester.pump();

      expect(selected, isTrue);
    });
  });
}

void _noop(bool s) {}
