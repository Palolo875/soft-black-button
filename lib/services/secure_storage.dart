import 'dart:typed_data';

import 'dart:convert';

import 'package:horizon/core/log/app_log.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _kMasterKey = 'horizon_master_key_v1';

  final FlutterSecureStorage _storage;

  const SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<Uint8List?> readMasterKey() async {
    final b64 = await _storage.read(key: _kMasterKey);
    if (b64 == null || b64.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(b64));
    } catch (e, st) {
      AppLog.w('secureStorage.readMasterKey invalid base64', error: e, stackTrace: st);
      return null;
    }
  }

  Future<void> writeMasterKey(Uint8List keyBytes) async {
    await _storage.write(key: _kMasterKey, value: base64Encode(keyBytes));
  }

  Future<void> deleteMasterKey() async {
    await _storage.delete(key: _kMasterKey);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
