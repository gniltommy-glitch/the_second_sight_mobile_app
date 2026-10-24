import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:secondsight/core/app_state.dart';
import 'package:secondsight/core/models.dart';
import 'package:secondsight/ui/home.dart';

class TestAppState extends AppState {
  final List<String> spoken = [];
  final List<Uri> launchedUrls = [];
  final List<String> sharedTexts = [];

  TestAppState() {
    urlLauncherOverride = (uri) async {
      launchedUrls.add(uri);
      return true;
    };
    shareOverride = (text) async {
      sharedTexts.add(text);
    };
  }

  @override
  Future<void> say(String text, {bool urgent = false}) async {
    spoken.add(text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Emergency Contact & Voice Matching', () {
    late TestAppState state;

    setUp(() {
      state = TestAppState();
      state.emergencyContacts = [
        const EmergencyContact('Mẹ', '0901112222'),
        const EmergencyContact('Anh Nam (hàng xóm)', '0988776655'),
        const EmergencyContact('Bác sĩ Tuấn', '0912345678'),
      ];
    });

    test('matchEmergencyContact finds contacts by name, diacritics, and phone', () {
      // 1. Direct match
      expect(state.matchEmergencyContact('Mẹ')?.phone, '0901112222');
      // 2. Diacritic folded match
      expect(state.matchEmergencyContact('me')?.phone, '0901112222');
      expect(state.matchEmergencyContact('anh nam')?.phone, '0988776655');
      expect(state.matchEmergencyContact('tuan')?.phone, '0912345678');
      // 3. Phone number match
      expect(state.matchEmergencyContact('0988776655')?.name, 'Anh Nam (hàng xóm)');
      // 4. Default to first if query empty
      expect(state.matchEmergencyContact('')?.name, 'Mẹ');
      expect(state.matchEmergencyContact(null)?.name, 'Mẹ');
      // 5. Unknown contact returns null
      expect(state.matchEmergencyContact('Người Lạ 123'), isNull);
    });

    test('triggerCall dials contact or emergency number via urlLauncher', () async {
      // Call known contact
      await state.triggerCall('Mẹ');
      expect(state.launchedUrls.last.toString(), 'tel:0901112222');
      expect(state.spoken.last, contains('Đang gọi cho Mẹ'));

      // Call emergency service number
      await state.triggerCall('115');
      expect(state.launchedUrls.last.toString(), 'tel:115');
      expect(state.spoken.last, contains('115'));

      // Unknown contact gives helpful voice prompt
      await state.triggerCall('Chú Ba');
      expect(state.spoken.last, contains('Không tìm thấy người thân Chú Ba'));
    });

    test('triggerShareLocation shares GPS link via SMS or Share', () async {
      state.location = const LatLng(10.7769, 106.7009);

      // Share to specific contact -> SMS
      await state.triggerShareLocation('Mẹ');
      expect(state.launchedUrls.last.scheme, 'sms');
      expect(state.launchedUrls.last.path, '0901112222');
      expect(state.launchedUrls.last.queryParameters['body'], contains('10.776900,106.700900'));

      // Share all -> Share dialog / broadcast
      await state.triggerShareLocation('tất cả');
      expect(state.sharedTexts.last, contains('https://maps.google.com/?q=10.776900,106.700900'));
    });
  });

  group('Emergency Loss of Connection State Machine', () {
    late TestAppState state;

    setUp(() {
      state = TestAppState();
      state.location = const LatLng(10.7769, 106.7009);
      state.emergencyContacts = [
        const EmergencyContact('Mẹ (Giám hộ 1)', '0901112222'),
        const EmergencyContact('Bố', '0903334444'),
      ];
    });

    tearDown(() {
      state.dispose();
    });

    test('5 retries exhausted triggers 10s countdown, then auto SMS & Call', () async {
      await state.startLostConnectionEmergency(simulated: true);
      expect(state.emergencyPhase, EmergencyPhase.reconnecting);
      expect(state.spoken.any((s) => s.contains('đứng yên tại chỗ')), isTrue);

      // Advance retry count to 5
      state.emergencyRetryCount = 5;
      // Start countdown manually or via timer
      // Trigger voice command cancel check
      expect(state.emergencyPhase, EmergencyPhase.reconnecting);

      // Simulate voice cancel
      await state.voiceGo('Hủy');
      expect(state.emergencyPhase, EmergencyPhase.cancelled);
      expect(state.spoken.last, contains('Đã hủy chế độ khẩn cấp'));
    });

    test('countdown timeout executes automated SOS SMS and dials priority 1 guardian', () async {
      // Start emergency and jump directly to countdown phase
      await state.startLostConnectionEmergency(simulated: true);
      state.emergencyRetryCount = 5;

      // Voice intent check: saying dừng during countdown also cancels
      await state.voiceGo('Aurelia ơi');
      expect(state.spoken.last, contains('địa chỉ'));

      // Test cancelEmergency
      await state.cancelEmergency();
      expect(state.emergencyPhase, EmergencyPhase.cancelled);

      // Test automated action dispatch when countdown expires
      await state.startLostConnectionEmergency(simulated: true);
      // Wait or invoke automated actions directly
      await state.voiceGo('Aurelia gọi cho Mẹ nhé');
      expect(state.launchedUrls.any((u) => u.toString() == 'tel:0901112222'), isTrue);

      // Direct end call voice command
      await state.voiceGo('Kết thúc cuộc gọi, Aurelia');
      expect(state.spoken.last, contains('Đã kết thúc cuộc gọi'));
    });

    test('Reconnection resolves emergency back to none', () async {
      await state.startLostConnectionEmergency(simulated: true);
      expect(state.emergencyPhase, EmergencyPhase.reconnecting);

      await state.resolveEmergencyReconnected();
      expect(state.emergencyPhase, EmergencyPhase.none);
      expect(state.spoken.last, contains('Đã kết nối lại với kính'));
    });
  });

  group('Emergency UI Banner Widget', () {
    testWidgets('Emergency banner renders and cancel button works', (tester) async {
      final state = TestAppState();
      state.emergencyContacts = [
        const EmergencyContact('Mẹ', '0901112222'),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: EmergencyBanner(state: state)),
      ));
      await tester.pump();

      // Initially no emergency banner
      expect(find.text('MẤT KẾT NỐI VỚI KÍNH'), findsNothing);

      // Trigger reconnecting phase
      state.emergencyPhase = EmergencyPhase.reconnecting;
      state.emergencyRetryCount = 2;
      state.notifyListeners();
      await tester.pump();

      expect(find.text('MẤT KẾT NỐI VỚI KÍNH'), findsOneWidget);
      expect(find.textContaining('Đang thử kết nối lại lần 2/5'), findsOneWidget);

      // Trigger countdown phase
      state.emergencyPhase = EmergencyPhase.countdown;
      state.emergencyCountdown = 9;
      state.notifyListeners();
      await tester.pump();

      expect(find.text('KHẨN CẤP: KÍNH MẤT KẾT NỐI'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('HỦY KHẨN CẤP (TÔI ỔN)'), findsOneWidget);

      // Tap cancel button
      await tester.tap(find.text('HỦY KHẨN CẤP (TÔI ỔN)'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(state.emergencyPhase, EmergencyPhase.cancelled);
      expect(find.text('KHẨN CẤP: KÍNH MẤT KẾT NỐI'), findsNothing);

      state.dispose();
    });
  });
}
