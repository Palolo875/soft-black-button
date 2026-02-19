import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:horizon/core/mobility/mobility_profile.dart';
import 'package:horizon/core/mobility/travel_mode.dart';
import 'package:horizon/services/comfort_profile.dart';
import 'package:horizon/services/mobility_settings_store.dart';

class MobilityProvider with ChangeNotifier {
  final MobilitySettingsStore _store;

  MobilitySettings _settings = const MobilitySettings(mode: TravelMode.cycling);

  bool _loaded = false;
  Future<void>? _loadFuture;

  MobilityProvider({required MobilitySettingsStore store}) : _store = store;

  bool get loaded => _loaded;

  TravelMode get mode => _settings.mode;

  double? get speedOverrideMetersPerSecond => _settings.speedMetersPerSecond;

  double get defaultSpeedMetersPerSecond {
    return MobilityProfile.defaultsFor(mode).pace.speedMetersPerSecond;
  }

  double get speedMetersPerSecond {
    final override = _settings.speedMetersPerSecond;
    if (override != null && override > 0) return override;
    return MobilityProfile.defaultsFor(mode).pace.speedMetersPerSecond;
  }

  ComfortProfile get comfortProfile {
    return MobilityProfile.defaultsFor(mode).exposure.toComfortProfile();
  }

  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    _settings = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(TravelMode next) async {
    if (_settings.mode == next) return;
    _settings = MobilitySettings(mode: next, speedMetersPerSecond: _settings.speedMetersPerSecond);
    notifyListeners();
    await _store.save(_settings);
  }

  Future<void> setSpeedMetersPerSecond(double? speed) async {
    final normalized = (speed != null && speed > 0) ? speed : null;
    if (_settings.speedMetersPerSecond == normalized) return;
    _settings = MobilitySettings(mode: _settings.mode, speedMetersPerSecond: normalized);
    notifyListeners();
    await _store.save(_settings);
  }

  Future<void> resetToDefaults() async {
    _settings = const MobilitySettings(mode: TravelMode.cycling);
    notifyListeners();
    await _store.clear();
  }
}
