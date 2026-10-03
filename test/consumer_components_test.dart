import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/ui/widgets/consumer_components.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'welcome supports narrow screens, large text and touch at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    JourneyWelcome(
                      connected: false,
                      navigating: false,
                      demo: false,
                      onDevice: () => opened = true,
                    ),
                    const SizedBox(height: 900),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Kết nối'));
        await tester.pumpAndSettle();
        expect(opened, isTrue);
        await tester.drag(find.byType(JourneyWelcome), const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getTopLeft(find.byType(JourneyWelcome)).dy, lessThan(20));
      },
    );
  }
}
