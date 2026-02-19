class HorizonConstants {
  HorizonConstants._();

  static const double defaultSpeedMps = 4.2;

  static const double sampleIntervalMeters = 450;
  static const double sampleIntervalMetersLowPower = 900;

  static const int maxSamples = 120;
  static const int maxSamplesLowPower = 60;

  static const Duration notificationCooldown = Duration(minutes: 30);

  static const Duration routeComputeThrottle = Duration(seconds: 2);
  static const Duration routePointDebounce = Duration(milliseconds: 450);

  static const Duration weatherAlertHorizon = Duration(minutes: 45);
  static const double rainAlertThresholdMm = 2.0;
  static const double rainAlertMinConfidence = 0.5;

  static const List<Duration> departureCompareOffsets = [
    Duration.zero,
    Duration(minutes: 30),
    Duration(minutes: 60),
  ];

  static const Duration departureWindowHorizon = Duration(hours: 6);
  static const Duration departureWindowStep = Duration(minutes: 20);

  static const Duration departureCompareCacheTtl = Duration(seconds: 25);
  static const Duration departureWindowCacheTtl = Duration(seconds: 45);

  static const Duration weatherCooldownNormal = Duration(minutes: 15);
  static const Duration weatherCooldownLowPower = Duration(minutes: 30);
  static const Duration routingCooldownNormal = Duration(minutes: 10);
  static const Duration routingCooldownLowPower = Duration(minutes: 45);

  static const double cacheGridFactor = 50.0;

  static const double comfortBaseTemperature = 18.0;
  static const double heatHumidityThreshold = 22.0;

  static const int nightStartHour = 22;
  static const int nightEndHour = 6;

  static const double comfortThresholdUncertain = 0.45;
  static const double comfortThresholdBad = 4.5;

  static const double rainLight = 0.1;
  static const double rainModerate = 0.5;
  static const double rainHeavy = 1.5;
  static const double rainExtreme = 4.0;

  static const double windModerate = 8.0;
  static const double windBreezy = 10.0;
  static const double windStrong = 20.0;

  static const double tempExtremelyCold = 6.0;
  static const double tempExtremelyHot = 30.0;

  static const double routeImpactDistanceRatio = 0.08;
  static const double routeImpactMinDistanceKm = 0.8;

  static const double confidenceHeuristicFallback = 0.6;
  static const double confidenceHeuristicBase = 0.85;
  static const double confidenceHeuristicRainHeavy = 2.0;
  static const double confidenceHeuristicRainExtreme = 5.0;

  static const Duration weatherAutoRefreshInterval = Duration(minutes: 10);

  static const double routeCacheGridFactor = 200.0;

  static const double polyline6Precision = 1e6;
}
