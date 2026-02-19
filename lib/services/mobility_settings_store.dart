import 'package:horizon/core/mobility/travel_mode.dart';
import 'package:horizon/services/secure_file_store.dart';

class MobilitySettings {
  final TravelMode mode;
  final double? speedMetersPerSecond;

  const MobilitySettings({
    required this.mode,
    this.speedMetersPerSecond,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'speedMetersPerSecond': speedMetersPerSecond,
      };

  static MobilitySettings fromJson(Map<String, dynamic> json) {
    final modeRaw = json['mode'];
    final mode = TravelMode.values.firstWhere(
      (m) => m.name == modeRaw,
      orElse: () => TravelMode.cycling,
    );

    final speedRaw = json['speedMetersPerSecond'];
    final speed = speedRaw is num ? speedRaw.toDouble() : null;

    return MobilitySettings(mode: mode, speedMetersPerSecond: speed);
  }
}

class MobilitySettingsStore {
  static const _key = 'mobility_settings_v1';

  final SecureFileStore _store;

  MobilitySettingsStore({SecureFileStore store = const SecureFileStore()}) : _store = store;

  Future<MobilitySettings> load() async {
    final raw = await _store.readJsonDecrypted(_key);
    if (raw == null) return const MobilitySettings(mode: TravelMode.cycling);
    return MobilitySettings.fromJson(raw);
  }

  Future<void> save(MobilitySettings s) async {
    await _store.writeJsonEncrypted(_key, s.toJson());
  }

  Future<void> clear() async {
    await _store.delete(_key);
  }
}
