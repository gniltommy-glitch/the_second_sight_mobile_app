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
