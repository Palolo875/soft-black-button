import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class LocalCrypto {
  static final _rng = Random.secure();

  final AesGcm _cipher;

  const LocalCrypto({AesGcm cipher = const AesGcm.with256bits()}) : _cipher = cipher;

  Future<Uint8List> newMasterKey() async {
    final bytes = Uint8List(32);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes;
  }

  Future<Uint8List> encryptBytes({
    required Uint8List plaintext,
    required Uint8List key,
    List<int> aad = const [],
  }) async {
    final secretKey = SecretKey(key);
    final nonce = _randomNonce(12);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad,
    );

    // Layout: nonce(12) + mac(16) + ciphertext
    final macBytes = Uint8List.fromList(box.mac.bytes);
    final out = Uint8List(nonce.length + macBytes.length + box.cipherText.length);
    out.setRange(0, nonce.length, nonce);
    out.setRange(nonce.length, nonce.length + macBytes.length, macBytes);
    out.setRange(nonce.length + macBytes.length, out.length, box.cipherText);
    return out;
  }

  Future<Uint8List> decryptBytes({
    required Uint8List blob,
    required Uint8List key,
    List<int> aad = const [],
  }) async {
    if (blob.length < 12 + 16) throw Exception('ciphertext too short');
    final nonce = blob.sublist(0, 12);
    final mac = Mac(blob.sublist(12, 28));
    final cipherText = blob.sublist(28);

    final secretKey = SecretKey(key);
    final box = SecretBox(cipherText, nonce: nonce, mac: mac);
    final clear = await _cipher.decrypt(box, secretKey: secretKey, aad: aad);
    return Uint8List.fromList(clear);
  }

  Uint8List _randomNonce(int n) {
    final bytes = Uint8List(n);
    for (int i = 0; i < n; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes;
  }
}
