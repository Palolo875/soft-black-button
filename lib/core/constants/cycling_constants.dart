/// Centralized constants for cycling computation.
///
/// All magic numbers previously spread across providers and services
/// are gathered here for easy tuning and documentation.
class CyclingConstants {
  CyclingConstants._();

  /// Default cycling speed in m/s (~15 km/h).
  static const double defaultSpeedMps = 4.2;

  /// Weather & route sample interval in meters (normal mode).
  static const double sampleIntervalMeters = 450;

  /// Weather & route sample interval in meters (low-power mode).
  static const double sampleIntervalMetersLowPower = 900;

  /// Maximum number of weather samples per route (normal mode).
  static const int maxSamples = 120;

  /// Maximum number of weather samples per route (low-power mode).
  static const int maxSamplesLowPower = 60;

  /// Minimum delay between contextual notifications.
  static const Duration notificationCooldown = Duration(minutes: 30);

  /// Minimum delay between route computations.
  static const Duration routeComputeThrottle = Duration(seconds: 2);

  /// Debounce for route computation after setting a point.
  static const Duration routePointDebounce = Duration(milliseconds: 450);

  /// Horizon in minutes ahead for rain alerts on route.
  static const Duration weatherAlertHorizon = Duration(minutes: 45);

  /// Precipitation threshold (mm) that triggers a route rain alert.
  static const double rainAlertThresholdMm = 2.0;

  /// Confidence threshold below which rain samples are ignored for alerts.
  static const double rainAlertMinConfidence = 0.5;

  /// Departure comparison offsets.
  static const List<Duration> departureCompareOffsets = [
    Duration.zero,
    Duration(minutes: 30),
    Duration(minutes: 60),
  ];

  /// Departure window recommendation horizon.
  static const Duration departureWindowHorizon = Duration(hours: 6);

  /// Departure window recommendation step.
  static const Duration departureWindowStep = Duration(minutes: 20);

  /// Cache freshness for departure comparisons.
  static const Duration departureCompareCacheTtl = Duration(seconds: 25);

  /// Cache freshness for departure window recommendations.
  static const Duration departureWindowCacheTtl = Duration(seconds: 45);

  // --- Scheduler ---

  static const Duration weatherCooldownNormal = Duration(minutes: 15);
  static const Duration weatherCooldownLowPower = Duration(minutes: 30);
  static const Duration routingCooldownNormal = Duration(minutes: 10);
  static const Duration routingCooldownLowPower = Duration(minutes: 45);

  // --- Weather Engine & Comfort Model ---

  /// Cache grid rounding factor (50 = round to 0.02 degrees).
  static const double cacheGridFactor = 50.0;

  /// Base temperature for comfort penalty calculations (Celsius).
  static const double comfortBaseTemperature = 18.0;

  /// Threshold for "extreme" heat humidity penalty (Celsius).
  static const double heatHumidityThreshold = 22.0;

  /// Night hours range.
  static const int nightStartHour = 22;
  static const int nightEndHour = 6;

  /// Comfort score thresholds.
  static const double comfortThresholdUncertain = 0.45;
  static const double comfortThresholdBad = 4.5;

  /// Rain intensity thresholds (mm/h).
  static const double rainLight = 0.1;
  static const double rainModerate = 0.5;
  static const double rainHeavy = 1.5;
  static const double rainExtreme = 4.0;

  /// Wind speed thresholds (m/s).
  static const double windModerate = 8.0;
  static const double windBreezy = 10.0;
  static const double windStrong = 20.0;

  /// Temperature extreme thresholds (Celsius).
  static const double tempExtremelyCold = 6.0;
  static const double tempExtremelyHot = 30.0;

  /// Percentage of route length used as threshold for weather impact flags.
  static const double routeImpactDistanceRatio = 0.08;

  /// Minimum absolute distance (km) for weather impact flags.
  static const double routeImpactMinDistanceKm = 0.8;

  // --- Confidence Heuristic ---

  static const double confidenceHeuristicFallback = 0.6;
  static const double confidenceHeuristicBase = 0.85;
  static const double confidenceHeuristicRainHeavy = 2.0;
  static const double confidenceHeuristicRainExtreme = 5.0;

  // --- Routing & Cache ---

  /// Default auto-refresh interval for weather data.
  static const Duration weatherAutoRefreshInterval = Duration(minutes: 10);

  /// Rounding for route cache lookup (200 = 0.005 degrees).
  static const double routeCacheGridFactor = 200.0;

  /// Precision for polyline6 decoding/encoding.
  static const double polyline6Precision = 1e6;
}
