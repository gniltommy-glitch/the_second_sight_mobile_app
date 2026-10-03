# Kiểm thử tích hợp trên thiết bị

Các mục dưới đây là kế hoạch nghiệm thu, chưa phải kết quả đã đạt.

| Tình huống | Kết quả cần thấy |
|---|---|
| Cài mới, chưa cấp GPS | App giải thích quyền, không giả vị trí hoặc bắt đầu chỉ dẫn |
| GPS từ chối vĩnh viễn | Hiển thị lỗi và có nút mở quyền ứng dụng |
| Micro bị từ chối | Vẫn nhập địa chỉ bằng bàn phím được |
| Key bản đồ sai/quá quota | Hiện lỗi, không âm thầm tạo tuyến giả |
| Tìm nơi ở Việt Nam | Kiểm tra địa danh, profile foot, trật tự lng/lat |
| Route có vòng và đường song song | Không nhảy tùy tiện sang đoạn gần đích; đối chiếu thực địa |
| Đi lệch trên 35 m với 4 GPS tốt | Tạm dừng lệnh rẽ, tính lại tối đa một lần/25 giây |
| Lệch tuyến khi mất Internet | Giữ tuyến lưu, báo không thể tính lại; không chỉ rẽ theo đoạn sai |
| GPS quá 8 giây hoặc sai số >20 m | Gửi hold, không phát chỉ dẫn rẽ mới |
| Mất mạng 4G nhưng LAN còn | Tuyến đã tải tiếp tục; tile/search/reroute có thể mất |
| Đóng và mở app | Tuyến cache ở trạng thái ready, không tự chạy lại |
| Nhập token sai | Server từ chối; không nhận telemetry hoặc điều khiển |
| Hotspot đổi IP Pi | Hostname mDNS hoặc cập nhật IP được; không hard-code trong mã |
| Dừng server Pi | App phát hiện mất kết nối; Pi thật vẫn perception cục bộ |
| Nối lại | Đồng bộ snapshot, revision, bước hiện tại trước chỉ dẫn |
| Dừng khi offline, rồi nối lại | Pi giữ ready/idle, không tự resume lệnh cũ |
| Hazard lúc đang đọc route | Hazard ngắt audio, route cũ không được tiếp tục nói đè |
| Telemetry mất trên 6 giây | UI bỏ số liệu cũ, hiện chưa có dữ liệu |
| Cảm biến báo false | UI hiển thị lỗi, nhật ký có sự kiện |
| SOS trên iPhone/Android/iPad | Mở dialer/share sheet đúng; hủy không báo đã gửi |
| Mô phỏng → chế độ thật | Xóa tuyến/vị trí giả, yêu cầu GPS thật |
| Khóa màn hình 5–15 phút | Đo GPS, heartbeat, pin; xác nhận watchdog khi OS đình chỉ |
| Tiết kiệm pin, force-stop | Pi dừng GPS navigation trong TTL và giữ cảm biến |
| TalkBack / VoiceOver | Đọc được nút, chỉ dẫn, lỗi; tác vụ chính không phụ thuộc riêng bản đồ |
| Chữ lớn 200% | Cuộn được, không mất nút SOS/bắt đầu/dừng |

Trước khi người dùng dựa vào kính để đi lại: nghiệm thu riêng phần cứng, sensor placement/calibration, vùng không quan sát được, độ trễ đầu cuối và cách phản ứng khi cảm biến hỏng. App không chứng thực độ an toàn của perception.

## Kiểm tra bổ sung FLP / STM32 / 3D

- Mẫu GPS đầu tiên >20 m, timestamp tương lai, cũ >8 giây hoặc trùng: không được nhận.
- Dẫn đường/off-route: HIGH; pause/stop/arrive: BALANCED. Đo mức pin và khả năng lấy fix thật ở từng chế độ.
- OkHttp: bearer handshake, sai token, reconnect, mất mạng khi handshake, app bị hủy, TLS certificate hợp lệ.
- STM32: 359° → mục tiêu 1° cho sai lệch +2°; chưa hiệu chuẩn, lỗi serial hoặc quá 500 ms không xác nhận hướng.
- Xác nhận hướng chỉ ở lệnh rẽ và cách điểm rẽ ≤12 m; target là hướng đoạn sau điểm rẽ, tham chiếu Bắc thật.
- Giữ hazard camera/cảm biến đang phát khi rút STM32; không nhận xác nhận hướng từ cờ giả do app gửi.
- Kiểm tra revision bo, calibration, trục lắp, declination và nhiễu từ thực tế. Nghiệm thu phần firmware HAL/driver riêng.
- 3D: tắt chuyển động; bật giảm chuyển động hệ điều hành; chữ lớn; trạng thái standby/đã hiệu chuẩn/mô phỏng.
