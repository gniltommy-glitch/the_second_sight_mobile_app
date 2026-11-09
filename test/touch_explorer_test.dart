import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/ui/widgets/touch_explorer.dart';

void main() {
  testWidgets('reads crossed targets once without activating buttons', (
    tester,
  ) async {
    final spoken = <String>[];
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TouchExplorer(
          onRead: (text) async => spoken.add(text),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(
                onPressed: () => taps++,
                child: const Text('Bắt đầu'),
              ),
              const SizedBox(height: 80),
              const Text('Hệ thống đã sẵn sàng'),
              const SizedBox(height: 80),
              const FilledButton(onPressed: null, child: Text('Lấy tuyến')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Bắt đầu')),
    );
    await tester.pump();
    expect(spoken, ['Bắt đầu. Nút']);
    await gesture.moveTo(tester.getCenter(find.text('Hệ thống đã sẵn sàng')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(spoken.last, 'Hệ thống đã sẵn sàng');
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump(const Duration(milliseconds: 80));
    expect(spoken, hasLength(2));
    await gesture.moveTo(tester.getCenter(find.text('Lấy tuyến')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(spoken.last, 'Lấy tuyến. Nút. Hiện chưa khả dụng');
    await gesture.up();
    expect(taps, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reads icon labels and yields to the system screen reader', (
    tester,
  ) async {
    final spoken = <String>[];
    Widget app(bool screenReader) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(accessibleNavigation: screenReader),
        child: TouchExplorer(onRead: (s) async => spoken.add(s), child: child!),
      ),
      home: Scaffold(
        body: Center(
          child: IconButton(
            tooltip: 'Trợ giúp khẩn cấp',
            onPressed: () {},
            icon: const Icon(Icons.sos),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(false));
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    expect(spoken.single, contains('Trợ giúp khẩn cấp'));
    spoken.clear();
    await tester.pumpWidget(app(true));
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    expect(spoken, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reads the visible dialog instead of the underlying page', (
    tester,
  ) async {
    final spoken = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            TouchExplorer(onRead: (s) async => spoken.add(s), child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const AlertDialog(content: Text('Xác nhận điểm đến')),
                ),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    spoken.clear();
    await tester.tap(find.text('Xác nhận điểm đến'));
    expect(spoken.single, 'Xác nhận điểm đến');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'switches between native TalkBack and fallback without duplicate speech',
    (tester) async {
      final spoken = <String>[];
      var cancelled = 0;
      Widget app(bool active) => MaterialApp(
        builder: (context, child) => TouchExplorer(
          systemReaderActive: active,
          onSystemReaderActivated: () async {
            cancelled++;
          },
          onRead: (text) async => spoken.add(text),
          child: child!,
        ),
        home: const Scaffold(body: Center(child: Text('Nội dung'))),
      );
      await tester.pumpWidget(app(false));
      await tester.pump();
      await tester.tap(find.text('Nội dung'));
      expect(spoken, hasLength(1));
      await tester.pumpWidget(app(true));
      await tester.pump();
      await tester.tap(find.text('Nội dung'));
      expect(spoken, hasLength(1));
      expect(cancelled, 1);
      await tester.pumpWidget(app(false));
      await tester.pump();
      await tester.tap(find.text('Nội dung'));
      expect(spoken, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
