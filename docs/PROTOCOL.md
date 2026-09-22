# SecondSight protocol v1

Transport: REST + WebSocket cùng origin; không truyền video. Client gửi `Authorization: Bearer <token>` trên cả handshake WS lẫn REST. Token phải ngẫu nhiên, tối thiểu 24 ký tự phía reference server; không đưa token vào URL. App lưu token trong secure storage. Pi cần lưu ngoài git, phân quyền file/service appropriately.

## Điểm cuối

| Endpoint | Chức năng |
|---|---|
| `GET /ws` | Kênh JSON hai chiều |
| `POST /navigation/state` | Snapshot trạng thái mong muốn; thay cho bộ lệnh start/stop rời rạc |
| `POST /settings` | Cấu hình âm thanh/rung/mức cảnh báo |
| `GET /device/status` | Trạng thái tổng quát |
| `POST /demo/hazard` | Chỉ có ở simulator; chèn hazard để thử ưu tiên |

Reference server nhận tối đa một controller WS. Pi production nên ghép đôi vật lý, xoay token và giữ cùng token cho các API. Server demo không triển khai enrollment, nhiều người điều khiển hoặc phân quyền người dùng.

## Snapshot

```json
{
  "protocol": 1,
  "session_id": "uuid-per-journey",
  "revision": 3,
  "state": "navigating",
  "route": {
    "id": "uuid-per-route",
    "destination": {"name": "Trường", "point": [106.66, 10.76]},
    "points": [[106.6601, 10.7601], [106.6602, 10.7602]],
    "steps": [{"text": "Đến điểm đến", "street": "", "action": "arrive", "index": 1}],
    "distance": 15,
    "seconds": 12,
    "created": "2026-09-22T12:00:00.000Z",
    "demo": false
  },
  "position": [106.6601, 10.7601],
  "gps_valid": true,
  "step_index": 0
}
```

Tọa độ JSON luôn `[longitude, latitude]`. Trạng thái: `idle`, `ready`, `navigating`, `paused`, `arrived`. `ready` không được phát chỉ dẫn như `navigating`.

Pi trả `200 {"ok":true,"revision":3}` sau khi áp dụng. Cùng session, revision nhỏ hơn hiện tại trả 409; gửi lại cùng revision phải idempotent. Client chỉ gửi chỉ dẫn hợp lệ sau khi snapshot/settings được xác nhận. Mỗi hành trình mới tạo session mới; tính lại tuyến giữ session và tăng revision, tạo route_id mới.

Khi reconnect, app gửi snapshot trạng thái hiện tại, full geometry tuyến, vị trí và bước mới nhất. Dữ liệu full route không gửi mỗi giây. Sau đó stream chỉ dẫn tiếp tục. Không dùng wall clock điện thoại làm bộ đo TTL ở Pi; dùng monotonic clock tính từ lúc nhận.

## Chỉ dẫn (khoảng 1 Hz)

```json
{
  "type": "navigation_instruction",
  "protocol": 1,
  "session_id": "uuid-per-journey",
  "revision": 3,
  "sequence": 12,
  "route_id": "uuid-per-route",
  "valid_for_ms": 3000,
  "gps_valid": true,
  "action": "turn_right",
  "text": "Rẽ phải",
  "street": "Nguyễn Văn Cừ",
  "distance_m": 35,
  "step_index": 2,
  "position": [106.6601, 10.7601],
  "accuracy_m": 8
}
```

Action: `continue`, `turn_left`, `turn_right`, `roundabout`, `u_turn`, `arrive`, `hold`. `hold` hoặc `gps_valid:false` làm ngừng chỉ dẫn GPS; tuyệt đối không tắt perception hoặc hủy âm thanh hazard đang phát.

Pi bỏ frame nếu session/revision/route không khớp, sequence không tăng hoặc trạng thái không phải navigating. TTL tối đa 3 giây. Hết TTL thì dừng chỉ dẫn GPS, không phát lại một lệnh rẽ đã cũ sau hazard. Decision Manager cần deduplicate lời đọc theo step và ngưỡng khoảng cách; stream 1 Hz không có nghĩa đọc mỗi giây.

## Heartbeat

App gửi `{"type":"ping","sent_at":"ISO8601"}` mỗi giây. Pi trả `{"type":"pong"}`. Sau hơn 5 giây không có pong, app coi là mất kết nối; retry 1, 2, 4, 8, 16, tối đa 30 giây. Pi demo đóng WS khi không nhận ping hơn 6 giây, đồng thời có watchdog TTL riêng. Cảnh báo cục bộ của Pi thật phải độc lập vòng lặp mạng này.

## Telemetry / hazard

```json
{"type":"device_status","demo":false,"yolo_fps":18.4,"cpu_temp":62,"battery_percent":76,"camera_ok":true,"lidar_ok":true,"imu_ok":true}
```

Pin không đo được thì gửi null/bỏ trường; không tự mặc định 100%. App coi telemetry cũ hơn 6 giây là chưa có dữ liệu. `demo:true` phải luôn xuất hiện ở simulator.

```json
{"type":"hazard","hazard_class":"drop_off","distance_m":1.2,"severity":"stop","confidence":0.91,"message":"Dừng lại — có mép hụt phía trước."}
```

`confidence` là giá trị model, không tự nó chứng minh cảm biến đủ tin cậy. Pi phát cảnh báo trực tiếp; mobile hiển thị và rung, tránh hai thiết bị nói đè nhau. Lỗi hệ thống gửi `{"type":"system_error","message":"..."}`; không nhét token/API key vào message.

## Cấu hình

```json
{"warning_level":"normal","volume":0.8,"speech_rate":0.5,"vibration":true}
```

Các mức `low/normal/detailed` không được tắt cảnh báo khẩn. `volume` 0–1, `speech_rate` 0.2–0.8 là giá trị chuẩn hóa; Pi thật phải quy đổi theo TTS của mình. Reference server áp dụng volume/rate cho espeak-ng; không có motor rung hoặc mô hình camera thật.
