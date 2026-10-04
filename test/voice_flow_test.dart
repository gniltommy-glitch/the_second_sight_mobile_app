import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/services/routing.dart';

class VoiceState extends AppState {
  final spoken = <String>[];
  int plans = 0, starts = 0;
  bool failStart = false;
  Completer<void>? hold;

  VoiceState() {
    favorites.add(demoRoute().destination);
  }

  @override
  Future<void> say(String text, {bool urgent = false}) async {
    spoken.add(text);
    if (hold != null) await hold!.future;
  }

  @override
  Future<void> plan() async {
    plans++;
    route = demoRoute();
  }

  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw Exception('Kết nối kính trước khi bắt đầu.');
    journey = JourneyState.navigating;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'spoken favorite plans and starts without another user action',
    () async {
      final s = VoiceState();
      await s.voiceGo('điểm đến là ${s.favorites.first.name}');
      expect(s.plans, 1);
      expect(s.starts, 1);
      expect(s.active, isTrue);
    },
  );

  test(
    'duplicate commands while processing do not create two routes',
    () async {
      final s = VoiceState()..hold = Completer<void>();
      final query = 'điểm đến là ${s.favorites.first.name}';
      final first = s.voiceGo(query);
      await s.voiceGo(query);
      s.hold!.complete();
      await first;
      expect(s.plans, 1);
      expect(s.starts, 1);
    },
  );

  test(
    'failed start is spoken without claiming navigation has started',
    () async {
      final s = VoiceState()..failStart = true;
      await s.voiceGo('điểm đến là ${s.favorites.first.name}');
      expect(s.error, contains('Kết nối kính'));
      expect(
        s.spoken.any((text) => text.contains('Bắt đầu dẫn đường')),
        isFalse,
      );
      expect(s.spoken.last, contains('Kết nối kính'));
    },
  );

  test('assistant name alone asks for destination without routing', () async {
    final s = VoiceState();
    await s.voiceGo('Aurelia ơi');
    expect(s.plans, 0);
    expect(s.spoken.single, contains('địa chỉ'));
  });
}
