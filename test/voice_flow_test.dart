import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/services/routing.dart';
import 'package:secondsight/services/pi_link.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

class VoiceState extends AppState {
  final spoken = <String>[];
  int plans = 0, starts = 0;
  bool failStart = false;
  Completer<void>? hold;

  VoiceState()
    : super(
        piLink: PiLink(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ) {
    link.connected = true;
    favorites.add(demoRoute().destination);
    listenReply = () async => 'có';
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

  test(
    'voice can preview walking route without glasses instead of failing start',
    () async {
      final state = VoiceState();
      state.link.connected = false;
      await state.voiceGo('điểm đến là ${state.favorites.first.name}');
      expect(state.plans, 1);
      expect(state.starts, 0);
      expect(state.route, isNotNull);
      expect(state.error, isNull);
      expect(state.spoken.last, contains('Đã lấy tuyến đi bộ'));
      state.dispose();
    },
  );

  test('assistant name alone asks for destination without routing', () async {
    final s = VoiceState();
    await s.voiceGo('Aurelia ơi');
    expect(s.plans, 0);
    expect(s.spoken.single, contains('địa chỉ'));
  });
}
