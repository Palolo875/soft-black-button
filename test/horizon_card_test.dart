import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/ui/horizon_card.dart';
import 'package:app/ui/horizon_theme.dart';

void main() {
  testWidgets('HorizonCard renders child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HorizonTheme.light(),
        home: const Scaffold(
          body: HorizonCard(
            child: Text('Hello'),
          ),
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('HorizonCard is tappable when onTap is provided', (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: HorizonTheme.light(),
        home: Scaffold(
          body: HorizonCard(
            onTap: () => taps++,
            child: const Text('Tap me'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tap me'));
    await tester.pump();
    expect(taps, 1);
  });
}
