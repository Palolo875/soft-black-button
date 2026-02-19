import 'package:horizon/core/mobility/travel_mode.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class TripStop {
  final String id;
  final String name;
  final LatLng location;
  final Duration stay;

  const TripStop({
    required this.id,
    required this.name,
    required this.location,
    this.stay = Duration.zero,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': location.latitude,
        'lng': location.longitude,
        'staySeconds': stay.inSeconds,
      };

  static TripStop? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final lat = json['lat'];
    final lng = json['lng'];
    final staySeconds = json['staySeconds'];

    if (id is! String || name is! String) return null;
    if (lat is! num || lng is! num) return null;

    final stay = staySeconds is num ? Duration(seconds: staySeconds.round()) : Duration.zero;

    return TripStop(
      id: id,
      name: name,
      location: LatLng(lat.toDouble(), lng.toDouble()),
      stay: stay,
    );
  }
}

class TripPlan {
  final String id;
  final String name;
  final TravelMode mode;
  final List<TripStop> stops;

  const TripPlan({
    required this.id,
    required this.name,
    required this.mode,
    required this.stops,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode.name,
        'stops': stops.map((s) => s.toJson()).toList(),
      };

  static TripPlan? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final modeRaw = json['mode'];
    final stopsRaw = json['stops'];

    if (id is! String || name is! String) return null;
    if (modeRaw is! String) return null;

    final mode = TravelMode.values.firstWhere(
      (m) => m.name == modeRaw,
      orElse: () => TravelMode.cycling,
    );

    final stops = <TripStop>[];
    if (stopsRaw is List) {
      for (final item in stopsRaw) {
        if (item is! Map) continue;
        final s = TripStop.fromJson(Map<String, dynamic>.from(item));
        if (s != null) stops.add(s);
      }
    }

    if (stops.length < 2) return null;

    return TripPlan(
      id: id,
      name: name,
      mode: mode,
      stops: stops,
    );
  }
}
