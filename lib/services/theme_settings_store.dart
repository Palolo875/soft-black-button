import 'package:horizon/services/secure_file_store.dart';

enum AppThemeMode { system, light, dark }

class ThemeSettings {
  final AppThemeMode mode;

  const ThemeSettings({required this.mode});

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
      };

  static ThemeSettings fromJson(Map<String, dynamic> json) {
    final raw = json['mode'];
    if (raw is String) {
      for (final m in AppThemeMode.values) {
        if (m.name == raw) return ThemeSettings(mode: m);
      }
    }
    return const ThemeSettings(mode: AppThemeMode.system);
  }
}

class ThemeSettingsStore {
  static const _key = 'theme_settings_v1';

  final SecureFileStore _store;

  ThemeSettingsStore({SecureFileStore store = const SecureFileStore()}) : _store = store;

  Future<ThemeSettings> load() async {
    final raw = await _store.readJsonDecrypted(_key);
    if (raw == null) return const ThemeSettings(mode: AppThemeMode.system);
    return ThemeSettings.fromJson(raw);
  }

  Future<void> save(ThemeSettings s) async {
    await _store.writeJsonEncrypted(_key, s.toJson());
  }
}
