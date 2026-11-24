import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:secondsight/core/models.dart';
import 'package:secondsight/services/routing.dart';

void main() {
  test('route explicitly requests foot and decodes longitude first', () async {
    final service = RoutingService(
      client: MockClient((request) async {
        expect(request.url.queryParameters['profile'], 'foot');
        expect(request.url.queryParametersAll['point']!.length, 2);
        expect(request.url.queryParameters['points_encoded'], 'false');

        final payload = jsonEncode({
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
        });

        return http.Response.bytes(utf8.encode(payload), 200);
      }),
    )..key = 'test-key';

    final route = await service.route(
      const LatLng(10, 106),
      const Place('Đích', LatLng(10.001, 106)),
    );
    expect(route.points.first.latitude, 10);
    expect(route.seconds, 90);
    expect(route.steps.last.action, 'arrive');
    service.dispose();
  });

  test(
    'provider errors surface instead of silently inventing a route',
    () async {
      final service = RoutingService(
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode('denied'), 403),
        ),
      )..key = 'bad';
      await expectLater(
        service.route(
          const LatLng(10, 106),
          const Place('Đích', LatLng(10.001, 106)),
        ),
        throwsException,
      );
      service.dispose();
    },
  );

  test(
    'route with avoidPoints posts GraphHopper custom_model and falls back to GET on failure',
    () async {
      final methods = <String>[];
      Map<String, dynamic>? postedBody;
      final payload = jsonEncode({
        'paths': [
          {
            'distance': 150.0,
            'time': 120000,
            'points': {
              'coordinates': [
                [106.0, 10.0],
                [106.0005, 10.0005],
                [106.0, 10.001],
              ],
            },
            'instructions': [
              {
                'text': 'Đi vòng tránh đoạn bị chặn',
                'sign': 0,
                'interval': [0, 2],
              },
              {
                'text': 'Đến đích',
                'sign': 4,
                'interval': [2, 2],
              },
            ],
          },
        ],
      });

      final service = RoutingService(
        client: MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'POST') {
            postedBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response.bytes(utf8.encode(payload), 200);
          }
          return http.Response.bytes(utf8.encode(payload), 200);
        }),
      )..key = 'test-key';

      final route = await service.route(
        const LatLng(10, 106),
        const Place('Đích', LatLng(10.001, 106)),
        avoidPoints: const [LatLng(10.0005, 106.0)],
      );
      expect(methods, ['POST']);
      expect(postedBody?['ch.disable'], isTrue);
      expect(postedBody?['profile'], 'foot');
      expect(
        (postedBody?['custom_model'] as Map)['priority'],
        isA<List>().having((l) => l.length, 'length', 1),
      );
      expect(route.distance, 150.0);
      service.dispose();

      // Verify fallback to GET if POST custom_model is rejected
      final fallbackMethods = <String>[];
      final fallbackService = RoutingService(
        client: MockClient((request) async {
          fallbackMethods.add(request.method);
          if (request.method == 'POST') {
            return http.Response.bytes(utf8.encode('not allowed'), 400);
          }
          return http.Response.bytes(utf8.encode(payload), 200);
        }),
      )..key = 'test-key';

      final fallbackRoute = await fallbackService.route(
        const LatLng(10, 106),
        const Place('Đích', LatLng(10.001, 106)),
        avoidPoints: const [LatLng(10.0005, 106.0)],
      );
      expect(fallbackMethods, ['POST', 'GET']);
      expect(fallbackRoute.distance, 150.0);
      fallbackService.dispose();
    },
  );
}
