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
| GPS quá 8 giây hoặc sai số >30 m | Gửi hold, không phát chỉ dẫn rẽ mới |
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
