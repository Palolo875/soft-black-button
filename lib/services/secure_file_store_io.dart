import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/core/log/app_log.dart';
import 'package:app/services/local_crypto.dart';
import 'package:app/services/secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class SecureFileStore {
  static const _folderName = 'horizon_secure_store';

  final SecureStorage _secureStorage;
  final LocalCrypto _crypto;

  const SecureFileStore({
    SecureStorage secureStorage = const SecureStorage(),
    LocalCrypto crypto = const LocalCrypto(),
  })  : _secureStorage = secureStorage,
        _crypto = crypto;

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Uint8List> _getOrCreateMasterKey() async {
    final existing = await _secureStorage.readMasterKey();
    if (existing != null && existing.length == 32) return existing;
    final mk = await _crypto.newMasterKey();
    await _secureStorage.writeMasterKey(mk);
    return mk;
  }

  String _safeName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  Future<void> writeJsonEncrypted(String name, Map<String, dynamic> jsonMap) async {
    final dir = await _dir();
    final file = File('${dir.path}/${_safeName(name)}.bin');
    final key = await _getOrCreateMasterKey();

    final bytes = Uint8List.fromList(utf8.encode(json.encode(jsonMap)));
    final blob = await _crypto.encryptBytes(plaintext: bytes, key: key, aad: utf8.encode(name));

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(blob, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Future<Map<String, dynamic>?> readJsonDecrypted(String name) async {
    final dir = await _dir();
    final file = File('${dir.path}/${_safeName(name)}.bin');
    if (!await file.exists()) return null;

    final key = await _secureStorage.readMasterKey();
    if (key == null || key.length != 32) return null;

    try {
      final blob = await file.readAsBytes();
      final clear = await _crypto.decryptBytes(blob: Uint8List.fromList(blob), key: key, aad: utf8.encode(name));
      final decoded = json.decode(utf8.decode(clear));
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded as Map);
    } catch (e, st) {
      AppLog.w('secureFileStore.readJsonDecrypted failed', error: e, stackTrace: st, props: {'name': name});
      return null;
    }
  }

  Future<void> delete(String name) async {
    final dir = await _dir();
    final file = File('${dir.path}/${_safeName(name)}.bin');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> panicWipe() async {
    final dir = await _dir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await _secureStorage.deleteAll();
  }

  Future<int> approxSizeBytes() async {
    final dir = await _dir();
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (err, st) {
          AppLog.w('secureFileStore.approxSizeBytes failed', error: err, stackTrace: st, props: {'path': e.path});
        }
      }
    }
    return total;
  }
}
