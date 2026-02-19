import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/app_monitoring.dart';

void main() {
  group('AppMonitoring', () {
    test('singleton returns same instance', () {
      final m1 = AppMonitoring();
      final m2 = AppMonitoring();
      expect(identical(m1, m2), isTrue);
    });

    test('captureException does not throw when not initialized', () {
      final monitoring = AppMonitoring();
      
      expect(
        () => monitoring.captureException(Exception('test')),
        returnsNormally,
      );
    });

    test('captureMessage does not throw when not initialized', () {
      final monitoring = AppMonitoring();
      
      expect(
        () => monitoring.captureMessage('test'),
        returnsNormally,
      );
    });

    test('setUser does not throw when not initialized', () {
      final monitoring = AppMonitoring();
      
      expect(
        () => monitoring.setUser(id: 'test-user'),
        returnsNormally,
      );
    });

    test('clearUser does not throw when not initialized', () {
      final monitoring = AppMonitoring();
      
      expect(
        () => monitoring.clearUser(),
        returnsNormally,
      );
    });

    test('addBreadcrumb does not throw when not initialized', () {
      final monitoring = AppMonitoring();
      
      expect(
        () => monitoring.addBreadcrumb(message: 'test'),
        returnsNormally,
      );
    });

    test('flush does not throw when not initialized', () async {
      final monitoring = AppMonitoring();
      
      expect(
        () => monitoring.flush(),
        returnsNormally,
      );
    });
  });
}
