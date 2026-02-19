import 'exposure_profile.dart';
import 'pace_model.dart';
import 'travel_mode.dart';

class MobilityProfile {
  final TravelMode mode;
  final ExposureProfile exposure;
  final PaceModel pace;

  const MobilityProfile({
    required this.mode,
    required this.exposure,
    required this.pace,
  });

  static MobilityProfile defaultsFor(TravelMode mode) {
    return MobilityProfile(
      mode: mode,
      exposure: ExposureProfile.defaultsFor(mode),
      pace: PaceModel.defaultsFor(mode),
    );
  }
}
