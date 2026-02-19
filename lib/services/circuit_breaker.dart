import 'dart:async';

enum CircuitState { closed, open, halfOpen }

class CircuitBreakerConfig {
  final int failureThreshold;
  final Duration resetTimeout;
  final Duration halfOpenTimeout;

  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 30),
    this.halfOpenTimeout = const Duration(seconds: 10),
  });
}

class CircuitBreaker {
  final String name;
  final CircuitBreakerConfig config;
  
  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _lastFailureTime;
  Timer? _resetTimer;

  CircuitState get state => _state;
  String get name => name;

  CircuitBreaker({
    required this.name,
    this.config = const CircuitBreakerConfig(),
  });

  bool get isClosed => _state == CircuitState.closed;
  bool get isOpen => _state == CircuitState.open;
  bool get isHalfOpen => _state == CircuitState.halfOpen;

  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_state == CircuitState.open) {
      if (_shouldAttemptReset()) {
        _state = CircuitState.halfOpen;
        _successCount = 0;
      } else {
        throw CircuitBreakerOpenException(name);
      }
    }

    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  bool _shouldAttemptReset() {
    final lastFailure = _lastFailureTime;
    if (lastFailure == null) return true;
    return DateTime.now().difference(lastFailure) >= config.resetTimeout;
  }

  void _onSuccess() {
    _failureCount = 0;
    
    if (_state == CircuitState.halfOpen) {
      _successCount++;
      if (_successCount >= 2) {
        _state = CircuitState.closed;
        _resetTimer?.cancel();
        _resetTimer = null;
      }
    }
  }

  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    if (_state == CircuitState.halfOpen) {
      _state = CircuitState.open;
      _scheduleReset();
    } else if (_failureCount >= config.failureThreshold) {
      _state = CircuitState.open;
      _scheduleReset();
    }
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(config.resetTimeout, () {
      _state = CircuitState.halfOpen;
      _successCount = 0;
    });
  }

  void reset() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _successCount = 0;
    _lastFailureTime = null;
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  void dispose() {
    _resetTimer?.cancel();
  }
}

class CircuitBreakerOpenException implements Exception {
  final String circuitName;
  
  CircuitBreakerOpenException(this.circuitName);
  
  @override
  String toString() => 'CircuitBreakerOpenException: $circuitName is open';
}

class CircuitBreakerRegistry {
  static final CircuitBreakerRegistry _instance = CircuitBreakerRegistry._internal();
  factory CircuitBreakerRegistry() => _instance;
  CircuitBreakerRegistry._internal();

  final Map<String, CircuitBreaker> _breakers = {};

  CircuitBreaker getOrCreate(String name, {CircuitBreakerConfig? config}) {
    return _breakers.putIfAbsent(
      name,
      () => CircuitBreaker(name: name, config: config ?? const CircuitBreakerConfig()),
    );
  }

  CircuitBreaker? get(String name) => _breakers[name];

  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
  }

  void dispose() {
    for (final breaker in _breakers.values) {
      breaker.dispose();
    }
    _breakers.clear();
  }

  Map<String, CircuitState> get allStates {
    return _breakers.map((key, value) => MapEntry(key, value.state));
  }
}
