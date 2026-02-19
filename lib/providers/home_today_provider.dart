import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:horizon/core/constants/horizon_constants.dart';
import 'package:horizon/services/home_today_engine.dart';
import 'package:horizon/services/home_today_store.dart';
import 'package:horizon/services/notification_service.dart';

class HomeTodayProvider with ChangeNotifier {
  final HomeTodayStore _store;
  final HomeTodayEngine _engine;
  final NotificationService _notifications;

  HomeTodaySettings _settings = HomeTodaySettings.defaults;
  HomeTodaySummary? _summary;

  bool _loaded = false;
  bool _notificationsEnabled = false;
  DateTime? _lastNotificationAt;

  Future<void>? _loadFuture;

  HomeTodayProvider({
    required HomeTodayStore store,
    required HomeTodayEngine engine,
    required NotificationService notifications,
  })  : _store = store,
        _engine = engine,
        _notifications = notifications;

  bool get loaded => _loaded;
  HomeTodaySettings get settings => _settings;
  HomeTodaySummary? get summary => _summary;

  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    _settings = await _store.load();
    _loaded = true;
    notifyListeners();
    unawaited(refresh());
  }

  void syncNotificationsEnabledFromSettings(bool enabled) {
    _notificationsEnabled = enabled;
  }

  Future<void> setEnabled(bool enabled) async {
    if (_settings.enabled == enabled) return;
    _settings = HomeTodaySettings(enabled: enabled, places: _settings.places);
    notifyListeners();
    await _store.save(_settings);
    unawaited(refresh());
  }

  Future<void> upsertPlace(FavoritePlace place) async {
    final next = [..._settings.places];
    final idx = next.indexWhere((p) => p.id == place.id);
    if (idx >= 0) {
      next[idx] = place;
    } else {
      next.add(place);
    }
    _settings = HomeTodaySettings(enabled: _settings.enabled, places: next);
    notifyListeners();
    await _store.save(_settings);
    unawaited(refresh());
  }

  Future<void> removePlace(String id) async {
    final next = _settings.places.where((p) => p.id != id).toList();
    _settings = HomeTodaySettings(enabled: _settings.enabled, places: next);
    notifyListeners();
    await _store.save(_settings);
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!_loaded) return;
    if (!_settings.enabled) {
      if (_summary != null) {
        _summary = null;
        notifyListeners();
      }
      return;
    }
    if (_settings.places.isEmpty) {
      if (_summary != null) {
        _summary = null;
        notifyListeners();
      }
      return;
    }

    final s = await _engine.compute(places: _settings.places);
    _summary = s;
    notifyListeners();

    if (_notificationsEnabled) {
      await _maybeNotify(s);
    }
  }

  Future<void> _maybeNotify(HomeTodaySummary s) async {
    final now = DateTime.now();
    final last = _lastNotificationAt;
    if (last != null && now.difference(last) < HorizonConstants.notificationCooldown) return;

    if (s.bestWindows.isEmpty) return;
    PlaceWindowCandidate? best;
    double bestScore = double.negativeInfinity;
    for (final c in s.bestWindows) {
      final score = (c.decision.comfortScore * 1.0) + (c.decision.confidence * 1.0) - (c.decision.now.precipitation * 0.6);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best == null) return;

    final delta = best.atUtc.toLocal().difference(now);
    if (delta.isNegative || delta > const Duration(hours: 3)) return;

    final rain = best.decision.now.precipitation;
    if (rain >= 1.0) return;

    final comfort = best.decision.comfortScore;
    if (comfort < 6.5) return;

    final t = best.atUtc.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');

    await _notifications.show(
      title: 'Fenêtre météo favorable',
      body: '${best.place.name} : conditions estimées favorables vers $hh:$mm.',
    );
    _lastNotificationAt = DateTime.now();
  }
}
