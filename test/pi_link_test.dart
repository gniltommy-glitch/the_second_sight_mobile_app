import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/services/pi_link.dart';

void main() {
  test(
    'authenticated native fallback handles handshake, messages and disconnect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final authorization = Completer<String?>();
      final frame = Completer<Map<String, dynamic>>();
      WebSocket? peer;
      final listener = server.listen((request) async {
        authorization.complete(request.headers.value('authorization'));
        peer = await WebSocketTransformer.upgrade(request);
        peer!.listen((raw) {
          final j = jsonDecode(raw as String) as Map<String, dynamic>;
          if (j['type'] == 'probe' && !frame.isCompleted) frame.complete(j);
          if (j['type'] == 'ping') peer!.add('{"type":"pong"}');
        });
        peer!.add('{"type":"device_status","stm32_ok":false}');
      });
      final link = PiLink()
        ..endpoint = 'http://127.0.0.1:${server.port}'
        ..allowInsecure = true
        ..token = 'test-local-only-token';
      addTearDown(() async {
        link.dispose();
        await peer?.close();
        await listener.cancel();
        await server.close(force: true);
      });
      final status = Completer<Map<String, dynamic>>();
      link.onMessage = (j) {
        if (!status.isCompleted) status.complete(j);
      };
      await link.connect();
      expect(link.connected, isTrue);
      expect(await authorization.future, 'Bearer test-local-only-token');
      expect(
        (await status.future.timeout(const Duration(seconds: 3)))['stm32_ok'],
        isFalse,
      );
      link.send({'type': 'probe', 'target_bearing': 90});
      expect(
        (await frame.future.timeout(
          const Duration(seconds: 3),
        ))['target_bearing'],
        90,
      );
      link.disconnect();
      expect(link.connected, isFalse);
    },
  );

  test('insecure transport is rejected before connecting unless explicitly enabled', () async {
    final link = PiLink()..token = 'test-local-only-token';
    addTearDown(link.dispose);
    await expectLater(link.connect(), throwsException);
  });
}
