import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/main.dart';
import 'package:horizon/core/di/app_dependencies.dart';
import 'package:horizon/features/map/presentation/map_screen.dart';

void main() {
  testWidgets('App basic smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final deps = AppDependencies.create();
    await tester.pumpWidget(HorizonApp(deps: deps));
    // On ne pump pas settle à cause des animations infinies du service météo
    await tester.pump();

    // Verify that some UI elements are present
    expect(find.byType(MapScreen), findsOneWidget);
  });
}
