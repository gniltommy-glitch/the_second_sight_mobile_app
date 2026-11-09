import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/services/speech_output.dart';

void main() {
  test(
    'directions wait for current sentence instead of cutting it off',
    () async {
      final first = Completer<int>();
      final spoken = <String>[];
      var stops = 0;
      final output = SpeechOutput(
        speak: (text) async {
          spoken.add(text);
          return text == 'first' ? first.future : 1;
        },
        stop: () async {
          stops++;
          return 1;
        },
        onError: (e) => fail('$e'),
      );
      final a = output.say('first');
      final b = output.say('turn right');
      await Future<void>.delayed(Duration.zero);
      expect(spoken, ['first']);
      first.complete(1);
      await Future.wait([a, b]);
      expect(spoken, ['first', 'turn right']);
      expect(stops, 0);
    },
  );

  test('urgent warning cancels pending directions', () async {
    final first = Completer<int>();
    final spoken = <String>[];
    final output = SpeechOutput(
      speak: (text) async {
        spoken.add(text);
        return text == 'first' ? first.future : 1;
      },
      stop: () async {
        first.complete(0);
        return 1;
      },
      onError: (e) => fail('$e'),
    );
    final a = output.say('first');
    final b = output.say('stale direction');
    await Future<void>.delayed(Duration.zero);
    await output.say('obstacle', urgent: true);
    await Future.wait([a, b]);
    expect(spoken, ['first', 'obstacle']);
  });

  test('native engine timeout releases caller and reports failure', () async {
    final errors = <Object>[];
    final output = SpeechOutput(
      speak: (_) => Completer<int>().future,
      stop: () async => 1,
      timeout: const Duration(milliseconds: 10),
      onError: errors.add,
    );
    await output.say('greeting');
    expect(errors.single, isA<TimeoutException>());
  });

  test('native rejection is not silently treated as spoken', () async {
    final errors = <Object>[];
    final output = SpeechOutput(
      speak: (_) async => 0,
      stop: () async => 1,
      onError: errors.add,
    );
    await output.say('greeting');
    expect(errors, hasLength(1));
  });
  test('touch speech replaces stale labels and yields to directions', () async {
    final spoken = <String>[];
    Completer<int>? playing;
    final output = SpeechOutput(
      speak: (text) {
        spoken.add(text);
        playing = Completer<int>();
        return playing!.future;
      },
      stop: () async {
        if (playing != null && !playing!.isCompleted) playing!.complete(0);
        return 1;
      },
      onError: (e) => fail('$e'),
    );
    final first = output.explore('Nút tìm kiếm');
    await Future<void>.delayed(Duration.zero);
    final second = output.explore('Vị trí của tôi');
    await Future<void>.delayed(Duration.zero);
    expect(spoken, ['Nút tìm kiếm', 'Vị trí của tôi']);
    final direction = output.say('Rẽ phải');
    await Future<void>.delayed(Duration.zero);
    await output.explore('Không được chen vào');
    expect(spoken, ['Nút tìm kiếm', 'Vị trí của tôi', 'Rẽ phải']);
    playing!.complete(1);
    await Future.wait([first, second, direction]);
    output.dispose();
  });

  test(
    'rapid touch changes keep only the latest label while stop awaits',
    () async {
      final stopped = Completer<int>();
      final firstDone = Completer<int>();
      final spoken = <String>[];
      final output = SpeechOutput(
        speak: (text) async {
          spoken.add(text);
          return text == 'first' ? firstDone.future : 1;
        },
        stop: () => stopped.future,
        onError: (e) => fail('$e'),
      );
      final first = output.explore('first');
      await Future<void>.delayed(Duration.zero);
      final stale = output.explore('stale');
      final latest = output.explore('latest');
      firstDone.complete(0);
      stopped.complete(1);
      await Future.wait([first, stale, latest]);
      expect(spoken, ['first', 'latest']);
      output.dispose();
    },
  );
  test(
    'screen reader takeover stops only exploration, never navigation speech',
    () async {
      var stops = 0;
      Completer<int>? playing;
      final output = SpeechOutput(
        speak: (_) {
          playing = Completer<int>();
          return playing!.future;
        },
        stop: () async {
          stops++;
          if (playing != null && !playing!.isCompleted) playing!.complete(0);
          return 1;
        },
        onError: (e) => fail('$e'),
      );
      final exploration = output.explore('Nhãn nút');
      await Future<void>.delayed(Duration.zero);
      await output.cancelExploration();
      await exploration;
      expect(stops, 1);
      final direction = output.say('Đi thẳng');
      await Future<void>.delayed(Duration.zero);
      await output.cancelExploration();
      expect(stops, 1);
      playing!.complete(1);
      await direction;
      output.dispose();
    },
  );
}
