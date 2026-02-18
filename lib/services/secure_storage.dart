import 'dart:typed_data';

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
      return Uint8List.fromList(_decodeBase64(b64));
    } catch (e, st) {
      AppLog.w('secureStorage.readMasterKey invalid base64', error: e, stackTrace: st);
      return null;
    }
  }

  Future<void> writeMasterKey(Uint8List keyBytes) async {
    await _storage.write(key: _kMasterKey, value: _encodeBase64(keyBytes));
  }

  Future<void> deleteMasterKey() async {
    await _storage.delete(key: _kMasterKey);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}

// Local minimal base64 helpers to avoid extra deps.
const _b64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

String _encodeBase64(List<int> input) {
  final sb = StringBuffer();
  int i = 0;
  while (i < input.length) {
    final b0 = input[i++];
    final b1 = i < input.length ? input[i++] : null;
    final b2 = i < input.length ? input[i++] : null;

    final n0 = b0 >> 2;
    final n1 = ((b0 & 0x03) << 4) | ((b1 ?? 0) >> 4);
    final n2 = b1 == null ? 64 : (((b1 & 0x0F) << 2) | ((b2 ?? 0) >> 6));
    final n3 = b2 == null ? 64 : (b2 & 0x3F);

    sb.write(_b64Chars[n0]);
    sb.write(_b64Chars[n1]);
    sb.write(n2 == 64 ? '=' : _b64Chars[n2]);
    sb.write(n3 == 64 ? '=' : _b64Chars[n3]);
  }
  return sb.toString();
}

List<int> _decodeBase64(String s) {
  int idx(String c) {
    final i = _b64Chars.indexOf(c);
    if (i < 0) throw FormatException('bad base64');
    return i;
  }

  final clean = s.replaceAll(RegExp(r'\s'), '');
  if (clean.length % 4 != 0) throw FormatException('bad base64 length');
  final out = <int>[];
  for (int i = 0; i < clean.length; i += 4) {
    final c0 = clean[i];
    final c1 = clean[i + 1];
    final c2 = clean[i + 2];
    final c3 = clean[i + 3];

    final n0 = idx(c0);
    final n1 = idx(c1);
    final n2 = c2 == '=' ? 64 : idx(c2);
    final n3 = c3 == '=' ? 64 : idx(c3);

    final b0 = (n0 << 2) | (n1 >> 4);
    out.add(b0 & 0xFF);

    if (n2 != 64) {
      final b1 = ((n1 & 0x0F) << 4) | (n2 >> 2);
      out.add(b1 & 0xFF);
    }

    if (n3 != 64 && n2 != 64) {
      final b2 = ((n2 & 0x03) << 6) | n3;
      out.add(b2 & 0xFF);
    }
  }
  return out;
}
