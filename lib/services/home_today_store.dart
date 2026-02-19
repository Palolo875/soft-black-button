import 'package:horizon/services/secure_file_store.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class FavoritePlace {
  final String id;
  final String name;
  final LatLng location;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.location,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': location.latitude,
        'lng': location.longitude,
      };

  static FavoritePlace? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final lat = json['lat'];
    final lng = json['lng'];
    if (id is! String || name is! String) return null;
    if (lat is! num || lng is! num) return null;
    return FavoritePlace(
      id: id,
      name: name,
      location: LatLng(lat.toDouble(), lng.toDouble()),
    );
  }
}

class HomeTodaySettings {
  final bool enabled;
  final List<FavoritePlace> places;

  const HomeTodaySettings({
    required this.enabled,
    required this.places,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'places': places.map((p) => p.toJson()).toList(),
      };

  static HomeTodaySettings fromJson(Map<String, dynamic> json) {
    final enabledRaw = json['enabled'];
    final placesRaw = json['places'];

    final places = <FavoritePlace>[];
    if (placesRaw is List) {
      for (final item in placesRaw) {
        if (item is! Map) continue;
        final p = FavoritePlace.fromJson(Map<String, dynamic>.from(item));
        if (p != null) places.add(p);
      }
    }

    return HomeTodaySettings(
      enabled: enabledRaw is bool ? enabledRaw : false,
      places: places,
    );
  }

  static const defaults = HomeTodaySettings(enabled: false, places: []);
}

class HomeTodayStore {
  static const _key = 'home_today_settings_v1';

  final SecureFileStore _store;

  HomeTodayStore({SecureFileStore store = const SecureFileStore()}) : _store = store;

  Future<HomeTodaySettings> load() async {
    final raw = await _store.readJsonDecrypted(_key);
    if (raw == null) return HomeTodaySettings.defaults;
    return HomeTodaySettings.fromJson(raw);
  }

  Future<void> save(HomeTodaySettings s) async {
    await _store.writeJsonEncrypted(_key, s.toJson());
  }

  Future<void> clear() async {
    await _store.delete(_key);
  }
}
