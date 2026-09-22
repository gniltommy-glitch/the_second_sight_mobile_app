import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

double meters(LatLng a, LatLng b) => const Distance().as(LengthUnit.Meter, a, b);
List<double> xy(LatLng p) => [p.longitude, p.latitude];
LatLng coordinate(dynamic p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());

class Place {
  final String name;
  final LatLng point;
  const Place(this.name, this.point);
  Map<String, dynamic> toJson() => {'name': name, 'point': xy(point)};
  factory Place.fromJson(Map<String, dynamic> j) => Place(j['name'], coordinate(j['point']));
}

class Maneuver {
  final String text, street, action;
  final int index;
  const Maneuver(this.text, this.street, this.action, this.index);
  Map<String, dynamic> toJson() => {'text': text, 'street': street, 'action': action, 'index': index};
  factory Maneuver.fromJson(Map<String, dynamic> j) => Maneuver(j['text'], j['street'], j['action'], j['index']);
  static String actionFor(int sign) => switch (sign) {
    -7 || -3 || -2 || -1 => 'turn_left',
    1 || 2 || 3 || 7 => 'turn_right',
    4 => 'arrive',
    6 || -6 => 'roundabout',
    -8 || 8 => 'u_turn',
    _ => 'continue',
  };
}

class WalkRoute {
  final String id;
  final Place destination;
  final List<LatLng> points;
  final List<Maneuver> steps;
  final double distance, seconds;
  final DateTime created;
  final bool demo;
  late final List<double> cumulative = _lengths();
  WalkRoute({required this.id, required this.destination, required this.points,
    required this.steps, required this.distance, required this.seconds,
    required this.created, this.demo = false});
  List<double> _lengths() {
    final result = <double>[0];
    for (var i = 1; i < points.length; i++) {
      result.add(result.last + meters(points[i - 1], points[i]));
    }
    return result;
  }
  Map<String, dynamic> toJson() => {
    'id': id, 'destination': destination.toJson(), 'points': points.map(xy).toList(),
    'steps': steps.map((s) => s.toJson()).toList(), 'distance': distance,
    'seconds': seconds, 'created': created.toIso8601String(), 'demo': demo,
  };
  factory WalkRoute.fromJson(Map<String, dynamic> j) => WalkRoute(
    id: j['id'], destination: Place.fromJson(j['destination']),
    points: (j['points'] as List).map(coordinate).toList(),
    steps: (j['steps'] as List).map((s) => Maneuver.fromJson(s)).toList(),
    distance: (j['distance'] as num).toDouble(), seconds: (j['seconds'] as num).toDouble(),
    created: DateTime.parse(j['created']), demo: j['demo'] == true,
  );
}

class Projection {
  final int segment;
  final double offRoute, progress;
  const Projection(this.segment, this.offRoute, this.progress);
}

/// Local planar projection, sufficient for short pedestrian route segments.
/// Search near prior progress to avoid jumping across a loop or parallel street.
Projection project(WalkRoute route, LatLng p, {int? previous}) {
  var best = const Projection(0, double.infinity, 0);
  final first = previous == null ? 0 : math.max(0, previous - 8);
  final last = previous == null ? route.points.length - 1 : math.min(route.points.length - 1, previous + 35);
  final scale = math.cos(p.latitude * math.pi / 180);
  for (var i = first; i < last; i++) {
    final a = route.points[i], b = route.points[i + 1];
    final ax = (a.longitude - p.longitude) * 111320 * scale;
    final ay = (a.latitude - p.latitude) * 111320;
    final bx = (b.longitude - p.longitude) * 111320 * scale;
    final by = (b.latitude - p.latitude) * 111320;
    final dx = bx - ax, dy = by - ay;
    final length2 = dx * dx + dy * dy;
    final t = length2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / length2).clamp(0.0, 1.0);
    final distance = math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2));
    if (distance < best.offRoute) {
      best = Projection(i, distance, route.cumulative[i] + t * (route.cumulative[i + 1] - route.cumulative[i]));
    }
  }
  return best;
}

class NavProgress {
  final int step;
  final double distanceToStep, remaining;
  final bool arrived;
  const NavProgress(this.step, this.distanceToStep, this.remaining, this.arrived);
}
NavProgress progressFor(WalkRoute r, Projection p, LatLng location) {
  var next = r.steps.length - 1;
  for (var i = 0; i < r.steps.length; i++) {
    if (r.cumulative[r.steps[i].index] > p.progress + 6) { next = i; break; }
  }
  final remain = math.max(0.0, r.cumulative.last - p.progress);
  return NavProgress(next, math.max(0.0, r.cumulative[r.steps[next].index] - p.progress), remain,
    remain < 12 && meters(location, r.points.last) < 15 && p.offRoute < 20);
}
