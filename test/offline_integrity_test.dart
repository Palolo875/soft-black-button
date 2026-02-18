import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/offline_integrity.dart';

void main() {
  test('sha256OfString matches sha256OfFile content', () async {
    const integrity = OfflineIntegrity();

    final dir = await Directory.systemTemp.createTemp('offline_integrity_test');
    try {
      final file = File('${dir.path}/x.txt');
      await file.writeAsString('hello');

      final a = integrity.sha256OfString('hello');
      final b = await integrity.sha256OfFile(file);
      expect(b, a);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('verifySha256 throws on mismatch (case-insensitive compare)', () async {
    const integrity = OfflineIntegrity();

    final dir = await Directory.systemTemp.createTemp('offline_integrity_test');
    try {
      final file = File('${dir.path}/x.txt');
      await file.writeAsString('hello');

      final actual = await integrity.sha256OfFile(file);
      await integrity.verifySha256(file: file, expectedHex: actual.toUpperCase());

      expect(
        () => integrity.verifySha256(file: file, expectedHex: 'deadbeef'),
        throwsException,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
