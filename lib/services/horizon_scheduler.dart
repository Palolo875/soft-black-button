import 'package:horizon/core/constants/cycling_constants.dart';

class SchedulerSnapshot {
  final bool appInForeground;
  final bool isOnline;
  final bool lowPowerMode;
  final bool navigationActive;
  final double? speedMps;

  const SchedulerSnapshot({
    required this.appInForeground,
    required this.isOnline,
    required this.lowPowerMode,
    required this.navigationActive,
    this.speedMps,
  });
}

enum ComputeLevel {
  inactive,
  consult,
  prepare,
  navigate,
  critical,
}

class HorizonScheduler {
  DateTime? _lastWeather;
  DateTime? _lastRouting;

  Duration weatherCooldown = CyclingConstants.weatherCooldownNormal;
  Duration routingCooldown = CyclingConstants.routingCooldownNormal;

  ComputeLevel levelFor(SchedulerSnapshot s) {
    if (!s.appInForeground) return ComputeLevel.inactive;
    if (s.navigationActive) return ComputeLevel.navigate;
    return ComputeLevel.consult;
  }

  bool shouldComputeWeather(SchedulerSnapshot s, {required bool userInitiated}) {
    final lvl = levelFor(s);
    if (lvl == ComputeLevel.inactive) return false;
    if (!s.isOnline) return false;

    final now = DateTime.now();
    if (userInitiated) {
      _lastWeather = now;
      return true;
    }

    final cd = s.lowPowerMode ? CyclingConstants.weatherCooldownLowPower : weatherCooldown;
    final last = _lastWeather;
    if (last == null || now.difference(last) >= cd) {
      _lastWeather = now;
      return true;
    }
    return false;
  }

  bool shouldComputeRouting(SchedulerSnapshot s, {required bool userInitiated}) {
    final lvl = levelFor(s);
    if (lvl == ComputeLevel.inactive) return false;
    if (!s.isOnline) return false;

    final now = DateTime.now();
    if (userInitiated) {
      _lastRouting = now;
      return true;
    }

    final cd = s.lowPowerMode ? CyclingConstants.routingCooldownLowPower : routingCooldown;
    final last = _lastRouting;
    if (last == null || now.difference(last) >= cd) {
      _lastRouting = now;
      return true;
    }
    return false;
  }

  void reset() {
    _lastWeather = null;
    _lastRouting = null;
  }
}
