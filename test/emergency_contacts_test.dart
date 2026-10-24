import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/core/models.dart';

void main() {
  test('migrates legacy single number', () {
    final list = EmergencyContact.decode(null, legacy: ' 0901234567 ');
    expect(list.length, 1);
    expect(list.first.phone, '0901234567');
    expect(list.first.label, '0901234567');
  });

  test('round-trips many contacts with notes and drops empty numbers', () {
    final json = EmergencyContact.encode(const [
      EmergencyContact('Mẹ', '0901'),
      EmergencyContact('Anh Nam (hàng xóm)', '0902'),
      EmergencyContact('Trống', ''),
    ]);
    final list = EmergencyContact.decode(json, legacy: 'ignored');
    expect(list.map((c) => c.label), ['Mẹ', 'Anh Nam (hàng xóm)']);
    expect(list.map((c) => c.phone), ['0901', '0902']);
  });

  test('saved empty list does not resurrect legacy number', () {
    expect(EmergencyContact.decode('[]', legacy: '0901'), isEmpty);
  });
}
