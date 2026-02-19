import 'package:horizon/services/comfort_profile.dart';

import 'travel_mode.dart';

class ExposureProfile {
  final TravelMode mode;

  final double weightRain;
  final double weightTemperature;
  final double weightHeadwind;
  final double weightCrosswind;
  final double weightHumidity;
  final double weightNight;

  const ExposureProfile({
    required this.mode,
    this.weightRain = 1.0,
    this.weightTemperature = 1.0,
    this.weightHeadwind = 1.0,
    this.weightCrosswind = 0.6,
    this.weightHumidity = 0.3,
    this.weightNight = 0.25,
  });

  ComfortProfile toComfortProfile() {
    return ComfortProfile(
      weightRain: weightRain,
      weightTemperature: weightTemperature,
      weightHeadwind: weightHeadwind,
      weightCrosswind: weightCrosswind,
      weightHumidity: weightHumidity,
      weightNight: weightNight,
    );
  }

  static ExposureProfile defaultsFor(TravelMode mode) {
    switch (mode) {
      case TravelMode.stay:
        return const ExposureProfile(mode: TravelMode.stay, weightHeadwind: 0.0, weightCrosswind: 0.0);
      case TravelMode.walking:
        return const ExposureProfile(mode: TravelMode.walking, weightHeadwind: 0.2, weightCrosswind: 0.2);
      case TravelMode.cycling:
        return const ExposureProfile(mode: TravelMode.cycling);
      case TravelMode.car:
        return const ExposureProfile(mode: TravelMode.car, weightHeadwind: 0.0, weightCrosswind: 0.0, weightNight: 0.1, weightRain: 0.35);
      case TravelMode.motorbike:
        return const ExposureProfile(mode: TravelMode.motorbike, weightCrosswind: 0.9, weightHeadwind: 0.8, weightRain: 1.1);
    }
  }
}
