import 'package:horizon/services/secure_file_store.dart';
import 'package:horizon/services/trip_models.dart';

class TripStoreState {
  final String? selectedPlanId;
  final List<TripPlan> plans;

  const TripStoreState({
    required this.selectedPlanId,
    required this.plans,
  });

  Map<String, dynamic> toJson() => {
        'selectedPlanId': selectedPlanId,
        'plans': plans.map((p) => p.toJson()).toList(),
      };

  static TripStoreState fromJson(Map<String, dynamic> json) {
    final selected = json['selectedPlanId'];
    final plansRaw = json['plans'];

    final plans = <TripPlan>[];
    if (plansRaw is List) {
      for (final item in plansRaw) {
        if (item is! Map) continue;
        final p = TripPlan.fromJson(Map<String, dynamic>.from(item));
        if (p != null) plans.add(p);
      }
    }

    final selectedPlanId = selected is String ? selected : null;

    return TripStoreState(selectedPlanId: selectedPlanId, plans: plans);
  }

  static const defaults = TripStoreState(selectedPlanId: null, plans: []);
}

class TripStore {
  static const _key = 'trip_store_v1';

  final SecureFileStore _store;

  TripStore({SecureFileStore store = const SecureFileStore()}) : _store = store;

  Future<TripStoreState> load() async {
    final raw = await _store.readJsonDecrypted(_key);
    if (raw == null) return TripStoreState.defaults;
    return TripStoreState.fromJson(raw);
  }

  Future<void> save(TripStoreState s) async {
    await _store.writeJsonEncrypted(_key, s.toJson());
  }

  Future<void> clear() async {
    await _store.delete(_key);
  }
}
