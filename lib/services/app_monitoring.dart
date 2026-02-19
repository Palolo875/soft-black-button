import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class AppMonitoring {
  static final AppMonitoring _instance = AppMonitoring._internal();
  factory AppMonitoring() => _instance;
  AppMonitoring._internal();

  bool _initialized = false;

  Future<void> init({
    required String dsn,
    String environment = 'production',
    double? sampleRate,
  }) async {
    if (_initialized) return;

    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.environment = environment;
        
        if (sampleRate != null) {
          options.tracesSampleRate = sampleRate;
        } else {
          options.tracesSampleRate = kDebugMode ? 1.0 : 0.1;
        }
        
        options.attachStacktrace = true;
        options.sendDefaultPii = false;
        
        options.beforeSend = (event, hint) {
          if (kDebugMode) {
            return null;
          }
          return event;
        };
      },
    );
    
    _initialized = true;
  }

  void captureException(
    Object exception, {
    StackTrace? stackTrace,
    Map<String, dynamic>? extra,
  }) {
    if (!_initialized) return;
    
    Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (extra != null) {
          scope.setExtra('custom_data', extra);
        }
      },
    );
  }

  void captureMessage(
    String message, {
    SentryLevel level = SentryLevel.info,
    Map<String, dynamic>? extra,
  }) {
    if (!_initialized) return;
    
    Sentry.captureMessage(
      message,
      level: level,
      withScope: (scope) {
        if (extra != null) {
          scope.setExtra('custom_data', extra);
        }
      },
    );
  }

  void setUser({
    required String id,
    String? email,
    String? username,
  }) {
    if (!_initialized) return;
    
    Sentry.setUser(
      SentryUser(
        id: id,
        email: email,
        username: username,
      ),
    );
  }

  void clearUser() {
    if (!_initialized) return;
    Sentry.configureScope((scope) => scope.user = null);
  }

  void addBreadcrumb({
    required String message,
    String? category,
    Map<String, dynamic>? data,
  }) {
    if (!_initialized) return;
    
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category ?? 'app',
        data: data,
      ),
    );
  }

  Future<void> flush() async {
    if (!_initialized) return;
    await Sentry.flush(const Duration(seconds: 5));
  }
}
