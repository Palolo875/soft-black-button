import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/theme_settings_store.dart';
import 'package:horizon/services/secure_file_store.dart';

class _MemorySecureFileStore implements SecureFileStore {
  final Map<String, Map<String, dynamic>> _db = <String, Map<String, dynamic>>{};

  @override
  Future<void> writeJsonEncrypted(String name, Map<String, dynamic> jsonMap) async {
    _db[name] = Map<String, dynamic>.from(jsonMap);
  }

  @override
  Future<Map<String, dynamic>?> readJsonDecrypted(String name) async {
    final v = _db[name];
    if (v == null) return null;
    return Map<String, dynamic>.from(v);
  }

  @override
  Future<void> delete(String name) async {
    _db.remove(name);
  }

  @override
  Future<void> panicWipe() async {
    _db.clear();
  }

  @override
  Future<int> approxSizeBytes() async {
    int total = 0;
    for (final entry in _db.entries) {
      total += entry.key.length;
      for (final v in entry.value.values) {
        total += v.toString().length;
      }
    }
    return total;
  }
}

void main() {
  test('ThemeSettings roundtrip json', () {
    const s = ThemeSettings(mode: AppThemeMode.dark);
    final json = s.toJson();
    final decoded = ThemeSettings.fromJson(json);
    expect(decoded.mode, AppThemeMode.dark);
  });

  test('ThemeSettings defaults to system on invalid json', () {
    final decoded = ThemeSettings.fromJson(const {'mode': 'nope'});
    expect(decoded.mode, AppThemeMode.system);
  });

  test('ThemeSettingsStore persists mode', () async {
    final store = ThemeSettingsStore(store: _MemorySecureFileStore());

    final initial = await store.load();
    expect(initial.mode, AppThemeMode.system);

    await store.save(const ThemeSettings(mode: AppThemeMode.dark));
    final afterSave = await store.load();
    expect(afterSave.mode, AppThemeMode.dark);

    await store.save(const ThemeSettings(mode: AppThemeMode.light));
    final afterOverwrite = await store.load();
    expect(afterOverwrite.mode, AppThemeMode.light);
  });
}
