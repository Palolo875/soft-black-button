import 'dart:convert';

import 'package:app/services/secure_file_store.dart';

class PerfMetricSample {
  final String name;
  final int ms;
  final DateTime at;
  final Map<String, dynamic> tags;

  const PerfMetricSample({
    required this.name,
    required this.ms,
    required this.at,
    this.tags = const {},
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'ms': ms,
        'at': at.toIso8601String(),
        'tags': tags,
      };
}

class PerfCounters {
  final Map<String, int> counts;

  const PerfCounters({required this.counts});

  Map<String, dynamic> toJson() => {
        'counts': counts,
      };

  static PerfCounters fromJson(Map<String, dynamic> json) {
    final raw = json['counts'];
    if (raw is! Map) return const PerfCounters(counts: {});
    final out = <String, int>{};
    for (final e in raw.entries) {
      if (e.key is String && e.value is num) {
        out[e.key as String] = (e.value as num).toInt();
      }
    }
    return PerfCounters(counts: out);
  }
}

class PerfMetrics {
  static const _key = 'perf_metrics_v1';

  final SecureFileStore _store;
  final List<PerfMetricSample> _samples = [];
  final Map<String, int> _counts = {};

  PerfMetrics({SecureFileStore store = const SecureFileStore()}) : _store = store;

  List<PerfMetricSample> get samples => List.unmodifiable(_samples);
  Map<String, int> get counts => Map.unmodifiable(_counts);

  Future<void> load() async {
    final raw = await _store.readJsonDecrypted(_key);
    if (raw == null) return;
    final c = PerfCounters.fromJson(raw);
    _counts
      ..clear()
      ..addAll(c.counts);

    final s = raw['samples'];
    if (s is List) {
      _samples.clear();
      for (final e in s) {
        if (e is! Map) continue;
        final name = e['name'];
        final ms = e['ms'];
        final at = e['at'];
        if (name is! String || ms is! num || at is! String) continue;
        final dt = DateTime.tryParse(at);
        if (dt == null) continue;
        final tagsRaw = e['tags'];
        _samples.add(PerfMetricSample(
          name: name,
          ms: ms.toInt(),
          at: dt,
          tags: tagsRaw is Map ? Map<String, dynamic>.from(tagsRaw) : const {},
        ));
      }
    }
  }

  void inc(String name) {
    _counts[name] = (_counts[name] ?? 0) + 1;
  }

  void recordDuration(String name, int ms, {Map<String, dynamic> tags = const {}}) {
    _samples.add(PerfMetricSample(name: name, ms: ms, at: DateTime.now().toUtc(), tags: tags));
    if (_samples.length > 120) {
      _samples.removeRange(0, _samples.length - 120);
    }
  }

  Future<void> flush() async {
    await _store.writeJsonEncrypted(_key, {
      ...PerfCounters(counts: _counts).toJson(),
      'samples': _samples.map((e) => e.toJson()).toList(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> clear() async {
    _samples.clear();
    _counts.clear();
    await _store.delete(_key);
  }

  Future<String> exportJson() async {
    return json.encode({
      ...PerfCounters(counts: _counts).toJson(),
      'samples': _samples.map((e) => e.toJson()).toList(),
    });
  }
}
