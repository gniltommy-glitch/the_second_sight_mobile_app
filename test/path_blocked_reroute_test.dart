import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/core/models.dart';
import 'package:secondsight/services/routing.dart';

class MockRoutingService extends RoutingService {
  int routeCallCount = 0;
  List<LatLng> lastAvoidPoints = const [];
  WalkRoute? cannedRoute;

  @override
  Future<WalkRoute> route(
    LatLng from,
    Place to, {
    List<LatLng> avoidPoints = const [],
  }) async {
    routeCallCount++;
    lastAvoidPoints = List<LatLng>.from(avoidPoints);
    return cannedRoute ??
        WalkRoute(
          id: 'rerouted-route-id',
          destination: to,
          points: [
            from,
            LatLng(from.latitude + 0.0001, from.longitude + 0.0001),
            to.point,
          ],
          steps: const [
            Maneuver('Đi thẳng theo tuyến mới', '', 'continue', 0),
            Maneuver('Đã đến điểm đến', '', 'arrive', 2),
          ],
          distance: 120,
          seconds: 90,
          created: DateTime.now(),
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ttsChannel = MethodChannel('flutter_tts');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async => 1);
  });

  group('Cấp độ 1: Vật cản nhỏ / Điểm mù trên vỉa hè (Né cục bộ, không reroute)', () {
    test(
      'obstacle_avoid triggers local avoidance prompt and DOES NOT call routing service',
      () async {
        final mockRouting = MockRoutingService();
        final state = AppState(routingService: mockRouting);
        addTearDown(state.dispose);
        await state.init();

        state.demo = false;
        state.destination = Place('Chợ Bến Thành', const LatLng(10.772, 106.698));
        state.location = const LatLng(10.762, 106.660);
        state.journey = JourneyState.navigating;

        expect(state.hasLocalAvoidance, isFalse);
        expect(state.isPathBlocked, isFalse);

        // Kính gửi tín hiệu né vật cản cục bộ sang trái
        state.handlePiMessage({
          'type': 'obstacle_avoid',
          'avoid_direction': 'left',
          'distance_m': 2.5,
          'message': 'Có vật cản trên vỉa hè, vui lòng bước chếch sang bên trái 2 bước.',
        });

        expect(state.hasLocalAvoidance, isTrue);
        expect(state.localAvoidanceDirection, 'left');
        expect(state.localAvoidanceMessage, contains('bước chếch sang bên trái'));
        expect(state.isPathBlocked, isFalse);
        expect(state.events.any((e) => e['type'] == 'obstacle_avoid'), isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // TUYỆT ĐỐI KHÔNG gọi GraphHopper dựng lại cả route!
        expect(mockRouting.routeCallCount, 0);
        expect(state.blockedLocations, isEmpty);
      },
    );

    test('hazard with obstacle_avoid class only guides local avoidance', () async {
      final mockRouting = MockRoutingService();
      final state = AppState(routingService: mockRouting);
      addTearDown(state.dispose);
      await state.init();

      state.demo = false;
      state.destination = Place('Công viên 23/9', const LatLng(10.770, 106.690));
      state.location = const LatLng(10.760, 106.660);
      state.journey = JourneyState.navigating;

      state.handlePiMessage({
        'type': 'hazard',
        'hazard_class': 'obstacle_avoid',
        'avoid_direction': 'right',
        'distance_m': 1.8,
        'message': 'Vật cản phía trước, né sang phải',
      });

      expect(state.hasLocalAvoidance, isTrue);
      expect(state.localAvoidanceDirection, 'right');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Không gọi reroute
      expect(mockRouting.routeCallCount, 0);
    });

    test('demoObstacleAvoid activates local avoidance banner without reroute', () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.init();

      state.demo = true;
      state.route = demoRoute();
      state.journey = JourneyState.navigating;
      final originalId = state.route!.id;

      state.demoObstacleAvoid(direction: 'right', distanceM: 2.0);

      expect(state.hasLocalAvoidance, isTrue);
      expect(state.isPathBlocked, isFalse);
      expect(state.localAvoidanceDirection, 'right');
      expect(state.route!.id, equals(originalId));
    });
  });

  group('Cấp độ 2: Bị chặn hoàn toàn lối đi (Đánh dấu điểm né & gọi GraphHopper reroute)', () {
    test(
      'path_blocked marks blocked location and immediately reroutes active navigation',
      () async {
        final mockRouting = MockRoutingService();
        final state = AppState(routingService: mockRouting);
        addTearDown(state.dispose);
        await state.init();

        state.demo = false;
        final initialDest = Place('Chợ Bến Thành', const LatLng(10.772, 106.698));
        state.destination = initialDest;
        final curLoc = const LatLng(10.762, 106.660);
        state.location = curLoc;
        state.accuracy = 4.0;
        state.fixAt = DateTime.now();
        state.journey = JourneyState.navigating;
        final initialRevision = state.snapshot['revision'] as int;

        expect(state.isPathBlocked, isFalse);
        expect(state.blockedLocations, isEmpty);

        // Kính gửi tín hiệu rào chắn thi công chặn toàn bộ lối đi
        state.handlePiMessage({
          'type': 'path_blocked',
          'reason': 'construction',
          'avoid_direction': 'left',
          'distance_m': 3.5,
          'message': 'Lối đi bị rào chắn hoàn toàn do công trình.',
        });

        expect(state.isPathBlocked, isTrue);
        expect(state.pathBlockedReason, 'construction');
        expect(state.pathBlockedDirection, 'left');
        expect(state.blockedLocations, contains(curLoc));
        expect(state.events.any((e) => e['type'] == 'path_blocked'), isTrue);

        // Đợi async reroute hoàn thành
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(mockRouting.routeCallCount, 1);
        expect(mockRouting.lastAvoidPoints, contains(curLoc));
        expect(state.route, isNotNull);
        expect(state.route!.id, 'rerouted-route-id');
        expect((state.snapshot['revision'] as int) > initialRevision, isTrue);
        expect(state.events.any((e) => e['type'] == 'reroute_success'), isTrue);
        expect(state.notice, contains('bên trái'));
      },
    );

    test('hazard message with barrier/dead_end class triggers reroute', () async {
      final mockRouting = MockRoutingService();
      final state = AppState(routingService: mockRouting);
      addTearDown(state.dispose);
      await state.init();

      state.demo = false;
      state.destination = Place('Trường học', const LatLng(10.780, 106.700));
      state.location = const LatLng(10.760, 106.660);
      state.accuracy = 3.0;
      state.fixAt = DateTime.now();
      state.journey = JourneyState.navigating;

      state.handlePiMessage({
        'type': 'hazard',
        'hazard_class': 'dead_end',
        'avoid_direction': 'right',
        'message': 'Đường cụt phía trước không còn lối đi',
      });

      expect(state.isPathBlocked, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockRouting.routeCallCount, 1);
      expect(state.events.any((e) => e['type'] == 'reroute_success'), isTrue);
      expect(state.notice, contains('bên phải'));
    });

    test(
      'demoBlockedPath simulates rerouting with detour in demo mode',
      () async {
        final state = AppState();
        addTearDown(state.dispose);
        await state.init();

        state.demo = true;
        state.route = demoRoute();
        state.destination = state.route!.destination;
        state.location = state.route!.points.first;
        state.accuracy = 3.0;
        state.fixAt = DateTime.now();
        state.journey = JourneyState.navigating;
        final originalRouteId = state.route!.id;

        state.demoBlockedPath(reason: 'barrier', avoidDirection: 'left');

        expect(state.isPathBlocked, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(state.route!.id, isNot(equals(originalRouteId)));
        expect(state.route!.steps.first.text, contains('tránh vật cản'));
        expect(state.events.any((e) => e['type'] == 'reroute_success'), isTrue);
      },
    );

    test('path_blocked does not reroute when idle', () async {
      final mockRouting = MockRoutingService();
      final state = AppState(routingService: mockRouting);
      addTearDown(state.dispose);
      await state.init();

      state.journey = JourneyState.idle;

      state.handlePiMessage({'type': 'path_blocked', 'reason': 'barrier'});

      expect(state.isPathBlocked, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mockRouting.routeCallCount, 0);
    });
  });
}
