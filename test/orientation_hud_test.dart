import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/ui/widgets/orientation_hud.dart';

void main() {
  for (final width in [320.0, 430.0, 900.0]) {
    testWidgets('IMU status remains legible at width $width and large text', (
      tester,
    ) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1000),
              textScaler: TextScaler.linear(1.4),
              disableAnimations: true,
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: OrientationHud(ready: false, demo: false),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Không xác nhận hướng rẽ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Dừng hiệu ứng 3D'));
      await tester.pump();
      expect(find.byTooltip('Bật hiệu ứng 3D'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
