import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/services/pairing_config.dart';
import 'package:secondsight/services/voice_intent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Caregiver pairing & voice intent extensions', () {
    test('PairingConfig parses optional relay_endpoint while preserving v1 format', () {
      const qrWithRelay = '''
      {
        "type": "secondsight_pairing",
        "version": 1,
        "endpoint": "http://secondsight.local:8765",
        "token": "secret-token-0123456789abcdef",
        "routing_key": "gh-demo",
        "allow_insecure": true,
        "relay_endpoint": "http://192.168.1.50:8787"
      }
      ''';
      final parsed = PairingConfig.parse(qrWithRelay);
      expect(parsed.endpoint, 'http://secondsight.local:8765');
      expect(parsed.token, 'secret-token-0123456789abcdef');
      expect(parsed.allowInsecure, isTrue);
      expect(parsed.relayEndpoint, 'http://192.168.1.50:8787');

      const legacyQr = '''
      {
        "type": "secondsight_pairing",
        "version": 1,
        "endpoint": "https://secondsight.local:8765",
        "token": "secret-token-0123456789abcdef",
        "allow_insecure": false
      }
      ''';
      final legacy = PairingConfig.parse(legacyQr);
      expect(legacy.relayEndpoint, isNull);
    });

    test('VoiceIntent parses askCaregiver and sosCaregiver without breaking existing intents', () {
      expect(
        parseIntent('Aurelia ơi gửi ảnh hỏi người thân').command,
        VoiceCommand.askCaregiver,
      );
      expect(
        parseIntent('Nhờ người thân xem giúp biển số xe buýt').command,
        VoiceCommand.askCaregiver,
      );
      expect(
        parseIntent('Aurelia cứu tôi với').command,
        VoiceCommand.sosCaregiver,
      );
      // Existing intents remain intact
      expect(
        parseIntent('dừng dẫn đường').command,
        VoiceCommand.stop,
      );
      expect(
        parseIntent('gọi cho Mẹ').command,
        VoiceCommand.call,
      );
      expect(
        parseIntent('chia sẻ vị trí cho Ba').command,
        VoiceCommand.shareLocation,
      );
    });
  });

  group('End-to-end Pi + Wearer App + Caregiver Relay bridge', () {
    late HttpServer mockPiServer;
    late HttpServer mockRelayServer;
    final receivedRelayPosts = <String, List<Map<String, dynamic>>>{};
    final receivedPiPosts = <String, List<Map<String, dynamic>>>{};
    WebSocket? wearerWsOnRelay;

    const testToken = 'caregiver-e2e-token-0123456789abcdef';

    setUp(() async {
      SharedPreferences.setMockInitialValues({'demo_mode': false});
      receivedRelayPosts.clear();
      receivedPiPosts.clear();
      wearerWsOnRelay = null;

      mockPiServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockPiServer.listen((HttpRequest req) async {
        if (req.headers.value('authorization') != 'Bearer $testToken') {
          req.response.statusCode = 401;
          await req.response.close();
          return;
        }
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          final ws = await WebSocketTransformer.upgrade(req);
          ws.listen((data) {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (msg['type'] == 'ping') {
              ws.add(jsonEncode({'type': 'pong'}));
            }
          });
          return;
        }
        final bodyStr = await utf8.decoder.bind(req).join();
        final body = bodyStr.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(bodyStr) as Map<String, dynamic>;
        receivedPiPosts.putIfAbsent(req.uri.path, () => []).add(body);

        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/caregiver/snapshot') {
          req.response.write(
            jsonEncode({
              'ok': true,
              'type': 'assist_request',
              'request_id': 'snap-01',
              'image_base64': base64Encode([0xFF, 0xD8, 0xFF, 0xD9]),
            }),
          );
        } else {
          req.response.write(jsonEncode({'ok': true, 'revision': body['revision'] ?? 0}));
        }
        await req.response.close();
      });

      mockRelayServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockRelayServer.listen((HttpRequest req) async {
        if (req.headers.value('authorization') != 'Bearer $testToken') {
          req.response.statusCode = 401;
          await req.response.close();
          return;
        }
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          expect(req.uri.queryParameters['role'], 'wearer');
          wearerWsOnRelay = await WebSocketTransformer.upgrade(req);
          wearerWsOnRelay!.listen((data) {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (msg['type'] == 'ping') {
              wearerWsOnRelay!.add(jsonEncode({'type': 'pong'}));
            }
          });
          return;
        }
        final bodyStr = await utf8.decoder.bind(req).join();
        final body = bodyStr.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(bodyStr) as Map<String, dynamic>;
        receivedRelayPosts.putIfAbsent(req.uri.path, () => []).add(body);

        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'ok': true}));
        await req.response.close();
      });
    });

    tearDown(() async {
      await wearerWsOnRelay?.close();
      await mockPiServer.close(force: true);
      await mockRelayServer.close(force: true);
    });

    test('forwards Pi snapshot to Caregiver Relay and routes caregiver_reply back to Pi', () async {
      final state = AppState();
      state.prefs = await SharedPreferences.getInstance();
      state.loaded = true;
      state.demo = false;

      state.link
        ..endpoint = 'http://127.0.0.1:${mockPiServer.port}'
        ..token = testToken
        ..allowInsecure = true;
      state.caregiverLink
        ..endpoint = 'http://127.0.0.1:${mockRelayServer.port}'
        ..token = testToken
        ..allowInsecure = true;

      await state.link.connect();
      await state.caregiverLink.connect();
      expect(state.link.connected, isTrue);
      expect(state.caregiverLink.connected, isTrue);

      // 1. Wearer asks caregiver -> fetches JPEG from Pi -> posts to Relay
      await state.askCaregiverWithSnapshot('Biển xe buýt số mấy?');
      expect(receivedPiPosts['/caregiver/snapshot'], isNotNull);
      expect(receivedRelayPosts['/assist/request'], isNotNull);
      expect(
        receivedRelayPosts['/assist/request']!.first['image_base64'],
        base64Encode([0xFF, 0xD8, 0xFF, 0xD9]),
      );

      // 2. Caregiver replies over Relay WS -> Wearer forwards to Pi /caregiver/speak
      state.caregiverLink.onMessage = state.handleCaregiverMessage;
      wearerWsOnRelay!.add(
        jsonEncode({
          'type': 'caregiver_reply',
          'request_id': 'snap-01',
          'sender_name': 'Mẹ',
          'reply_text': 'Tuyến xe buýt số 08 ngay trước mặt.',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(receivedPiPosts['/caregiver/speak'], isNotNull);
      expect(
        receivedPiPosts['/caregiver/speak']!.first['reply_text'],
        'Tuyến xe buýt số 08 ngay trước mặt.',
      );

      // 3. Wearer triggers SOS -> attaches Pi snapshot -> posts to Relay /sos/trigger
      await state.triggerCaregiverSos('Cần hỗ trợ tại ngã tư!', silentTts: true);
      expect(receivedRelayPosts['/sos/trigger'], isNotNull);
      expect(
        receivedRelayPosts['/sos/trigger']!.first['image_base64'],
        isNotEmpty,
      );

      state.dispose();
    });
  });
}
