import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/ui/home.dart';

class BackgroundState extends AppState {
  final spoken = <String>[];
  @override
  Future<void> say(String text, {bool urgent = false}) async {
    spoken.add(text);
  }

  @override
  Future<void> cancelSpeech() async {}
  @override
  Future<void> stop() async {
    journey = JourneyState.ready;
    notifyListeners();
  }
}

void _lifecycle(WidgetTester tester, bool background) {
  final states = background
      ? [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]
      : [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ];
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  test('navigation wake defaults on only for navigating and offRoute', () {
    final state = AppState();
    for (final journey in JourneyState.values) {
      state.journey = journey;
      expect(
        state.navigationVoiceActive,
        journey == JourneyState.navigating || journey == JourneyState.offRoute,
      );
    }
    state.dispose();
  });

  test(
    'background commands cannot choose destinations or run outside navigation',
    () async {
      final state = BackgroundState()..journey = JourneyState.navigating;
      await state.backgroundVoiceCommand('đến chợ Bến Thành');
      expect(state.active, isTrue);
      expect(state.destination, isNull);
      expect(state.spoken.last, contains('chưa hiểu lệnh'));
      state.spoken.clear();
      state.journey = JourneyState.paused;
      await state.backgroundVoiceCommand('dừng dẫn đường');
      expect(state.journey, JourneyState.paused);
      expect(state.spoken, isEmpty);
      state.dispose();
    },
  );

  for (final journey in [JourneyState.navigating, JourneyState.offRoute]) {
    testWidgets(
      'native mic is armed before background in $journey and stops with voice stop',
      (tester) async {
        const native = MethodChannel('secondsight/voice');
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (
          call,
        ) async {
          calls.add(call);
          return true;
        });
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugin.csdcorp.com/speech_to_text'),
          (_) async => true,
        );
        final state = BackgroundState()..journey = journey;
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(home: Home(state: state)));
        await tester.pump();
        expect(
          calls
              .where((c) => c.method == 'configureNavigation')
              .last
              .arguments['enabled'],
          isTrue,
        );

        _lifecycle(tester, true);
        await tester.pump();
        Future<void> event(String method, dynamic argument) async {
          tester.binding.channelBuffers.push(
            native.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, argument),
            ),
            (_) {},
          );
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
        }

        await event('backgroundWake', 9);
        expect(state.spoken.last, contains('Mời bạn nói'));
        expect(
          calls
              .where((c) => c.method == 'commandReady')
              .last
              .arguments['ticket'],
          9,
        );
        await event('backgroundListening', true);
        expect(state.commandMicOpen, isTrue);
        await event('backgroundCommand', 'dừng dẫn đường');
        expect(state.journey, JourneyState.ready);
        expect(
          calls
              .where((c) => c.method == 'configureNavigation')
              .last
              .arguments['enabled'],
          isFalse,
        );
        expect(calls.any((c) => c.method == 'commandFinished'), isTrue);
        await tester.pumpWidget(const SizedBox());
        state.dispose();

        _lifecycle(tester, false);
        await tester.pump(const Duration(milliseconds: 10));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          native,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugin.csdcorp.com/speech_to_text'),
          null,
        );
      },
    );
  }

  testWidgets(
    'hazard suppresses background commands and notification mute stops mic only',
    (tester) async {
      const native = MethodChannel('secondsight/voice');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      final state = BackgroundState()..journey = JourneyState.navigating;
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(home: Home(state: state)));

      _lifecycle(tester, true);
      await tester.pump();
      state.handlePiMessage({
        'type': 'hazard',
        'hazard_id': 'h1',
        'hold_ms': 3000,
      });
      await tester.pump();
      expect(
        calls
            .where((c) => c.method == 'configureNavigation')
            .last
            .arguments['interrupt'],
        isTrue,
      );
      await state.backgroundVoiceCommand('dừng dẫn đường');
      expect(state.active, isTrue);
      expect(state.spoken, isEmpty);
      tester.binding.channelBuffers.push(
        native.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('backgroundMuted'),
        ),
        (_) {},
      );
      await tester.pump();
      await tester.pump();
      expect(state.active, isTrue);
      expect(state.navigationVoiceActive, isFalse);
      expect(
        calls
            .where((c) => c.method == 'configureNavigation')
            .last
            .arguments['enabled'],
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      state.dispose();

      _lifecycle(tester, false);
      await tester.pump(const Duration(milliseconds: 10));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        native,
        null,
      );
    },
  );
}
