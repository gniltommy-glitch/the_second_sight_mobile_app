# SecondSight 1.1 · giao diện đại chúng

Cảm hứng: [React Bits](https://reactbits.dev/get-started/index), đặc biệt Spotlight Card và chuyển động xuất hiện của nội dung. Code giao diện là Flutter native; không thêm React hoặc web view vào APK. SpotlightSurface là cách triển khai riêng trong Flutter, phản hồi cả con trỏ và chạm, không bắt mất thao tác cuộn. Tôn trọng cài đặt giảm chuyển động.

- Trang Dẫn đường: lời chào ngắn, hình khối chỉ hướng có chiều sâu, CTA kết nối kính, tìm địa điểm, trạng thái vị trí, bản đồ và tuyến đi bộ.
- Màn hình Kính giữ la bàn 3D cùng thông tin IMU; không đưa tên firmware hoặc calibration vào nội dung giới thiệu cho người dùng mới.
- Màu đen mực / xanh bạc hà; chữ Be Vietnam Pro có sẵn offline; nút chạm rộng, chuyển trang nhẹ, thẻ bo góc và ánh sáng vừa phải.
- Bản đồ chuyển khỏi nguồn CARTO đang trả tile “API key required”. Bản thử dùng OSM, attribution luôn hiện, tải theo viewport và cache mặc định của flutter_map. Với phân phối đại trà, cấu hình tile provider có hạn mức và SLA phù hợp.
- Android: icon SecondSight riêng, splash tối đồng nhất với ứng dụng, không còn icon Flutter mặc định.

APK hiện là bản cài thử, dùng cấu hình ký debug để cài trực tiếp. Giao diện có thiết kế cho người dùng phổ thông nhưng không đồng nghĩa phần cứng hỗ trợ dẫn đường đã được nghiệm thu thực địa.
