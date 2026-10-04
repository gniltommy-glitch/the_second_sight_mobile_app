import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/ui/home.dart';

class StartupState extends AppState {
  final List<String> calls;
  StartupState(this.calls);
  @override
  Future<void> say(String text, {bool urgent = false}) async {
    calls.add(text);
  }
}

void main() {
  testWidgets(
    'greeting precedes recognition setup; mic opens without taps and closes on navigation',
    (tester) async {
      final calls = <String>[];
      const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return true;
      });
      final state = StartupState(calls);
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(home: Home(state: state)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(calls.first, contains('Xin chào, mình là Aurelia'));
      expect(calls.indexOf('initialize'), greaterThan(0));
      expect(calls, contains('listen'));
      state.journey = JourneyState.navigating;
      state.notifyListeners();
      await tester.pump();
      expect(calls.last, 'cancel');
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
}
