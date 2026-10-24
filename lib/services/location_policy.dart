import 'package:geolocator/geolocator.dart';

/// Both modes request high accuracy; only navigation keeps a foreground service.
LocationSettings locationSettingsFor(bool navigating) => AndroidSettings(
  forceLocationManager: false,
  accuracy: navigating
      ? LocationAccuracy.bestForNavigation
      : LocationAccuracy.high,
  distanceFilter: 0,
  intervalDuration: Duration(seconds: navigating ? 1 : 5),
  foregroundNotificationConfig: navigating
      ? const ForegroundNotificationConfig(
          notificationTitle: 'SecondSight đang dẫn đường',
          notificationText: 'Đang hỗ trợ hành trình đi bộ',
          enableWakeLock: true,
        )
      : null,
);

/// Keep valid coarse fixes for display; turn guidance checks accuracy separately.
bool acceptsPosition(Position p, DateTime now, {DateTime? previous}) {
  final age = now.difference(p.timestamp);
  return p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180 &&
      p.accuracy.isFinite &&
      p.accuracy >= 0 &&
      !age.isNegative &&
      age <= const Duration(seconds: 8) &&
      (previous == null || p.timestamp.isAfter(previous));
}
