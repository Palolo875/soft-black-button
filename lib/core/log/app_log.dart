import 'package:flutter/foundation.dart';

enum AppLogLevel {
  debug,
  info,
  warn,
  error,
}

class AppLog {
  static AppLogLevel level = kReleaseMode ? AppLogLevel.info : AppLogLevel.debug;

  static void d(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? props}) {
    _log(AppLogLevel.debug, message, error: error, stackTrace: stackTrace, props: props);
  }

  static void i(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? props}) {
    _log(AppLogLevel.info, message, error: error, stackTrace: stackTrace, props: props);
  }

  static void w(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? props}) {
    _log(AppLogLevel.warn, message, error: error, stackTrace: stackTrace, props: props);
  }

  static void e(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?>? props}) {
    _log(AppLogLevel.error, message, error: error, stackTrace: stackTrace, props: props);
  }

  static void _log(
    AppLogLevel msgLevel,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? props,
  }) {
    if (msgLevel.index < level.index) return;

    final sb = StringBuffer();
    sb.write('[${msgLevel.name.toUpperCase()}] ');
    sb.write(message);
    if (props != null && props.isNotEmpty) {
      sb.write(' ');
      sb.write(props);
    }
    if (error != null) {
      sb.write(' error=');
      sb.write(error);
    }
    if (stackTrace != null) {
      sb.write('\n');
      sb.write(stackTrace);
    }
    debugPrint(sb.toString());
  }
}
