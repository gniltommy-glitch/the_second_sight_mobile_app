import 'package:flutter_test/flutter_test.dart';
import 'package:secondsight/services/voice_intent.dart';

void main() {
  void go(String said, String expected) {
    final i = parseIntent(said);
    expect(i.command, VoiceCommand.go, reason: said);
    expect(i.destination, expected, reason: said);
  }

  test('destination with origin phrase is extracted, origin ignored', () {
    go('hôm nay điểm đến là chợ Bến Thành còn nơi đi là nhà', 'chợ Bến Thành');
    go(
      'điểm đến là bệnh viện Chợ Rẫy, nơi đi là trường học',
      'bệnh viện Chợ Rẫy',
    );
    go('nơi đi là nhà điểm đến là công viên Tao Đàn', 'công viên Tao Đàn');
    go('đi từ nhà đến chợ Bến Thành', 'chợ Bến Thành');
  });

  test('common Vietnamese phrasings', () {
    go('đưa tôi đến bệnh viện Từ Dũ', 'bệnh viện Từ Dũ');
    go('tôi muốn đi siêu thị Coopmart nhé', 'siêu thị Coopmart');
    go('chỉ đường tới nhà thờ Đức Bà', 'nhà thờ Đức Bà');
    go('về nhà', 'nhà');
    go('Aurelia ơi dẫn đường đến công viên Lê Văn Tám', 'công viên Lê Văn Tám');
    go('chợ Bến Thành', 'chợ Bến Thành');
    go('Aurealia ơi điểm đến là chợ Bến Thành', 'chợ Bến Thành');
    go('hôm nay đi bệnh viện', 'bệnh viện');
  });

  test('speech without diacritics still works', () {
    go('diem den la cho ben thanh', 'cho ben thanh');
    go('dua toi den benh vien', 'benh vien');
  });

  test('control commands', () {
    expect(parseIntent('dừng lại').command, VoiceCommand.stop);
    expect(parseIntent('kết thúc').command, VoiceCommand.stop);
    expect(parseIntent('tôi đang ở đâu').command, VoiceCommand.where);
    expect(parseIntent('lặp lại').command, VoiceCommand.repeat);
    // Place names that fold like "dừng" must not stop the journey.
    go('đến khu công nghiệp Dung Quất', 'khu công nghiệp Dung Quất');
  });

  test('direct call and location sharing commands', () {
    final call1 = parseIntent('gọi cho Mẹ');
    expect(call1.command, VoiceCommand.call);
    expect(call1.recipient, 'Mẹ');

    final call2 = parseIntent('Aurelia ơi gọi cho anh Nam nhé');
    expect(call2.command, VoiceCommand.call);
    expect(call2.recipient, 'anh Nam');

    final call3 = parseIntent('gọi 115');
    expect(call3.command, VoiceCommand.call);
    expect(call3.recipient, '115');

    final call4 = parseIntent('gọi cấp cứu');
    expect(call4.command, VoiceCommand.call);
    expect(call4.recipient, 'cấp cứu');

    final share1 = parseIntent('chia sẻ vị trí');
    expect(share1.command, VoiceCommand.shareLocation);
    expect(share1.recipient, isNull);

    final share2 = parseIntent('chia sẻ vị trí cho Mẹ');
    expect(share2.command, VoiceCommand.shareLocation);
    expect(share2.recipient, 'Mẹ');

    final share3 = parseIntent('gửi GPS cho tất cả');
    expect(share3.command, VoiceCommand.shareLocation);
    expect(share3.recipient, 'tất cả');

    expect(parseIntent('kết thúc cuộc gọi, Aurelia').command, VoiceCommand.endCall);
    expect(parseIntent('kết thúc cuộc gọi').command, VoiceCommand.endCall);
    expect(parseIntent('dừng cuộc gọi').command, VoiceCommand.endCall);
    expect(parseIntent('hủy khẩn cấp').command, VoiceCommand.cancelEmergency);
  });

  test('empty or meaningless input is unknown', () {
    expect(parseIntent('Aurelia ơi').command, VoiceCommand.unknown);
    expect(parseIntent('Aurealia').command, VoiceCommand.unknown);
    expect(parseIntent('').command, VoiceCommand.unknown);
    expect(parseIntent('đến').command, VoiceCommand.unknown);
  });
}
