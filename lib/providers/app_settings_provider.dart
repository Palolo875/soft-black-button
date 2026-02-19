import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:horizon/services/analytics_service.dart';
import 'package:horizon/services/notification_service.dart';
import 'package:horizon/services/notification_settings_store.dart';
import 'package:horizon/services/perf_metrics.dart';
import 'package:horizon/services/theme_settings_store.dart';

class AppSettingsProvider with ChangeNotifier {
  final AnalyticsService _analytics;
  final PerfMetrics _metrics;
  final NotificationService _notifications;
  final NotificationSettingsStore _notificationStore;
  final ThemeSettingsStore _themeStore;

  ThemeSettings _themeSettings = const ThemeSettings(mode: AppThemeMode.system);
  NotificationSettings _notificationSettings = const NotificationSettings(enabled: false);

  bool _loaded = false;
  Future<void>? _loadFuture;

  AppSettingsProvider({
    required AnalyticsService analytics,
    required PerfMetrics metrics,
    required NotificationService notifications,
    required NotificationSettingsStore notificationStore,
    required ThemeSettingsStore themeStore,
  })  : _analytics = analytics,
        _metrics = metrics,
        _notifications = notifications,
        _notificationStore = notificationStore,
        _themeStore = themeStore;

  bool get loaded => _loaded;

  AppThemeMode get appThemeMode => _themeSettings.mode;
  bool get notificationsEnabled => _notificationSettings.enabled;
  AnalyticsSettings get analyticsSettings => _analytics.settings;

  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    await _analytics.load();
    await _metrics.load();
    _notificationSettings = await _notificationStore.load();
    _themeSettings = await _themeStore.load();
    if (!kIsWeb) {
      unawaited(_notifications.init());
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAppThemeMode(AppThemeMode mode) async {
    if (_themeSettings.mode == mode) return;
    _themeSettings = ThemeSettings(mode: mode);
    notifyListeners();
    await _themeStore.save(_themeSettings);
  }

  Future<void> setAnalyticsLevel(AnalyticsLevel level) async {
    await _analytics.setLevel(level);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    if (kIsWeb) {
      _notificationSettings = const NotificationSettings(enabled: false);
      notifyListeners();
      return;
    }

    if (enabled) {
      final ok = await _notifications.requestPermissions();
      if (!ok) {
        _notificationSettings = const NotificationSettings(enabled: false);
        await _notificationStore.save(_notificationSettings);
        notifyListeners();
        return;
      }
    }

    _notificationSettings = NotificationSettings(enabled: enabled);
    await _notificationStore.save(_notificationSettings);
    notifyListeners();
  }
}
