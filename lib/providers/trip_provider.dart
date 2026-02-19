import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:horizon/core/constants/horizon_constants.dart';
import 'package:horizon/core/format/friendly_error.dart';
import 'package:horizon/providers/mobility_provider.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/trip_engine.dart';
import 'package:horizon/services/trip_models.dart';
import 'package:horizon/services/trip_store.dart';

class TripProvider with ChangeNotifier {
  final TripEngine _engine;
  final TripStore _store;

  MobilityProvider? _mobility;
  VoidCallback? _mobilityListener;

  bool? _isOnline;
  bool _lowPowerMode = false;
  double _timeOffset = 0.0;

  bool _loaded = false;
  Future<void>? _loadFuture;

  TripStoreState _state = TripStoreState.defaults;
  TripPlan? _currentPlan;

  List<RouteVariant> _variants = const [];
  RouteVariantKind _selectedVariant = RouteVariantKind.fast;

  bool _loading = false;
  String? _error;

  DateTime? _lastComputeAt;

  TripProvider({
    required TripEngine engine,
    required TripStore store,
  })  : _engine = engine,
        _store = store;

  bool get loaded => _loaded;
  List<TripPlan> get plans => _state.plans;
  TripPlan? get currentPlan => _currentPlan;

  List<RouteVariant> get variants => _variants;
  RouteVariantKind get selectedVariant => _selectedVariant;

  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    _state = await _store.load();
    _loaded = true;

    final selectedId = _state.selectedPlanId;
    TripPlan? resolved;
    if (selectedId != null) {
      for (final p in _state.plans) {
        if (p.id == selectedId) {
          resolved = p;
          break;
        }
      }
    }
    resolved ??= _state.plans.isNotEmpty ? _state.plans.first : null;
    _currentPlan = resolved;

    notifyListeners();
    unawaited(computeTripVariants(userInitiated: false));
  }

  void attachMobility(MobilityProvider mobility) {
    if (identical(_mobility, mobility)) return;
    final old = _mobility;
    final oldListener = _mobilityListener;
    if (old != null && oldListener != null) {
      old.removeListener(oldListener);
    }

    _mobility = mobility;
    _mobilityListener = _onMobilityChanged;
    mobility.addListener(_mobilityListener!);
  }

  void _onMobilityChanged() {
    unawaited(computeTripVariants(userInitiated: false));
  }

  void syncIsOnline(bool? isOnline) {
    _isOnline = isOnline;
  }

  void syncLowPowerMode(bool enabled) {
    _lowPowerMode = enabled;
  }

  void syncTimeOffset(double value) {
    _timeOffset = value;
  }

  DateTime _forecastBaseUtc() {
    final minutes = (_timeOffset * 60).round();
    return DateTime.now().toUtc().add(Duration(minutes: minutes));
  }

  Future<void> setCurrentPlan(TripPlan? plan) async {
    _currentPlan = plan;
    _variants = const [];
    _error = null;
    notifyListeners();

    final nextSelected = plan?.id;
    _state = TripStoreState(selectedPlanId: nextSelected, plans: _state.plans);
    await _store.save(_state);

    unawaited(computeTripVariants(userInitiated: true));
  }

  Future<void> upsertPlan(TripPlan plan, {bool select = true}) async {
    final next = [..._state.plans];
    final idx = next.indexWhere((p) => p.id == plan.id);
    if (idx >= 0) {
      next[idx] = plan;
    } else {
      next.add(plan);
    }

    final selectedPlanId = select ? plan.id : _state.selectedPlanId;
    _state = TripStoreState(selectedPlanId: selectedPlanId, plans: next);
    await _store.save(_state);

    if (select) {
      await setCurrentPlan(plan);
      return;
    }

    notifyListeners();
  }

  Future<void> removePlan(String id) async {
    final next = _state.plans.where((p) => p.id != id).toList();
    final selectedPlanId = _state.selectedPlanId == id ? (next.isNotEmpty ? next.first.id : null) : _state.selectedPlanId;
    _state = TripStoreState(selectedPlanId: selectedPlanId, plans: next);
    await _store.save(_state);

    if (_currentPlan?.id == id) {
      _currentPlan = next.isNotEmpty ? next.first : null;
      _variants = const [];
      _selectedVariant = RouteVariantKind.fast;
    }
    notifyListeners();
    unawaited(computeTripVariants(userInitiated: false));
  }

  void selectVariant(RouteVariantKind kind) {
    if (_selectedVariant == kind) return;
    _selectedVariant = kind;
    notifyListeners();
  }

  Future<void> computeTripVariants({required bool userInitiated}) async {
    if (!_loaded) return;
    final plan = _currentPlan;
    if (plan == null) return;
    if ((_isOnline ?? true) == false) return;

    final now = DateTime.now();
    final last = _lastComputeAt;
    if (!userInitiated && last != null && now.difference(last) < HorizonConstants.routeComputeThrottle) {
      return;
    }
    _lastComputeAt = now;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final speed = _mobility?.speedMetersPerSecond ?? HorizonConstants.defaultSpeedMps;
      final comfort = _mobility?.comfortProfile;

      final variants = await _engine.computeTripVariants(
        plan: plan,
        departureTimeUtc: _forecastBaseUtc(),
        speedMetersPerSecond: speed,
        comfortProfile: comfort,
        sampleEveryMeters: _lowPowerMode ? HorizonConstants.sampleIntervalMetersLowPower : HorizonConstants.sampleIntervalMeters,
        maxSamples: _lowPowerMode ? HorizonConstants.maxSamplesLowPower : HorizonConstants.maxSamples,
      );

      _variants = variants;
      if (_variants.isNotEmpty) {
        final hasSelected = _variants.any((v) => v.kind == _selectedVariant);
        if (!hasSelected) _selectedVariant = _variants.first.kind;
      }

      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = friendlyError(e);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    final m = _mobility;
    final l = _mobilityListener;
    if (m != null && l != null) {
      m.removeListener(l);
    }
    super.dispose();
  }
}
