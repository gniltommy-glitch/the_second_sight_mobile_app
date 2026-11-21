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
  WalkRoute? cannedRoute;

  @override
  Future<WalkRoute> route(LatLng from, Place to) async {
    routeCallCount++;
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

  test('path_blocked message immediately reroutes active navigation', () async {
    final mockRouting = MockRoutingService();
    final state = AppState(routingService: mockRouting);
    addTearDown(state.dispose);
    await state.init();

    state.demo = false;
    final initialDest = Place('Chợ Bến Thành', const LatLng(10.772, 106.698));
    state.destination = initialDest;
    state.location = const LatLng(10.762, 106.660);
    state.accuracy = 4.0;
    state.fixAt = DateTime.now();
    state.journey = JourneyState.navigating;
    final initialRevision = state.snapshot['revision'] as int;

    expect(state.isPathBlocked, isFalse);

    // Kính gửi tín hiệu phát hiện điểm mù chắn đường
    state.handlePiMessage({
      'type': 'path_blocked',
      'reason': 'blind_spot',
      'avoid_direction': 'left',
      'distance_m': 3.5,
    });

    expect(state.isPathBlocked, isTrue);
    expect(state.pathBlockedReason, 'blind_spot');
    expect(state.pathBlockedDirection, 'left');
    expect(state.events.any((e) => e['type'] == 'path_blocked'), isTrue);

    // Đợi async reroute hoàn thành
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(mockRouting.routeCallCount, 1);
    expect(state.route, isNotNull);
    expect(state.route!.id, 'rerouted-route-id');
    expect((state.snapshot['revision'] as int) > initialRevision, isTrue);
    expect(state.events.any((e) => e['type'] == 'reroute_success'), isTrue);
    expect(state.notice, contains('bên trái'));
  });

  test('hazard message with blind_spot class triggers reroute', () async {
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
      'hazard_class': 'blind_spot',
      'avoid_direction': 'right',
      'message': 'Cảnh báo điểm mù phía trước',
    });

    expect(state.isPathBlocked, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(mockRouting.routeCallCount, 1);
    expect(state.events.any((e) => e['type'] == 'reroute_success'), isTrue);
    expect(state.notice, contains('bên phải'));
  });

  test(
    'demoPathBlocked simulates rerouting with detour in demo mode',
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

      state.demoPathBlocked(reason: 'blind_spot', avoidDirection: 'left');

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

    state.handlePiMessage({'type': 'path_blocked', 'reason': 'blind_spot'});

    expect(state.isPathBlocked, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(mockRouting.routeCallCount, 0);
  });
}
