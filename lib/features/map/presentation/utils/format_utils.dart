/// Presentation-layer formatting helpers shared by map screen widgets.

String formatBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * kb;
  const gb = 1024 * mb;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}

double msToKmh(double ms) => ms * 3.6;

String formatDurationFromSeconds(double seconds) {
  final total = seconds.isFinite ? seconds.round() : 0;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  if (h <= 0) return '${m} min';
  return '${h} h ${m.toString().padLeft(2, '0')}';
}

String routeVariantTitle(String kindName) {
  switch (kindName) {
    case 'fast':
      return 'Route rapide';
    case 'safe':
      return 'Route sûre';
    case 'scenic':
      return 'Route calme';
    case 'imported':
      return 'Route GPX';
    default:
      return 'Route';
  }
}

String routeVariantLabel(String kindName) {
  switch (kindName) {
    case 'fast':
      return 'Rapide';
    case 'safe':
      return 'Sûre';
    case 'scenic':
      return 'Calme';
    case 'imported':
      return 'GPX';
    default:
      return kindName;
  }
}
