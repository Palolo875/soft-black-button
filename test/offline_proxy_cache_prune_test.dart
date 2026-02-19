import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/offline_service.dart';

void main() {
  test('pruneProxyCacheDir removes oldest files to satisfy limits', () async {
    final dir = await Directory.systemTemp.createTemp('horizon_proxy_cache_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final f1 = File('${dir.path}/a');
    final f2 = File('${dir.path}/b');
    final f3 = File('${dir.path}/c');

    await f1.writeAsBytes(List<int>.filled(10, 1));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await f2.writeAsBytes(List<int>.filled(10, 2));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await f3.writeAsBytes(List<int>.filled(10, 3));

    await pruneProxyCacheDir(dir, maxEntries: 2, maxBytes: 1000);

    final remaining = dir
        .listSync(recursive: false)
        .whereType<File>()
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();

    expect(remaining, ['b', 'c']);
  });
}
