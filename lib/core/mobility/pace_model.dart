import 'travel_mode.dart';

class PaceModel {
  final double speedMetersPerSecond;

  const PaceModel({required this.speedMetersPerSecond});

  static PaceModel defaultsFor(TravelMode mode) {
    switch (mode) {
      case TravelMode.stay:
        return const PaceModel(speedMetersPerSecond: 0);
      case TravelMode.walking:
        return const PaceModel(speedMetersPerSecond: 1.35);
      case TravelMode.cycling:
        return const PaceModel(speedMetersPerSecond: 4.2);
      case TravelMode.car:
        return const PaceModel(speedMetersPerSecond: 13.9);
      case TravelMode.motorbike:
        return const PaceModel(speedMetersPerSecond: 11.1);
    }
  }
}
