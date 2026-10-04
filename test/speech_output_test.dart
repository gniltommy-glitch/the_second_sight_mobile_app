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
}
