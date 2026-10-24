import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:secondsight/services/location_policy.dart';

void main() {
  final now = DateTime.utc(2026, 10, 2, 12);
  Position fix({double accuracy = 10, int age = 0, double lat = 10}) =>
      Position(
        latitude: lat,
        longitude: 106,
        timestamp: now.subtract(Duration(seconds: age)),
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 90,
        headingAccuracy: 1,
        speed: 1,
        speedAccuracy: 1,
      );
  test('display accepts coarse fixes but rejects invalid or stale samples', () {
    expect(acceptsPosition(fix(accuracy: 20), now), isTrue);
    expect(acceptsPosition(fix(accuracy: 75), now), isTrue);
    for (final p in [
      fix(accuracy: -1),
      fix(accuracy: double.nan),
      fix(age: 9),
      fix(age: -1),
      fix(lat: 91),
    ]) {
      expect(acceptsPosition(p, now), isFalse);
    }
    expect(acceptsPosition(fix(), now, previous: now), isFalse);
    expect(acceptsPosition(fix(age: 1), now, previous: now), isFalse);
  });
  test('navigation uses FLP high priority, idle requests accurate position without wakelock', () {
    final active = locationSettingsFor(true) as AndroidSettings;
    final idle = locationSettingsFor(false) as AndroidSettings;
    expect(active.accuracy, LocationAccuracy.bestForNavigation);
    expect(idle.accuracy, LocationAccuracy.high);
    expect(active.forceLocationManager, isFalse);
    expect(active.foregroundNotificationConfig, isNotNull);
    expect(idle.foregroundNotificationConfig, isNull);
  });
}
