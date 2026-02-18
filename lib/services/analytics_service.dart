import 'dart:convert';

import 'package:horizon/services/secure_file_store.dart';

enum AnalyticsLevel {
  off,
  anonymous,
}

class AnalyticsEvent {
  final String name;
  final DateTime at;
  final Map<String, dynamic> props;

  const AnalyticsEvent({
    required this.name,
    required this.at,
    this.props = const {},
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'at': at.toIso8601String(),
        'props': props,
      };
}

class AnalyticsSettings {
  final AnalyticsLevel level;

  const AnalyticsSettings({required this.level});

  Map<String, dynamic> toJson() => {
        'level': level.name,
      };

  static AnalyticsSettings fromJson(Map<String, dynamic> json) {
    final raw = json['level'];
    final level = AnalyticsLevel.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AnalyticsLevel.off,
    );
    return AnalyticsSettings(level: level);
  }
}

class AnalyticsService {
  static const _settingsKey = 'analytics_settings_v1';
  static const _bufferKey = 'analytics_buffer_v1';

  final SecureFileStore _store;

  AnalyticsSettings _settings = const AnalyticsSettings(level: AnalyticsLevel.off);

  AnalyticsService({SecureFileStore store = const SecureFileStore()}) : _store = store;

  AnalyticsSettings get settings => _settings;

  Future<void> load() async {
    final raw = await _store.readJsonDecrypted(_settingsKey);
    if (raw == null) return;
    _settings = AnalyticsSettings.fromJson(raw);
  }

  Future<void> setLevel(AnalyticsLevel level) async {
    _settings = AnalyticsSettings(level: level);
    await _store.writeJsonEncrypted(_settingsKey, _settings.toJson());
  }

  Future<void> record(String name, {Map<String, dynamic> props = const {}}) async {
    if (_settings.level == AnalyticsLevel.off) return;

    final ev = AnalyticsEvent(name: name, at: DateTime.now().toUtc(), props: props);

    // Local-only buffer (no network). Purgeable via panic wipe.
    final existing = await _store.readJsonDecrypted(_bufferKey);
    final list = <Map<String, dynamic>>[];
    if (existing != null) {
      final raw = existing['events'];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
    }

    list.add(ev.toJson());
    // Keep bounded.
    if (list.length > 200) {
      list.removeRange(0, list.length - 200);
    }

    await _store.writeJsonEncrypted(_bufferKey, {
      'events': list,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> bufferedCount() async {
    final existing = await _store.readJsonDecrypted(_bufferKey);
    if (existing == null) return 0;
    final raw = existing['events'];
    if (raw is! List) return 0;
    return raw.length;
  }

  Future<void> clearBuffer() async {
    await _store.delete(_bufferKey);
  }

  // Export for user transparency (local portability). Still local only.
  Future<String?> exportBufferJson() async {
    final existing = await _store.readJsonDecrypted(_bufferKey);
    if (existing == null) return null;
    return json.encode(existing);
  }
}
