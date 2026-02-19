import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class OfflineIntegrity {
  const OfflineIntegrity();

  Future<String> sha256OfFile(File file) async {
    final digest = await _sha256Stream(file.openRead());
    return digest.toString();
  }

  Future<Digest> _sha256Stream(Stream<List<int>> stream) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in stream) {
      input.add(chunk);
    }
    input.close();
    return output.events.single;
  }

  Future<void> verifySha256({
    required File file,
    required String expectedHex,
  }) async {
    final actual = await sha256OfFile(file);
    if (!_equalsIgnoreCase(actual, expectedHex)) {
      throw Exception('SHA-256 mismatch');
    }
  }

  bool _equalsIgnoreCase(String a, String b) {
    return a.toLowerCase() == b.toLowerCase();
  }

  String sha256OfString(String s) {
    final bytes = utf8.encode(s);
    return sha256.convert(bytes).toString();
  }
}
