import 'dart:convert';

import 'dart:html' as html;

import 'package:app/core/log/app_log.dart';

class SecureFileStore {
  static const _prefix = 'horizon_secure_store_v1:';

  const SecureFileStore();

  String _k(String name) => '$_prefix$name';

  Future<void> writeJsonEncrypted(String name, Map<String, dynamic> jsonMap) async {
    html.window.localStorage[_k(name)] = json.encode(jsonMap);
  }

  Future<Map<String, dynamic>?> readJsonDecrypted(String name) async {
    final raw = html.window.localStorage[_k(name)];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded as Map);
    } catch (e, st) {
      AppLog.w('secureFileStore.web.readJsonDecrypted failed', error: e, stackTrace: st, props: {'name': name});
      return null;
    }
  }

  Future<void> delete(String name) async {
    html.window.localStorage.remove(_k(name));
  }

  Future<void> panicWipe() async {
    final keys = html.window.localStorage.keys.where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      html.window.localStorage.remove(k);
    }
  }

  Future<int> approxSizeBytes() async {
    int total = 0;
    for (final k in html.window.localStorage.keys) {
      if (!k.startsWith(_prefix)) continue;
      final v = html.window.localStorage[k];
      if (v != null) total += v.length;
    }
    return total;
  }
}
