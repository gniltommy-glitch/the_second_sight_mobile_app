import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/services/routing.dart';
import 'package:secondsight/ui/home.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SessionState extends AppState {
  final spoken = <String>[];
  final commands = <String>[];
  @override
  Future<void> say(String text, {bool urgent = false}) async =>
      spoken.add(text);
  @override
  Future<void> cancelSpeech() async {}
  @override
  Future<void> voiceGo(String text) async => commands.add(text);
}

void main() {
  const speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  const hardware = MethodChannel('secondsight/voice');

  Future<void> send(WidgetTester tester, String method, dynamic value) async {
    tester.binding.channelBuffers.push(
      speechChannel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> words(WidgetTester tester, String text, int type) => send(
    tester,
    'textRecognition',
    jsonEncode({
      'alternates': [
        {'recognizedWords': text, 'confidence': 1.0},
      ],
      'resultType': type,
    }),
  );

  Future<SessionState> mount(
    WidgetTester tester,
    List<String> calls, {
    bool navigating = false,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      speechChannel,
      (call) async {
        calls.add(call.method);
        return true;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hardware,
      (_) async => null,
    );
    final state = SessionState();
    if (navigating) state.journey = JourneyState.navigating;
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Home(state: state, recognizer: SpeechToText.withMethodChannel()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return state;
  }

  Future<void> cleanup(WidgetTester tester, SessionState state) async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    await tester.pump(const Duration(milliseconds: 10));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    debugDefaultTargetPlatformOverride = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      speechChannel,
      null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hardware,
      null,
    );
  }

  testWidgets(
    'partial destination survives mic end, fills field and dispatches once',
    (tester) async {
      final calls = <String>[];
      final state = await mount(tester, calls);
      expect(state.spoken.length, 1);
      await words(tester, 'đến chợ Bến Thành', 0);
      expect(state.commands, isEmpty);
      await send(tester, 'notifyStatus', 'notListening');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(state.commands, ['đến chợ Bến Thành']);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .any((field) => field.controller?.text == 'chợ Bến Thành'),
        isTrue,
      );
      await words(tester, 'đến chợ Bến Thành', 2);
      expect(state.commands.length, 1);
      await tester.pump(const Duration(seconds: 35));
      expect(calls.where((c) => c == 'listen').length, 1);
      expect(state.spoken.length, 1);
      await cleanup(tester, state);
    },
  );

  testWidgets(
    'silence and app resume never repeat the destination invitation',
    (tester) async {
      final calls = <String>[];
      final state = await mount(tester, calls);
      await send(tester, 'notifyStatus', 'done');
      await tester.pump(const Duration(seconds: 30));
      expect(state.spoken.length, 1);
      expect(calls.where((c) => c == 'listen').length, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 30));
      expect(state.spoken.length, 1);
      expect(calls.where((c) => c == 'listen').length, 1);
      await cleanup(tester, state);
    },
  );

  testWidgets(
    'partial wake opens one command session; timeout monitors silently',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <String>[];
      final state = await mount(tester, calls, navigating: true);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Mic đang chờ “Hey Aurelia”'), findsNothing);
      await send(tester, 'notifyStatus', 'listening');
      expect(
        find.text('Mic đang chờ “Hey Aurelia”'),
        findsOneWidget,
        reason:
            'calls=$calls, error=${state.error}, mic=${state.commandMicOpen}',
      );
      await words(tester, 'Hây Au rê lia', 0);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        state.commandMicOpen,
        isTrue,
        reason: 'calls=$calls, spoken=${state.spoken}, error=${state.error}',
      );
      expect(state.spoken.length, 1);
      expect(state.spoken.single, contains('Mời bạn nói lệnh'));
      await send(
        tester,
        'notifyError',
        jsonEncode({'errorMsg': 'error_speech_timeout', 'permanent': false}),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(state.commandMicOpen, isFalse);
      expect(state.spoken.length, 1);
      expect(state.commands, isEmpty);
      await cleanup(tester, state);
    },
  );

  testWidgets('GPS updates do not discard a partial navigation command', (
    tester,
  ) async {
    final calls = <String>[];
    final state = await mount(tester, calls, navigating: true);
    await tester.tap(find.byKey(const Key('command_mic')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await words(tester, 'nhắc lại', 0);
    await send(tester, 'notifyStatus', 'notListening');
    state.notifyListeners();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(
      state.commands,
      ['nhắc lại'],
      reason:
          'calls=$calls, spoken=${state.spoken}, error=${state.error}, mic=${state.commandMicOpen}',
    );
    expect(state.spoken.length, 1);
    await cleanup(tester, state);
  });

  testWidgets(
    'Android waiting opens no recurring recognizer or banner, native wake opens once',
    (tester) async {
      final calls = <String>[];
      final state = await mount(tester, calls, navigating: true);
      await tester.pump(const Duration(seconds: 60));
      expect(calls.where((c) => c == 'listen'), isEmpty);
      expect(find.text('Mic đang chờ “Hey Aurelia”'), findsNothing);
      expect(state.spoken, isEmpty);
      tester.binding.channelBuffers.push(
        hardware.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('backgroundWake', 1),
        ),
        (_) {},
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(calls.where((c) => c == 'listen').length, 1);
      expect(state.commandMicOpen, isTrue);
      expect(state.spoken.length, 1);
      await send(
        tester,
        'notifyError',
        jsonEncode({'errorMsg': 'error_speech_timeout', 'permanent': false}),
      );
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(calls.where((c) => c == 'listen').length, 1);
      expect(state.spoken.length, 1);
      await cleanup(tester, state);
    },
  );

  test(
    'unclear confirmation is asked once and cannot start navigation',
    () async {
      final state = SessionState()..demo = true;
      state.route = demoRoute();
      var attempts = 0;
      state.listenReply = () async {
        attempts++;
        return null;
      };
      // Use AppState's real flow here, rather than SessionState's recorder.
      final real = _ConfirmationState()..demo = true;
      real.route = demoRoute();
      real.listenReply = state.listenReply;
      await real.voiceGo('đến chợ');
      expect(attempts, 1);
      expect(real.spoken.where((s) => s.contains('đúng không')).length, 1);
      expect(real.active, isFalse);
      real.dispose();
      state.dispose();
    },
  );
}

class _ConfirmationState extends AppState {
  final spoken = <String>[];
  @override
  Future<void> say(String text, {bool urgent = false}) async =>
      spoken.add(text);
}
