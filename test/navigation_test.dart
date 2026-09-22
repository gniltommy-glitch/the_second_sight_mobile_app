import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:secondsight/core/models.dart';
import 'package:secondsight/services/routing.dart';

void main() {
  test('route cache round trip preserves geometry and maneuver indices', () {
    final r = demoRoute();
    final restored = WalkRoute.fromJson(r.toJson());
    expect(restored.points.length, r.points.length);
    expect(restored.steps[1].action, 'turn_right');
    expect(restored.demo, isTrue);
    expect(restored.cumulative.last, closeTo(r.cumulative.last, .001));
  });
  test('distance to turn follows polyline and arrival needs proximity', () {
    final r = demoRoute();
    final p = project(r, r.points[5]);
    final nav = progressFor(r, p, r.points[5]);
    expect(nav.step, 1);
    expect(nav.distanceToStep, greaterThan(100));
    expect(nav.arrived, isFalse);
    final end = project(r, r.points.last);
    expect(progressFor(r, end, r.points.last).arrived, isTrue);
    expect(progressFor(r, end, const LatLng(11, 107)).arrived, isFalse);
  });
  test('segment projection detects perpendicular drift', () {
    final r = demoRoute();
    final p = project(r, LatLng(r.points[10].latitude, r.points[10].longitude - .001));
    expect(p.offRoute, greaterThan(90));
    expect(p.offRoute, lessThan(125));
  });
  test('walking actions preserve left/right/roundabout/arrival', () {
    expect(Maneuver.actionFor(-2), 'turn_left');
    expect(Maneuver.actionFor(2), 'turn_right');
    expect(Maneuver.actionFor(6), 'roundabout');
    expect(Maneuver.actionFor(4), 'arrive');
  });
}
