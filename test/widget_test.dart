import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('App basic smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const HorizonApp());
    // On ne pump pas settle à cause des animations infinies du service météo
    await tester.pump();

    // Verify that some UI elements are present
    expect(find.byType(MapScreen), findsOneWidget);
  });
}
