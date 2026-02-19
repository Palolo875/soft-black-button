import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/circuit_breaker.dart';

void main() {
  group('CircuitBreaker', () {
    test('starts in closed state', () {
      final cb = CircuitBreaker(name: 'test');
      expect(cb.state, CircuitState.closed);
      expect(cb.isClosed, isTrue);
    });

    test('opens after failure threshold', () async {
      final cb = CircuitBreaker(
        name: 'test',
        config: const CircuitBreakerConfig(failureThreshold: 3),
      );

      for (int i = 0; i < 3; i++) {
        try {
          await cb.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }

      expect(cb.state, CircuitState.open);
      expect(cb.isOpen, isTrue);
    });

    test('allows request in half-open state after reset timeout', () async {
      final cb = CircuitBreaker(
        name: 'test',
        config: const CircuitBreakerConfig(
          failureThreshold: 2,
          resetTimeout: Duration(milliseconds: 50),
        ),
      );

      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}
      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}

      expect(cb.state, CircuitState.open);

      await Future.delayed(const Duration(milliseconds: 60));

      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}

      expect(cb.state, CircuitState.halfOpen);
    });

    test('closes after successful half-open requests', () async {
      final cb = CircuitBreaker(
        name: 'test',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          resetTimeout: Duration(milliseconds: 50),
        ),
      );

      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}

      expect(cb.state, CircuitState.open);

      await Future.delayed(const Duration(milliseconds: 60));

      await cb.execute(() async => 'success');
      expect(cb.state, CircuitState.halfOpen);

      await cb.execute(() async => 'success');
      expect(cb.state, CircuitState.closed);
    });

    test('throws when circuit is open and not reset', () async {
      final cb = CircuitBreaker(
        name: 'test',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          resetTimeout: Duration(hours: 1),
        ),
      );

      try {
        await cb.execute(() async => throw Exception('fail'));
      } catch (_) {}

      expect(cb.state, CircuitState.open);

      expect(
        () => cb.execute(() async => 'success'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });
  });

  group('CircuitBreakerRegistry', () {
    test('getOrCreate returns same instance', () {
      final registry = CircuitBreakerRegistry();
      final cb1 = registry.getOrCreate('test');
      final cb2 = registry.getOrCreate('test');
      expect(identical(cb1, cb2), isTrue);
    });

    test('getOrCreate creates different instances for different names', () {
      final registry = CircuitBreakerRegistry();
      final cb1 = registry.getOrCreate('test1');
      final cb2 = registry.getOrCreate('test2');
      expect(identical(cb1, cb2), isFalse);
    });

    test('resetAll resets all breakers', () {
      final registry = CircuitBreakerRegistry();
      final cb = registry.getOrCreate('test');
      
      try {
        cb.execute(() async => throw Exception('fail'));
      } catch (_) {}
      
      registry.resetAll();
      expect(cb.state, CircuitState.closed);
    });

    test('allStates returns all circuit states', () {
      final registry = CircuitBreakerRegistry();
      registry.getOrCreate('test1');
      registry.getOrCreate('test2');
      
      final states = registry.allStates;
      expect(states.length, 2);
      expect(states['test1'], CircuitState.closed);
      expect(states['test2'], CircuitState.closed);
    });
  });
}
