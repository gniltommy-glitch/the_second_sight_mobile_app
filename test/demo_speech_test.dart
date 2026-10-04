import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/services/routing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');

  test('demo timer sends spoken directions to phone without glasses', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final utterances = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'speak') {
            utterances.add(
              call.arguments is String
                  ? call.arguments as String
                  : (call.arguments as Map)['text'] as String,
            );
          }
          return 1;
        });
    final state = AppState();
    addTearDown(state.dispose);
    await state.init();
    expect(state.loaded, isTrue);
    state.demo = true;
    state.route = demoRoute();
    state.destination = state.route!.destination;
    state.location = state.route!.points.first;
    state.accuracy = 3;
    state.fixAt = DateTime.now();
    state.journey = JourneyState.navigating;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(
      utterances,
      isNotEmpty,
      reason:
          'journey=${state.journey}, progress=${state.progress}, fresh=${state.freshFix}, sync=${state.syncPending}, error=${state.error}, events=${state.events}',
    );
    expect(utterances.join(' '), contains(state.instruction!.text));
    expect(state.link.connected, isFalse);
  });

  test(
    'saved demo mode restores simulated GPS without a route cache',
    () async {
      SharedPreferences.setMockInitialValues({'demo_mode': true});
      FlutterSecureStorage.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 1);
      final state = AppState();
      addTearDown(state.dispose);
      await state.init();
      expect(state.demo, isTrue);
      expect(state.route!.demo, isTrue);
      expect(state.freshFix, isTrue);
      expect(state.connected, isTrue);
      expect(state.journey, JourneyState.ready);
    },
  );

  test('uses available Vietnamese locale when engine rejects vi-VN', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'setLanguage')
            return call.arguments == 'vi' ? 1 : 0;
          if (call.method == 'getVoices') {
            return [
              {'name': 'Vietnamese', 'locale': 'vi'},
            ];
          }
          return 1;
        });
    final state = AppState();
    addTearDown(state.dispose);
    await state.configureSpeech();
    expect(state.speechReady, isTrue);
    expect(calls.any((call) => call.method == 'setVoice'), isTrue);
    await state.say('Xin chào');
    expect(calls.any((call) => call.method == 'speak'), isTrue);
  });

  test('missing Vietnamese voice surfaces an actionable error', () async {
    final binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'speak')
        fail('Must not speak after configuration failed');
      if (call.method == 'getVoices') return <dynamic>[];
      return call.method == 'setLanguage' ? 0 : 1;
    });
    final state = AppState();
    await state.configureSpeech();
    expect(state.error, contains('tải giọng tiếng Việt'));
    expect(state.events.first['type'], 'tts_error');
    expect(state.speechReady, isFalse);
    final events = state.events.length;
    await state.say('Xin chào');
    await state.say('Rẽ phải');
    expect(state.events.length, events);
    state.dispose();
  });
}
