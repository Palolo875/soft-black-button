import 'package:horizon/services/secure_file_store.dart';

class NotificationSettings {
  final bool enabled;

  const NotificationSettings({required this.enabled});

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
      };

  static NotificationSettings fromJson(Map<String, dynamic> json) {
    final v = json['enabled'];
    return NotificationSettings(enabled: v is bool ? v : false);
  }
}

class NotificationSettingsStore {
  static const _key = 'notification_settings_v1';

  final SecureFileStore _store;

  NotificationSettingsStore({SecureFileStore store = const SecureFileStore()}) : _store = store;

  Future<NotificationSettings> load() async {
    final raw = await _store.readJsonDecrypted(_key);
    if (raw == null) return const NotificationSettings(enabled: false);
    return NotificationSettings.fromJson(raw);
  }

  Future<void> save(NotificationSettings s) async {
    await _store.writeJsonEncrypted(_key, s.toJson());
  }
}
