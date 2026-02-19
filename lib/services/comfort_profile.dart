class ComfortProfile {
  final double weightRain;
  final double weightTemperature;
  final double weightHeadwind;
  final double weightCrosswind;
  final double weightHumidity;
  final double weightNight;

  const ComfortProfile({
    this.weightRain = 1.0,
    this.weightTemperature = 1.0,
    this.weightHeadwind = 1.0,
    this.weightCrosswind = 0.6,
    this.weightHumidity = 0.3,
    this.weightNight = 0.25,
  });

  Map<String, dynamic> toJson() => {
        'weightRain': weightRain,
        'weightTemperature': weightTemperature,
        'weightHeadwind': weightHeadwind,
        'weightCrosswind': weightCrosswind,
        'weightHumidity': weightHumidity,
        'weightNight': weightNight,
      };

  static ComfortProfile fromJson(Map<String, dynamic> json) {
    double d(String k, double fallback) {
      final v = json[k];
      if (v is num) return v.toDouble();
      return fallback;
    }

    return ComfortProfile(
      weightRain: d('weightRain', 1.0),
      weightTemperature: d('weightTemperature', 1.0),
      weightHeadwind: d('weightHeadwind', 1.0),
      weightCrosswind: d('weightCrosswind', 0.6),
      weightHumidity: d('weightHumidity', 0.3),
      weightNight: d('weightNight', 0.25),
    );
  }
}
