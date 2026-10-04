# SecondSight — ứng dụng đồng hành với kính

Mã nguồn Flutter dùng chung Android/iOS, giao diện tiếng Việt. Điện thoại lấy GPS, tìm tuyến đi bộ và gửi chỉ dẫn; kính chịu trách nhiệm nhận thức môi trường, ưu tiên an toàn và phát âm thanh. Không có video streaming hoặc YOLO trên điện thoại.

**Cập nhật 02/10/2026:** FLP lọc vị trí ≤20 m / ≤8 giây, Android dùng OkHttp WebSocket native, Pi có `STM32IMUReceiverThread`, lõi Mahony C và giao diện Flutter 3D/HUD. Có kiểm thử phần mềm; chưa nghiệm thu trên Android/Pi/STM32 thật. Xem [báo cáo kiểm tra](docs/VALIDATION.md).

## 1. Chạy app

Cần Flutter stable (cấu hình CI: 3.47.5), Python 3, Android SDK + Java 17 cho Android; macOS + Xcode + CocoaPods cho iOS. Kiểm tra `flutter doctor` trước.

```bash
cd secondsight
python3 scripts/bootstrap.py
flutter analyze --no-fatal-infos
flutter test
flutter run
```

Windows dùng `python` thay `python3`. Chọn thiết bị bằng `flutter devices`, sau đó `flutter run -d DEVICE_ID`.

`bootstrap.py` tự tạo hai project native `android/` và `ios/` bằng template chính thức của SDK đang cài, bổ sung quyền GPS, micro, LAN và cấu hình nền, rồi chạy `flutter pub get`. Không ghi đè `lib/`, `test/` hay `pubspec.yaml`. Gói này đã có hai thư mục native; phải giữ cầu nối OkHttp trong Android khi tái tạo runner. Chạy lại script được; nó giữ các project đã tạo và cập nhật các quyền do script quản lý. Script không tạo certificate ký app.

### Thử ngay không có kính hoặc API key

1. Mở **Cài đặt → Chế độ mô phỏng**.
2. Vào **Dẫn đường → Bắt đầu hành trình**.
3. Vị trí mô phỏng tự di chuyển mỗi giây; app đọc chỉ dẫn tiếng Việt.
4. Vào **Kính → Thử cảnh báo mép hụt** để thử ưu tiên cảnh báo.
5. Nhấn tạm dừng/tiếp tục/kết thúc. Nhật ký ghi các sự kiện.

Dữ liệu mô phỏng được gắn nhãn. Không gửi tuyến mô phỏng sang Pi thật. Tile bản đồ nền vẫn cần mạng; hình tuyến mô phỏng không cần API key. Nếu thiếu giọng đọc tiếng Việt, cài voice của hệ điều hành.

## 2. Bản đồ thật

Tạo API key GraphHopper, nhập trong **Cài đặt → GraphHopper API key → Lưu**. Tài khoản phải hỗ trợ profile `foot`. App gửi `profile=foot` và `points_encoded=false`; không dùng tuyến ô tô thay thế khi lỗi.

1. Tắt mô phỏng, cấp quyền vị trí chính xác.
2. Tìm địa chỉ bằng chữ/giọng nói hoặc nhấn giữ bản đồ.
3. Điểm A là GPS hiện tại; điểm B là điểm bạn chọn.
4. Nhấn **Lấy tuyến đi bộ** để xem tuyến, khoảng cách, ETA và từng bước.
5. Kết nối kính rồi nhấn **Bắt đầu hành trình**.

API key và token được lưu bằng secure storage. Đây là mô hình BYOK cho prototype: không nhúng key dùng chung vào binary. Với app phân phối rộng, thay RoutingService bằng backend proxy có xác thực, quota và khóa giữ trên server. GraphHopper có chính sách tính phí riêng. Có thể viết adapter Valhalla/GraphHopper tự host dựa trên cùng `WalkRoute`; gói này chỉ triển khai GraphHopper hosted.

Bản đồ nền dùng OpenStreetMap, có attribution. Không tải hàng loạt hoặc cache offline toàn vùng từ public tile server. Khi triển khai nhiều người dùng, cấu hình tile provider phù hợp hạn mức/chính sách.

## 3. Chạy Pi mô phỏng để thử kết nối thật

Server trong `pi_demo/` là bộ tham chiếu giao thức. Các thông số pin/FPS/cảm biến là **giả lập**, không phải driver phần cứng. Có thể chạy trên Pi hoặc máy tính cùng Wi-Fi.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r pi_demo/requirements.txt
export SECONDSIGHT_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
# Xem token này ở terminal của bạn để nhập vào app; không commit hoặc chia sẻ nó.
printf '%s\n' "$SECONDSIGHT_TOKEN"
python3 pi_demo/server.py
```

Trên Windows đặt biến môi trường tương đương trong PowerShell. Để phát giọng trên Pi, cài `espeak-ng` có voice tiếng Việt rồi đặt `SECONDSIGHT_VOICE=1` trước khi chạy server. Nếu không bật, server in thông điệp âm thanh ra console; không giả vờ có loa thật.

Trong app:

- Tắt mô phỏng nội bộ để kiểm tra kết nối LAN thật.
- Địa chỉ: `http://secondsight.local:8765` nếu đã đặt hostname Pi là secondsight và bật mDNS/Avahi; nếu không, nhập `http://<IP-LAN-Pi>:8765`.
- Nhập token giống biến môi trường phía server.
- Bật **HTTP LAN thử nghiệm**, lưu, rồi bấm **Kết nối kính**.
- Màn hình Kính vẫn ghi rõ số liệu mô phỏng khi nhận `demo: true` từ server.

Hotspot phải do người dùng bật trong Settings của điện thoại. Pi phải được cấu hình Wi-Fi vào hotspot trước. App không tự cấp Wi-Fi credentials cho Pi. Một số hotspot không hỗ trợ phân giải mDNS ổn định; dùng IP LAN là đường dự phòng. Chưa có UDP discovery.

Để thử ngắt chỉ dẫn bằng hazard trên Pi:

```bash
curl -X POST http://127.0.0.1:8765/demo/hazard \
  -H "Authorization: Bearer $SECONDSIGHT_TOKEN"
```

Pi thật thay telemetry và `/demo/hazard` bằng sensor fusion/Decision Manager của bạn. Giữ watchdog và ưu tiên cục bộ ngay cả khi app mất kết nối. Chi tiết trong [docs/PROTOCOL.md](docs/PROTOCOL.md).

## 4. Tính năng đã có trong source

| Nhóm | Luồng đã triển khai |
|---|---|
| Điểm đến | Tìm chữ/giọng nói, chọn trên bản đồ, lưu/xóa yêu thích |
| Tuyến | GPS điện thoại, tuyến đi bộ, polyline, ETA, danh sách bước |
| Điều hướng | Bắt đầu/tạm dừng/tiếp tục/kết thúc, khoảng cách theo tuyến |
| Lệch tuyến | 4 mẫu GPS tốt lệch trên 35 m, cooldown tính lại 25 giây |
| Offline | Lưu một tuyến, mở lại thủ công, giữ tuyến nếu tính lại thất bại |
| Kết nối | Hostname mDNS/IP cấu hình, bearer token, heartbeat, reconnect backoff |
| Đồng bộ | Snapshot phiên/tuyến/bước, revision, sequence, TTL chỉ dẫn |
| Trạng thái | Pin/FPS/nhiệt độ/cảm biến; quá 6 giây đánh dấu chưa có dữ liệu |
| Cài đặt | Mức cảnh báo, âm lượng, tốc độ, rung; đồng bộ khi kết nối |
| SOS | Mở trình gọi người thân hoặc share sheet chứa vị trí mới và sai số |
| Nhật ký | 300 sự kiện cục bộ, xuất nội dung JSON qua share sheet, xóa |
| Demo | Mô phỏng app nội bộ và server Pi tham chiếu độc lập |

Route cache không phải bộ máy routing offline, cũng không bảo đảm tile bản đồ đã tải. Tìm kiếm/tính lại tuyến cần mạng. Cache được phục hồi ở trạng thái chờ; app không tự tiếp tục hành trình cũ sau khi khởi động.

App tạm ngừng gửi chỉ dẫn rẽ hợp lệ khi GPS quá 8 giây, sai số trên 20 m hoặc lệch tuyến. Pi ngừng chỉ dẫn sau TTL tối đa 3 giây nếu không nhận cập nhật. Khi reconnect, snapshot được đồng bộ trước các chỉ dẫn tiếp theo. Lệnh dừng khi offline được đồng bộ lúc nối lại; watchdog phía Pi chịu trách nhiệm dừng ngay trong khoảng mất kết nối.

## 5. Build

```bash
# Sau bootstrap và kiểm thử
flutter build apk --debug
# File: build/app/outputs/flutter-apk/app-debug.apk

# Android phát hành: cấu hình keystore/signing trước
flutter build appbundle --release

# macOS, Xcode, iOS simulator
flutter build ios --simulator --debug

# iPhone thật: mở ios/Runner.xcworkspace, chọn Team/bundle ID và signing
flutter build ipa --release
```

Workflow `.github/workflows/check.yml` kiểm tra Flutter, build APK debug và build iOS simulator khi bạn đưa source lên GitHub. Workflow chưa được chạy trong phiên bàn giao. Nó không upload App Store, không tạo IPA đã ký và không tạo bản Android release đã ký.

## 6. Các điểm phải kiểm chứng khi tích hợp

- GPS nền: đã cấu hình Android foreground location service và iOS background location. Timer/WebSocket nền vẫn phụ thuộc hệ điều hành. Force-stop, tiết kiệm pin, đổi hotspot hoặc khóa máy có thể ngắt app. Kiểm tra riêng từng thiết bị; không khẳng định 1 Hz tuyệt đối trong nền.
- App giữ màn hình sáng trong hành trình để giảm gián đoạn demo. Quyền vị trí được xin khi sử dụng; iOS có thể yêu cầu quyền bổ sung ở Settings để chạy nền theo cấu hình thực tế.
- HTTP LAN chỉ cho thử nghiệm mạng riêng. Bản triển khai dùng TLS với certificate tin cậy cho HTTPS/WSS; app không vô hiệu hóa xác minh certificate. Server mẫu chưa có TLS tích hợp, cần reverse proxy hoặc cấu hình SSL của aiohttp.
- Rung trong app dùng haptic hệ điều hành, không bảo đảm hoạt động khi màn hình tắt. Rung trên kính cần firmware/driver thực thi cấu hình được gửi xuống.
- API chỉ dẫn đi bộ không bảo đảm gắn nhãn mọi vạch qua đường/đèn giao thông. App không kết luận “được phép qua đường”. Perception/traffic safety thuộc Pi.
- LD19 là LiDAR quét một mặt phẳng. Muốn phát hiện mép hụt/độ cao bậc phải có bố trí cảm biến, hiệu chuẩn và kiểm thử phù hợp. Code app không biến cảm biến thành hệ nhận thức đã được chứng nhận.
- SOS không có backend theo dõi trực tiếp hay gửi tự động. Người dùng chọn cuộc gọi/người nhận bằng ứng dụng hệ thống.

Xem [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) để chạy kiểm thử trên thiết bị; [docs/VALIDATION.md](docs/VALIDATION.md) ghi chính xác phần đã kiểm tra trong gói bàn giao.

## 7. Mã nguồn

- `lib/core/models.dart`: route, maneuver, phép chiếu lên tuyến, tính tiến trình.
- `lib/core/app_state.dart`: trạng thái app, GPS, cache, đồng bộ, mô phỏng, nhật ký.
- `lib/services/routing.dart`: GraphHopper search/routing, fixture demo.
- `lib/services/pi_link.dart`: REST/WebSocket, token, heartbeat/reconnect.
- `lib/ui/home.dart`: bản đồ, điều hướng, kính, SOS, nhật ký, cài đặt.
- `lib/main.dart`: khởi động, theme, locale.
- `pi_demo/`: server Python, ưu tiên âm thanh tham chiếu, kiểm thử giao thức.
- `scripts/bootstrap.py`: tạo/cấu hình runners Android/iOS chính thức.
- `test/`: kiểm thử hình học điều hướng và hợp đồng routing.

Tài liệu API dùng để đối chiếu: [GraphHopper](https://docs.graphhopper.com/), [flutter_map](https://pub.dev/packages/flutter_map), [Geolocator](https://pub.dev/packages/geolocator), [Speech to Text](https://pub.dev/packages/speech_to_text), [Share Plus](https://pub.dev/packages/share_plus/versions/11.1.0), [Secure Storage](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4).
# the_second_sight_mobile_app

## 8. Kiến trúc cập nhật

### Vị trí điện thoại

Sử dụng Fused Location Provider API để kết hợp GPS, Wi-Fi và mạng di động, giúp tối ưu độ chính xác và mức tiêu thụ pin. Khi đang dẫn đường sử dụng `PRIORITY_HIGH_ACCURACY`; khi chưa dẫn đường sử dụng `PRIORITY_BALANCED_POWER_ACCURACY`. Đọc latitude, longitude, accuracy, speed, bearing và timestamp; loại dữ liệu cũ hoặc có accuracy >20 m.

Trong Flutter, `geolocator_android` gọi FLP với `forceLocationManager:false`: `bestForNavigation` tương ứng HIGH, `medium` tương ứng BALANCED. Ngưỡng dữ liệu cũ là 8 giây; cũng bỏ timestamp tương lai và mẫu đến sai thứ tự, kể cả lúc khởi động. Pause/stop/arrive chuyển về BALANCED; đổi chế độ mô phỏng hủy stream thật. BALANCED không bảo đảm sai số ≤20 m, vì vậy có thể phải chờ fix đạt yêu cầu. Không hạ ngưỡng kiểm tra để lách yêu cầu chính xác.

### Kết nối app–Pi

Phía Android dùng **OkHttp WebSocket** để truyền chỉ dẫn tới Raspberry Pi qua platform channel `secondsight/okhttp`. Bearer token ở header handshake; heartbeat và reconnect có backoff. Snapshot phiên và cấu hình tiếp tục qua REST có xác thực theo giao thức hiện hữu. iOS dùng WebSocket `dart:io`; browser chỉ xem giao diện/mô phỏng vì không đặt được Authorization header của WebSocket như app native.

### STM32F411E-DISCO

Đọc accelerometer, gyroscope và magnetometer trên bo; chạy Mahony (một lựa chọn trong Madgwick/Mahony) để tính quaternion, heading, pitch và roll; gửi sang Pi bằng UART hoặc USB Serial. Pi dùng `STM32IMUReceiverThread` để nhận hướng, kiểm tra calibration/freshness và so sánh `target_bearing` với `current_heading`.

`firmware/stm32/mahony.c` là lõi fusion có kiểm thử, chưa phải firmware CubeIDE hoàn chỉnh. Hướng dẫn driver theo revision, hiệu chuẩn, hệ trục, declination và truyền serial nằm trong [firmware/stm32/README.md](firmware/stm32/README.md).

Chạy Pi với biến môi trường `SECONDSIGHT_IMU_PORT=/dev/serial0` hoặc đường dẫn USB Serial. Nếu không đặt, receiver không khởi động và trạng thái IMU là chưa có dữ liệu; không giả vờ đã hiệu chuẩn. Telemetry camera/LiDAR của server này vẫn là mô phỏng và luôn có `demo:true`.

### Xử lý lỗi

STM32 mất kết nối, dữ liệu quá 500 ms hoặc chưa hiệu chuẩn → không dùng heading để xác nhận hướng rẽ. Luồng cảnh báo vật cản bằng camera và cảm biến trên Pi độc lập và tiếp tục hoạt động khi các cảm biến đó còn hoạt động. App không dùng la bàn điện thoại thay heading đã hiệu chuẩn. Pi tự quyết định độ hợp lệ, không tin cờ `stm32_heading_valid` do điện thoại gửi.

### Giao diện

Giữ Flutter để bảo toàn app Android/iOS. Bộ component dùng Material 3, `flutter_animate` và `vector_math`: quỹ đạo/khối hướng có phép chiếu 3D, bảng HUD, trạng thái IMU và kính mờ. Phông Be Vietnam Pro được đóng gói để đọc tiếng Việt offline. Tông đen mực / xanh ngọc, chi tiết chữ Nhật tiết chế; không nhúng React hoặc web view vào app. Khối 3D có nút dừng và tôn trọng giảm chuyển động của hệ điều hành. Trạng thái STANDBY không biểu diễn một hướng đo thật.

Nguồn kỹ thuật: [FLP Priority](https://developers.google.com/android/reference/com/google/android/gms/location/Priority), [OkHttp WebSockets](https://square.github.io/okhttp/), [BSP STM32F411E-Discovery](https://github.com/STMicroelectronics/32f411ediscovery-bsp).


## Aurelia — nhập điểm đến bằng giọng nói

Chọn luồng điểm đi = GPS hiện tại. Sau khi cấp quyền micro, nhận dạng giọng
nói và vị trí, mở app: Aurelia hỏi điểm đến và tự mở mic. Nói “chợ Bến Thành”
hoặc “Aurelia ơi, hôm nay điểm đến là chợ Bến Thành còn nơi đi là nhà”.
App lấy phần điểm đến, tìm địa điểm (ưu tiên yêu thích), tính tuyến từ GPS và
bắt đầu dẫn đường, không cần bấm Tìm, Lấy tuyến hay Bắt đầu. Phần nơi đi trong
câu nói không thay thế GPS. Ô tìm kiếm hiển thị điểm đến đã nhận dạng.

Nếu chưa nghe rõ hoặc không tìm thấy, app tự mở lại một phiên nghe sau lời
nhắc. Nút mic và chạm đúp màn hình vẫn có thể mở phiên nghe thủ công; hủy nghe
sẽ dừng tự nghe cho tới khi mở lại mic. App ngừng nghe khi ra nền và không tự
mở mic trong hành trình để tránh thu lại chỉ dẫn. Khi có nhiều kết quả tìm kiếm,
app dùng kết quả đầu tiên và đọc tên địa điểm được chọn.

Không tích hợp Picovoice Porcupine hay khóa dịch vụ nhận dạng riêng. Đây là
nhận dạng câu ngắn khi app ở trước màn hình, **không phải gọi đánh thức nền
như Siri**. “Aurelia”/“Aurealia” trong câu là tiền tố tùy chọn. Nhận dạng phụ
thuộc dịch vụ hệ điều hành và có thể cần mạng. GraphHopper vẫn cần API key như
luồng nhập tay; hành trình thật vẫn yêu cầu kính đã kết nối và GPS đạt chuẩn.
Nếu thiếu quyền/dịch vụ nhận dạng, app đọc lỗi và dừng thử lại tự động.

Kiểm tra trên thiết bị thật: cấp/từ chối quyền lần đầu; im lặng rồi nói ở phiên
kế tiếp; nói câu ví dụ trên; chuyển app ra nền trong lúc nghe; tắt mạng;
thử GPS yếu và kính chưa kết nối; xác nhận không thông báo đã bắt đầu khi lỗi.

### Bản sửa âm thanh 1.1.1+3

- Khai báo `android.intent.action.TTS_SERVICE` trong APK và script bootstrap.
- Lời chào Aurelia chạy trước khi khởi tạo dịch vụ nhận dạng; thiếu quyền mic
  không còn chặn lời chào. Mic chỉ mở sau khi câu hỏi đọc xong.
- Câu đọc thường được phát tuần tự; cảnh báo khẩn, tạm dừng và kết thúc mới
  ngắt hàng đợi. Chờ TTS có giới hạn; lỗi/thiếu giọng tiếng Việt hiện thông báo
  và sự kiện `tts_error` trong Nhật ký, không bị bỏ qua.
- Bắt đầu mô phỏng bằng nút sẽ đọc ngay chỉ dẫn đầu tiên và đóng mic để không
  nhận nhầm tiếng của app thành điểm đến mới.
- Kiểm thử dùng dịch vụ giọng nói giả lập; vẫn cần nghe và nói thử trên Android
  thật. Điện thoại phải có dịch vụ TTS với giọng tiếng Việt, dịch vụ nhận dạng
  giọng nói và quyền micro. Âm lượng phương tiện của hệ điều hành cần bật.
