import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/ui/landing_page.dart';

void main() {
  testWidgets('LandingPage displays branding, telemetries, and loading status',
      (WidgetTester tester) async {
    final state = AppState();

    await tester.pumpWidget(
      MaterialApp(
        home: LandingPage(state: state),
      ),
    );

    // Initial loading state
    expect(find.text('SecondSight'), findsOneWidget);
    expect(find.text('Đang khởi động...'), findsOneWidget);
    expect(find.text('CORE v1.2.4'), findsOneWidget);
    expect(find.text('LOCAL OFFLINE'), findsOneWidget);

    // Advance timeline to allow status messages and animations to update
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SpineKinematicPainter), findsNothing); // painter used via CustomPaint
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('LandingPage triggers onEnter callback when ready',
      (WidgetTester tester) async {
    final state = AppState()..loaded = true;
    bool entered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LandingPage(
          state: state,
          onEnter: () => entered = true,
        ),
      ),
    );

    expect(find.text('Hệ thống đã sẵn sàng'), findsOneWidget);

    // Advance past timeline completion
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump(const Duration(milliseconds: 500));

    expect(entered, isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
