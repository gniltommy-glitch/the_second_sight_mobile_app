import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secondsight/services/pi_link.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/services/pairing_config.dart';
import 'package:secondsight/services/routing.dart';
import 'package:secondsight/services/voice_intent.dart';
import 'package:secondsight/ui/home.dart';

class RecordedState extends AppState {
  RecordedState({PiLink? link}) : super(piLink: link);
  final spoken = <String>[];
  @override
  Future<void> say(String text, {bool urgent = false}) async =>
      spoken.add(text);
  @override
  Future<void> stop() async {
    journey = JourneyState.ready;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('requested commands and wake phrase exclude unrelated conversation', () {
    expect(parseIntent('Nhắc lại').command, VoiceCommand.repeat);
    expect(parseIntent('Còn bao xa?').command, VoiceCommand.remaining);
    expect(wakeCommand('Hey Aurelia, nhắc lại'), 'nhắc lại');
    expect(wakeCommand('Aurelia ơi'), '');
    expect(wakeCommand('Hây Au rê lia'), '');
    expect(wakeCommand('hey aurelia còn bao xa'), 'còn bao xa');
    expect(wakeCommand('tôi nghe nói hey aurelia'), isNull);
    expect(wakeCommand('nhắc lại'), isNull);
  });

  test(
    'stop works off route and a new destination cannot silently stop a trip',
    () async {
      final state = RecordedState()..journey = JourneyState.offRoute;
      await state.voiceGo('đến chợ Bến Thành');
      expect(state.offRoute, isTrue);
      expect(state.spoken.last, contains('dừng dẫn đường trước'));
      await state.voiceGo('dừng dẫn đường');
      expect(state.journey, JourneyState.ready);
      expect(state.spoken.last, contains('Đã kết thúc'));
      state.dispose();
    },
  );

  test('no explicit confirmation never starts the journey', () async {
    final state = RecordedState()..demo = true;
    state.route = demoRoute();
    state.listenReply = () async => null;
    await state.voiceGo('đến chợ');
    expect(state.active, isFalse);
    expect(state.spoken.where((s) => s.contains('đúng không')), isNotEmpty);
    expect(state.pendingConfirm, isNull);
    state.dispose();
  });

  test(
    'confirmation rejects negatives and gives address for duplicate names',
    () {
      expect(parseYesNo('không đúng'), YesNo.no);
      expect(parseYesNo('hủy'), YesNo.cancel);
      expect(parseYesNo('đúng rồi'), YesNo.yes);
      expect(
        confirmQuestion('Nhà thuốc', address: 'Quận 1', sameName: 2),
        contains('Có 2 nơi tên Nhà thuốc. Bạn muốn đến Nhà thuốc tại Quận 1'),
      );
    },
  );

  test('preflight lists absent and faulty support instead of accepting connection alone', () async {
    final state = RecordedState();
    state.speechReady = true;
    await expectLater(
      state.preflight(),
      throwsA(predicate((e) => e.toString().contains('Dữ liệu kính'))),
    );
    state.statusAt = DateTime.now();
    state.status = {'camera_ok': false, 'lidar_ok': false};
    await expectLater(
      state.preflight(),
      throwsA(
        predicate(
          (e) =>
              e.toString().contains('Camera') && e.toString().contains('LiDAR'),
        ),
      ),
    );
    state.dispose();
  });

  test(
    'preflight needs audio acknowledgement and rechecks telemetry afterward',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.path);
        return http.Response('{}', 200);
      });
      final state = RecordedState(link: PiLink(client: client));
      state.route = demoRoute();
      state.location = state.route!.points.first;
      state.fixAt = DateTime.now();
      state.accuracy = 3;
      state.statusAt = DateTime.now();
      state.status = {'camera_ok': true, 'lidar_ok': true};
      state.speechReady = true;
      state.link.connected = true;
      state.link.endpoint = 'http://glasses.local:8765';
      state.link.allowInsecure = true;
      state.listenReply = () async => 'có';
      await state.preflight();
      expect(requests, ['/audio/test']);
      expect(state.spoken.join(' '), contains('điện thoại và từ kính'));
      state.listenReply = () async {
        state.statusAt = DateTime.now().subtract(const Duration(seconds: 7));
        return 'có';
      };
      await expectLater(
        state.preflight(),
        throwsA(predicate((e) => e.toString().contains('vừa gián đoạn'))),
      );
      state.dispose();
    },
  );

  test(
    'health transitions are spoken once and stale telemetry is not trusted',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = RecordedState();
      state.prefs = await SharedPreferences.getInstance();
      state.loaded = true;
      state.journey = JourneyState.navigating;
      state.link.connected = true;
      state.fixAt = DateTime.now();
      state.accuracy = 3;
      state.statusAt = DateTime.now();
      state.status = {'camera_ok': false, 'lidar_ok': true};
      state.debugTick();
      await Future<void>.delayed(Duration.zero);
      expect(state.spoken.join(' '), contains('Camera chưa hoạt động'));
      final count = state.spoken.length;
      state.debugTick();
      expect(state.spoken.length, count);
      state.statusAt = DateTime.now().subtract(const Duration(seconds: 7));
      state.debugTick();
      await Future<void>.delayed(Duration.zero);
      expect(state.spoken.last, contains('Dữ liệu kính quá cũ'));
      state.dispose();
    },
  );

  test(
    'pairing never accepts credential URLs or unmarked insecure endpoints',
    () {
      String config(String endpoint, {bool insecure = false}) => jsonEncode({
        'type': 'secondsight_pairing',
        'version': 1,
        'endpoint': endpoint,
        'token': 'local-test-token',
        'routing_key': 'test-key',
        'allow_insecure': insecure,
      });
      expect(
        PairingConfig.parse(config('https://glasses.local:8765')).routingKey,
        'test-key',
      );
      expect(
        PairingConfig.parse(config('http://glasses.local:8765', insecure: true))
            .allowInsecure,
        isTrue,
      );
      for (final raw in [
        config('http://glasses.local'),
        config('https://user:secret@glasses.local'),
        config('https://glasses.local?token=secret'),
        '{}',
        'bad',
      ]) {
        expect(() => PairingConfig.parse(raw), throwsFormatException);
      }
    },
  );

  testWidgets(
    'wake waiting ignores ordinary speech and Hey Aurelia opens a command mic',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => true,
      );
      final state = RecordedState()..journey = JourneyState.navigating;
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(home: Home(state: state)));
      await state.setWakeEnabled(true);
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.binding.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('notifyStatus', 'listening'),
        ),
        (_) {},
      );
      await tester.pump();
      expect(find.text('Mic đang chờ “Hey Aurelia”'), findsOneWidget);
      Future<void> transcript(String words) async {
        final packet = const StandardMethodCodec().encodeMethodCall(
          MethodCall(
            'textRecognition',
            jsonEncode({
              'alternates': [
                {'recognizedWords': words, 'confidence': 1.0},
              ],
              'resultType': 2,
            }),
          ),
        );
        tester.binding.channelBuffers.push(channel.name, packet, (_) {});
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await transcript('dừng dẫn đường');
      expect(state.active, isTrue);
      expect(state.spoken, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await transcript('Hey Aurelia');
      expect(state.commandMicOpen, isTrue);
      expect(state.spoken.last, contains('Mời bạn nói lệnh'));
      await state.setWakeEnabled(false);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      await tester.pump(const Duration(milliseconds: 10));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );

  for (final journey in [JourneyState.navigating, JourneyState.offRoute]) {
    testWidgets(
      'command mic and hardware work during $journey; GPS notifications do not close mic',
      (tester) async {
        final calls = <String>[];
        const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            return true;
          },
        );
        final state = RecordedState()..journey = journey;
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(home: Home(state: state)));
        await tester.tap(find.byKey(const Key('command_mic')));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(calls, contains('listen'));
        expect(
          state.commandMicOpen,
          isTrue,
          reason: "calls=$calls, spoken=${state.spoken}, error=${state.error}",
        );
        final canceled = calls.where((c) => c == 'cancel').length;
        state.notifyListeners();
        await tester.pump();
        expect(calls.where((c) => c == 'cancel').length, canceled);
        await tester.tap(find.byKey(const Key('command_mic')));
        await tester.pump();
        expect(state.commandMicOpen, isFalse);
        state.handlePiMessage({'type': 'voice_button'});
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(state.commandMicOpen, isTrue);
        // A hazard must immediately close recognition to avoid catching Pi speech.
        state.handlePiMessage({
          'type': 'hazard',
          'hazard_id': 'test',
          'hold_ms': 1000,
        });
        await tester.pump();
        expect(state.commandMicOpen, isFalse);
        expect(calls.last, 'cancel');
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        await tester.pump(const Duration(milliseconds: 10));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      },
    );
  }
}
