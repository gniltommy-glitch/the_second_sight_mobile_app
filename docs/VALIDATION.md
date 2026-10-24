# Báo cáo kiểm tra cập nhật

Ngày: 02/10/2026. Môi trường: macOS, Flutter 3.47.5 / Dart 3.13.4.

## Đã chạy

| Kiểm tra | Kết quả |
|---|---|
| Flutter analyze `--no-fatal-infos` | PASS: không error/warning; còn lint mức info trong mã hiện hữu |
| Flutter test | PASS: 14 tests |
| Python `unittest discover -s pi_demo -v` | PASS: 9 tests |
| Python `unittest discover -s scripts -p 'test_*.py' -v` | PASS: 1 test |
| C11 Mahony với `-Wall -Wextra -Werror` và test executable | PASS |
| Flutter web release build | PASS |
| Xem giao diện trong browser cục bộ | Đã thấy khối 3D/HUD, trạng thái chờ IMU và điều hướng |

Test Flutter bao gồm hình học tuyến, routing, FLP policy, lọc GPS đầu tiên/sai số/timestamp tương lai và cũ, handshake WebSocket có bearer trên transport dart:io, thông điệp hai chiều, từ chối HTTP chưa bật thử nghiệm và layout component 3D ở chiều rộng 320/430/900 với chữ 140%.

Test Python kiểm tra HTTP auth, revision, sequence replay, heartbeat, pause, ưu tiên hazard, TTL và STM32: chuẩn hóa quaternion, dữ liệu lỗi/NaN, mất kết nối, mất calibration, replay, freshness 500 ms, wraparound 359° → 1°. Test C kiểm tra tư thế đứng yên, hội tụ yaw 90°, đầu vào lỗi, packet và buffer quá nhỏ.

## Chưa kiểm chứng

- Build APK/AAB và chạy OkHttp platform channel trên Android thật: máy chưa có Android SDK.
- iOS simulator/IPA: môi trường thiếu runtime/CocoaPods.
- Firmware STM32Cube/HAL trên bo, đọc sensor thực, UART/USB thực và hiệu chuẩn. Chỉ có lõi fusion C portable và hướng dẫn tích hợp; chưa có image firmware đã flash.
- Driver perception camera/LD19/cảm biến khoảng cách thật. `pi_demo` vẫn là simulator; mở serial thật không biến số liệu camera/pin/FPS thành dữ liệu thật.
- GraphHopper với key thật, GPS nền, hotspot, giọng đọc, đo pin, độ chính xác heading và nhận biết rẽ ngoài thực địa.
- GitHub Actions sau khi cập nhật phiên bản Flutter.

Web build chỉ hỗ trợ xem giao diện và mô phỏng, không thay thế kiểm thử native. Kiểm thử transport dart:io không kiểm chứng OkHttp. Các ngưỡng 20 m, 8 s, 500 ms, ±15° và 12 m là chính sách prototype cần kiểm thử với thiết bị và tình huống thực.

Xem `ACCEPTANCE.md` và `firmware/stm32/README.md` cho các bước kiểm thử thiết bị.


## Kiểm tra bản Aurelia 1.2.0+5 — 04/10/2026

- Flutter 3.47.5 / Dart 3.13.4: `flutter analyze` không phát hiện vấn đề.
- `flutter test`: 46 kiểm thử qua, gồm mic khi navigating/offRoute, không bị đóng bởi cập nhật GPS, nút kính, gọi Hey Aurelia và bỏ qua lời nói không có câu gọi, xác nhận điểm đến, preflight và cảnh báo suy giảm.
- Kiểm thử Python Pi: 15 kiểm thử qua, gồm xác thực thử âm thanh, chờ phone nhường loa và gia hạn im lặng suốt cảnh báo dài.
- `flutter build apk --debug`: build thành công, Android Kotlin/QR plugin được biên dịch. APK thử nghiệm, ký bằng debug key.
- `git diff --check` qua; script Python biên dịch cú pháp thành công.
- Chưa thử điện thoại/kính/tai nghe thật; chưa build iOS trong phiên này. Hey Aurelia chỉ là tùy chọn thử nghiệm khi app ở trước màn hình. iOS cần thiết lập CocoaPods và nghiệm thu camera/mic.
- Nguồn thay đổi đang có sẵn trước phiên được giữ lại; phần xác nhận điểm đến và ưu tiên Pi đã được hoàn thiện cùng các kiểm thử.

Hướng dẫn sử dụng/tích hợp tại [ASSISTIVE_CONTROLS.md](ASSISTIVE_CONTROLS.md).


## Aurelia 1.2.1+6 — mic nền Android, 04/10/2026

- `flutter analyze`: không có vấn đề. `flutter test`: 51 kiểm thử qua.
- Thêm 5 kiểm thử về phạm vi navigation/offRoute, cầu nối nền, câu gọi mở phiên lệnh, lệnh dừng ngắt dịch vụ, chặn transcript khi có hazard và tắt gọi từ thông báo. Đây là kiểm thử Flutter với platform channel giả lập, không phải thử mic nền trên Android thật.
- APK debug 1.2.1+6 build thành công, gồm `NavigationVoiceService`, foreground service type microphone, quyền micro/notification và CPU wake lock có giới hạn/gia hạn trong phiên.
- Native service không tự khởi động lại khi process bị kill, force-stop, vuốt đóng app hoặc reboot. Không lưu audio. Hoạt động nhận dạng phụ thuộc dịch vụ hệ điều hành và mạng.
- Chưa có thiết bị Android kết nối để đo hoạt động khi khóa máy, ưu tiên âm thanh, battery optimization, Bluetooth và dịch vụ tiếng Việt. Chưa triển khai mic nền iOS.

## Aurelia 1.2.2+7 — sửa phiên nghe và bỏ tự hỏi lại, 04/10/2026

- `flutter analyze`: không có vấn đề. `flutter test`: 56 kiểm thử qua.
- Thêm kiểm thử chữ nhận dạng tạm thời → kết thúc mic → điền điểm đến và xử lý đúng một lần; không tự hỏi lại sau im lặng hoặc quay lại từ nền; câu gọi ở kết quả tạm thời mở một phiên lệnh; GPS cập nhật không bỏ chữ lệnh; xác nhận không rõ chỉ hỏi một lần.
- Banner chờ tên chỉ hiện sau trạng thái đang nghe từ dịch vụ nhận dạng. Mic lệnh nền không tự thử lại khi không có câu trả lời; quay về bộ chờ câu gọi im lặng.
- APK debug 1.2.2+7 build thành công, gồm cập nhật Kotlin cho nhận câu gọi từ kết quả tạm thời và hết phiên lệnh nền.
- Chưa nghiệm thu tiếng nói thật, mic tai nghe và khóa màn hình trên điện thoại Android trong phiên làm việc này. Kiểm thử dùng kênh nhận dạng giả lập; không chứng minh khả năng nghe trên thiết bị cụ thể.

## Aurelia 1.2.3+8 — chờ câu gọi cục bộ, GPS và xem tuyến, 04/10/2026

- `flutter analyze`: không có vấn đề. `flutter test`: 60 kiểm thử qua.
- Android không gọi SpeechRecognizer trong lúc chờ tên. Vosk duy trì luồng AudioRecord liên tục, chỉ mở bộ nhận dạng lệnh sau kích hoạt. Không thay đổi âm lượng hệ thống. Kiểm thử kênh native giả lập xác nhận không có phiên nghe lệnh hoặc lời mời theo chu kỳ trong 60 giây; một sự kiện câu gọi mở đúng một phiên.
- Mô hình thực được kiểm tra trên máy phát triển với hai mẫu âm thanh tổng hợp tiếng Anh: “Hey Aurelia” nhận đúng cả hai từ với confidence 1.0; câu “Good morning. Please repeat the directions.” đi vào nhánh từ không rõ, không kích hoạt. Kiểm tra này dùng Vosk Python 0.3.44 và cùng mô hình, không phải micro/Android/Vosk Android 0.3.75 trên điện thoại thật.
- Giữ vị trí gần đúng để hiển thị; xem tuyến dùng vị trí tối đa 30 giây, sai số tối đa 100 m. Kiểm thử lập tuyến thật qua HTTP giả lập xác nhận `profile=foot` và không cần kết nối kính. GPS sai số 65 m xem được tuyến nhưng không được xem là đủ chính xác để đọc lệnh rẽ.
- Giọng nói khi chưa có kính giữ tuyến xem trước và đọc kết quả; không tự thử bắt đầu rồi báo lỗi kính. Chỉ bước Bắt đầu với kính cần kính và kiểm tra trước chuyến đi.
- APK debug 1.2.3+8 build thành công. Mô hình và thư viện native nằm trong APK; không cần tải mô hình khi chạy.
- Chưa thử mic thật, giọng người dùng, quyền vị trí, GPS ngoài trời, âm báo, khóa màn hình, RAM và hao pin trên điện thoại Android. Không suy ra các điều này từ kiểm thử giả lập/âm thanh tổng hợp.
