import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/services/android_accessibility.dart';
import 'package:secondsight/ui/widgets/accessibility_support_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidAccessibility.channel, null);
  });

  testWidgets(
    'native state refreshes on resume and opens accessibility settings',
    (tester) async {
      var active = false;
      var opened = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidAccessibility.channel,
        (call) async {
          if (call.method == 'openSettings') {
            opened = true;
            return true;
          }
          return {'talkBackEnabled': active, 'touchExplorationEnabled': active};
        },
      );
      final service = AndroidAccessibility()..start();
      await tester.pump();
      expect(service.systemReaderActive, isFalse);
      expect(service.touchExplorationEnabled, isFalse);
      active = true;
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(service.talkBackEnabled, isTrue);
      expect(service.systemReaderActive, isTrue);
      expect(await service.openSettings(), isTrue);
      expect(opened, isTrue);
      service.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('live Android events update support card and fallback state', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidAccessibility.channel,
      (_) async => {'talkBackEnabled': false, 'touchExplorationEnabled': false},
    );
    final service = AndroidAccessibility()..start();
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidAccessibilityScope(
          service: service,
          child: const Scaffold(
            body: SingleChildScrollView(child: AccessibilitySupportCard()),
          ),
        ),
      ),
    );
    expect(find.text('Đang dùng giọng đọc của Aurelia'), findsOneWidget);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      AndroidAccessibility.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('stateChanged', {
          'talkBackEnabled': true,
          'touchExplorationEnabled': true,
        }),
      ),
      (_) {},
    );
    await tester.pump();
    expect(service.systemReaderActive, isTrue);
    expect(find.text('TalkBack đang bật'), findsOneWidget);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      AndroidAccessibility.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('stateChanged', {
          'talkBackEnabled': false,
          'touchExplorationEnabled': true,
        }),
      ),
      (_) {},
    );
    await tester.pump();
    expect(service.systemReaderActive, isTrue);
    expect(find.text('Trình đọc màn hình hệ thống đang bật'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'unavailable bridge remains unknown and settings failure is reported',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidAccessibility.channel,
        (_) async => throw MissingPluginException(),
      );
      final service = AndroidAccessibility()..start();
      await tester.pump();
      expect(service.touchExplorationEnabled, isNull);
      expect(await service.openSettings(), isFalse);
      service.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
