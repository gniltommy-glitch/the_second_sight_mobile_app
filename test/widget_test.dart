import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/main.dart';

void main() {
  testWidgets('app loads into loading state', (WidgetTester tester) async {
    await tester.pumpWidget(const SecondSightApp());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
