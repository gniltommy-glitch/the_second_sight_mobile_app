# Báo cáo kiểm tra bàn giao

Ngày: 2026-09-22.

## Đã chạy

| Kiểm tra | Kết quả |
|---|---|
| `python3 -m unittest discover -s pi_demo -v` | PASS — 5 tests |
| `python3 -m unittest discover -s scripts -p 'test_*.py' -v` | PASS — 1 test |
| `python3 scripts/check_syntax.py` | PASS — 8 file Dart, không có lỗi parser |
| `python3 -m py_compile scripts/bootstrap.py pi_demo/server.py` | PASS |

Python tests dùng aiohttp TestServer thật trên loopback để kiểm tra HTTP auth, revision, validation, WebSocket heartbeat, sequence replay, pause; DecisionManager được kiểm tra hazard preemption và expiry. Bootstrap test dùng fixture native để kiểm tra quyền và khả năng chạy lặp không sinh bản sao quyền. Nó không build project native.

Parser Dart kiểm tra cấu trúc ngôn ngữ, không kiểm tra kiểu, API plugin, phân giải dependency hoặc runtime UI.

## Chưa chạy

- `flutter pub get`, `flutter analyze`, `flutter test`.
- Build Android APK/AAB hoặc iOS simulator/IPA.
- Workflow GitHub Actions đi kèm.
- GraphHopper request thật với API key người dùng.
- GPS, micro, keychain, LAN/hotspot, audio, background operation trên điện thoại thật.
- Thiết bị Pi và phần cứng camera/LD19/A02YYUW/BNO085 thật.

Lý do: môi trường không có Flutter/Dart SDK; thử tải SDK bị lỗi mạng/timeout. Không có credentials GraphHopper, thiết bị mobile hoặc phần cứng Pi. Không có binary app đã biên dịch trong gói này.

## Cách tiếp tục xác minh

Chạy `python3 scripts/bootstrap.py`, `flutter analyze --no-fatal-infos`, `flutter test`, rồi build debug theo README. Các test Dart đã được viết trong `test/` để kiểm tra route cache, geometry/progress/arrival, request profile foot và lỗi provider. Kết quả của các test đó chưa được xác nhận trong phiên này. Chạy các ca thực địa trong ACCEPTANCE.md trước khi dựa vào hệ thống để đi lại.
