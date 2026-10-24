import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/services/routing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('coarse phone position previews a foot route without glasses', () async {
    SharedPreferences.setMockInitialValues({});
    var requested = 0;
    final service = RoutingService(
      client: MockClient((request) async {
        requested++;
        expect(request.url.queryParameters['profile'], 'foot');
        return http.Response(
          jsonEncode({
            'paths': [
              {
                'distance': 111.0,
                'time': 90000,
                'points': {
                  'coordinates': [
                    [106.0, 10.0],
                    [106.0, 10.001],
                  ],
                },
                'instructions': [
                  {
                    'text': 'Đi thẳng',
                    'sign': 0,
                    'interval': [0, 1],
                  },
                  {
                    'text': 'Đến đích',
                    'sign': 4,
                    'interval': [1, 1],
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..key = 'test-only';
    final state = AppState(routingService: service);
    state.prefs = await SharedPreferences.getInstance();
    state.destination = demoRoute().destination;
    state.location = demoRoute().points.first;
    state.accuracy = 65;
    state.fixAt = DateTime.now();
    expect(state.freshFix, isFalse);
    expect(state.routePreviewFix, isTrue);
    expect(state.link.connected, isFalse);
    await state.plan();
    expect(requested, 1);
    expect(state.journey, JourneyState.ready);
    expect(state.route, isNotNull);
    expect(state.notice, contains('sai số khoảng 65 m'));
    expect(state.active, isFalse);
    state.dispose();
  });

  test(
    'preview rejects stale or very imprecise position; turns keep 20m limit',
    () {
      final state = AppState();
      state.location = demoRoute().points.first;
      state.fixAt = DateTime.now();
      state.accuracy = 20;
      expect(state.freshFix, isTrue);
      state.accuracy = 21;
      expect(state.freshFix, isFalse);
      expect(state.routePreviewFix, isTrue);
      state.accuracy = 101;
      expect(state.routePreviewFix, isFalse);
      state.accuracy = 10;
      state.fixAt = DateTime.now().subtract(const Duration(seconds: 31));
      expect(state.routePreviewFix, isFalse);
      state.dispose();
    },
  );
}
