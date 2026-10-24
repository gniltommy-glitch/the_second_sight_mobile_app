# Aurelia 1.2.3 — giọng nói và kiểm tra hỗ trợ

## Không tự hỏi lại

Khi mở app lần đầu, Aurelia chào và hỏi điểm đến đúng một lần. Không hỏi lại khi im lặng, không nghe rõ, hết giờ nghe hoặc quay lại từ nền. Lời mời tiếp theo chỉ phát sau khi người dùng gọi “Hey Aurelia”, bấm mic, chạm đúp hoặc bấm nút kính/tai nghe. Câu xác nhận điểm đến/âm thanh chỉ hỏi một lần mỗi lượt; câu trả lời không rõ không bắt đầu hành trình.

Chữ nhận dạng tạm thời được giữ trong phiên. Khi mic kết thúc, app chờ tối đa 2,5 giây cho kết quả cuối, rồi xử lý chữ đã nhận đúng một lần, điền vào ô điểm đến và chạy tìm kiếm/xác nhận. Android bỏ banner chờ câu gọi. Bộ nhận dạng cục bộ Vosk giữ một luồng micro liên tục để chờ “Hey Aurelia”, không mở lại Android SpeechRecognizer theo chu kỳ và không thay đổi âm lượng hệ thống. Chỉ dẫn rẽ khi chuyển bước và cảnh báo nguy hiểm vẫn hoạt động.

## Nói lệnh khi đang đi

Nút mic ở thanh trên cùng có ở mọi trang, kể cả đang dẫn đường, lệch tuyến và tạm dừng. Chạm đúp màn hình cũng mở một phiên nghe ngắn. Khi mở mic, điện thoại dừng câu đọc đang phát và tạm ngừng đọc chỉ dẫn cho tới khi kết thúc nghe.

- “Nhắc lại”: đọc chỉ dẫn hiện tại kèm khoảng cách. Nếu GPS không đạt hoặc đang lệch tuyến, đọc tình trạng thay vì lệnh rẽ không còn đáng tin.
- “Dừng dẫn đường”: kết thúc cả khi đang lệch tuyến.
- “Còn bao xa?”: đọc khoảng cách còn lại theo tuyến đã tính. Khi lệch tuyến, con số vẫn dựa trên tuyến hiện có, không phải khoảng cách trực tiếp tới đích.
- Chọn điểm đến mới trong một hành trình: app yêu cầu dừng trước; không tự kết thúc hành trình vì nhận nhầm lời nói thành tên địa điểm.

Android nhận nút tai nghe `HEADSETHOOK`, `MEDIA_PLAY_PAUSE` hoặc `VOICE_ASSIST` nếu hệ điều hành chuyển sự kiện tới cửa sổ app. Không chiếm nút âm lượng. Firmware kính có thể gửi `{"type":"voice_button"}` qua WebSocket đã xác thực. Đây là hợp đồng tích hợp; chưa có driver nút kính hay xác minh từng mẫu tai nghe/Bluetooth. Nút của nhiều tai nghe có thể do hệ điều hành xử lý thay vì chuyển tới app.

## “Hey Aurelia” khi dẫn đường, kể cả khóa màn hình

**Cài đặt → Gọi Aurelia trong hành trình** mặc định bật. Khi trạng thái là đang dẫn đường hoặc lệch tuyến, app tự bật chờ câu gọi. Tạm dừng, kết thúc hoặc đến nơi sẽ tắt mic nền. Ngoài hành trình không có dịch vụ mic nền.

- Trên Android nói “Hey Aurelia”: app đọc lời mời rồi mở phiên nghe lệnh.
- Nói “Hey Aurelia”, chờ lời mời, rồi nói lệnh. Bộ chờ dùng mô hình tiếng Anh; phát âm và độ nhạy cần thử trên điện thoại thật.
- Có thể nói “nhắc lại”, “dừng dẫn đường”, “còn bao xa?” hoặc hỏi vị trí sau câu gọi.
- Mic nền chỉ nhận các lệnh điều khiển hành trình; không tự chọn điểm đến mới từ lời nói nền.

**Android:** dịch vụ foreground microphone được khởi động khi bắt đầu dẫn đường, lúc app còn hiển thị. Sau đó có thể ra màn hình chính hoặc khóa máy. Hệ điều hành có thể hỏi quyền micro và thông báo; cho phép micro để sử dụng. Thông báo “Aurelia đang hỗ trợ dẫn đường” có nút **Tắt gọi Aurelia**, tắt chế độ gọi tự động mà giữ hành trình. Một partial wake lock giữ CPU hoạt động khi khóa màn hình và được giải phóng khi dịch vụ tắt; không mở khóa hoặc tự bật lại màn hình.

Trên Android, bộ chờ tên chạy bằng [Vosk](https://alphacephei.com/vosk/android) với mô hình `vosk-model-small-en-us-0.15` đi kèm APK (Apache 2.0). Chỉ chờ cụm “Hey Aurelia”; không lưu âm thanh, không cần mạng cho câu gọi, không tự tải mô hình lúc chạy. Lần đầu app sao chép mô hình từ APK vào bộ nhớ riêng. Mô hình nhỏ vẫn cần RAM và việc chờ mic liên tục tiêu thụ pin; cần đo trên thiết bị mục tiêu.

Khi nghe câu gọi hoặc bấm mic, app dừng bộ chờ rồi mở một phiên nhận dạng lệnh tiếng Việt. Phiên lệnh này vẫn dùng dịch vụ nhận dạng của điện thoại và có thể cần mạng/phát âm báo của hệ điều hành đúng lúc người dùng kích hoạt. Hết phiên quay lại chờ cục bộ, không tự hỏi lại. Lời đọc của app và cảnh báo Pi tạm ngừng bộ chờ để tránh tự kích hoạt. Ngoài hành trình bộ chờ chỉ chạy khi app hiển thị và tùy chọn ngoài hành trình bật. Đang dẫn đường/lệch tuyến mới tiếp tục nghe khi khóa màn hình.

Android yêu cầu [dịch vụ microphone khởi động lúc app đang hiển thị](https://developer.android.com/develop/background-work/services/fgs/service-types#microphone); hoàn tất quyền micro trước khi khóa máy. Chưa có điện thoại Android kết nối để nghiệm thu độ nhạy câu gọi, âm thanh, khóa màn hình và hao pin; build/kiểm thử giả lập không chứng minh các điều này.

**iOS:** bản này chưa có dịch vụ mic nền; gọi Aurelia chỉ ở trước màn hình. Tùy chọn **Gọi “Hey Aurelia” ngoài hành trình** vẫn mặc định tắt và chỉ dùng khi app hiển thị.

## GPS và lấy tuyến đi bộ

App tự yêu cầu vị trí điện thoại khi mở, không phụ thuộc kính. Yêu cầu vị trí chính xác cao ở cả lúc chờ và lúc đi; vị trí hợp lệ có sai số lớn vẫn được hiển thị cùng sai số thay vì báo “chưa có GPS”. Nếu quyền vị trí bị từ chối, dịch vụ vị trí tắt hoặc không có bản tin mới, app báo nguyên nhân.

Xem trước tuyến cần vị trí không quá 30 giây và sai số không quá 100 m; không đòi kính. Lập tuyến dùng `profile=foot`. Vị trí gần đúng được ghi rõ trên giao diện. Chỉ dẫn rẽ trong hành trình vẫn cần bản tin không quá 8 giây và sai số không quá 20 m, nhằm không xác định nhầm đoạn đường/ngã rẽ. Đây là ngưỡng của app, không phải điều kiện của GraphHopper hoặc bằng chứng điện thoại không có GPS. “Lấy tuyến đi bộ” và “Bắt đầu với kính” là hai bước khác nhau. Giọng nói lập tuyến xong mà chưa kết nối kính sẽ đọc kết quả xem trước, không thử bắt đầu rồi báo lỗi kính.

## Xác nhận điểm đến

Mỗi địa điểm được đọc tên, địa chỉ và khoảng cách ước tính từ GPS. Nếu trùng tên, app báo có nhiều nơi. “Không” chuyển sang địa điểm kế tiếp, tối đa ba lựa chọn; “có” mới tính tuyến và bắt đầu. Im lặng, câu không rõ hoặc hủy không bắt đầu hành trình. Có các nút Có/Không/Hủy để dùng khi không thể nhận dạng giọng nói. Cảnh báo Pi xen vào sẽ vô hiệu hóa câu trả lời giọng nói đang thu. Không tự hỏi lại; người dùng chủ động gọi mic hoặc chọn lại điểm đến.

## Kiểm tra trước khi bắt đầu hành trình thật

App yêu cầu tuyến đúng chế độ, kết nối kính, GPS đủ mới/chính xác, telemetry mới trong sáu giây, camera/LiDAR báo hoạt động, giọng đọc điện thoại sẵn sàng và âm lượng app khác không. Điện thoại phát câu thử, yêu cầu Pi phát câu thử qua `/audio/test`, rồi hỏi người dùng có nghe rõ **cả hai** không. Phản hồi HTTP không được xem là bằng chứng người dùng đã nghe; phải có câu trả lời hoặc nút Có. Sau xác nhận app kiểm tra lại trạng thái thiết bị/GPS.

Pi mẫu trả lỗi nếu chưa bật `SECONDSIGHT_VOICE=1` hoặc thiếu `espeak-ng`. Pi thật phải triển khai endpoint có xác thực và kiểm tra driver âm thanh thật. Thiếu API này sẽ chặn hành trình thật và hiện mã lỗi; chế độ mô phỏng nội bộ vẫn dùng được. Không có kiểm tra âm lượng phần cứng tự động: xác nhận nghe là bước nghiệm thu của người dùng.

STM32 chưa sẵn sàng được thông báo là mất hỗ trợ xác nhận hướng rẽ; không giả vờ thay bằng la bàn điện thoại. Nếu GPS, telemetry, camera, LiDAR, hướng hoặc tốc độ nhận diện suy giảm trong hành trình, app đọc phần hỗ trợ đang gián đoạn. Cảnh báo được gộp, đọc một lần cho mỗi lần phát sinh và chờ cảnh báo nguy hiểm kết thúc.

## Âm thanh app–Pi

Dùng app và Pi cùng phiên bản giao thức cập nhật:

1. Pi gửi `hazard` có `hazard_id`, `hold_ms` trước khi phát cảnh báo.
2. Điện thoại hủy TTS, đóng mic đang thu, và gửi `audio_yielded` sau khi dừng âm thanh.
3. Pi chờ xác nhận tối đa 200 ms rồi phát; hết thời gian vẫn cảnh báo để không phụ thuộc điện thoại.
4. Cảnh báo dài gửi `hazard_hold` mỗi giây để giữ điện thoại im lặng.
5. Khi phát xong Pi gửi `hazard_clear` đúng mã. Điện thoại chờ thêm 600 ms rồi tiếp tục chỉ dẫn từ vị trí mới.

Cảnh báo điện thoại cũng không được chen vào lúc Pi đang sở hữu âm thanh. TTL là dự phòng khi mất gói tin; độ trễ mạng hoặc hệ điều hành vẫn có thể gây chồng âm ngắn nếu không nhận được xác nhận. Đây là phối hợp phần mềm, cần đo trên thiết bị thật. Không khẳng định hai loa đồng bộ tuyệt đối.

## Ghép nối một lần

Người hỗ trợ chuẩn bị QR chứa JSON:

```json
{
  "type": "secondsight_pairing",
  "version": 1,
  "endpoint": "https://secondsight.local:8765",
  "token": "TOKEN_CUA_KINH",
  "routing_key": "API_KEY_GRAPHOPPER",
  "allow_insecure": false
}
```

`routing_key` có thể bỏ để giữ khóa hiện tại. HTTP LAN thử nghiệm phải có `allow_insecure:true`. App kiểm tra định dạng, hiện endpoint để người hỗ trợ xác nhận, rồi lưu token/API key bằng secure storage. QR không được ghi vào nhật ký. Cấu hình không chứa thông tin Wi-Fi; Pi và điện thoại vẫn cần cùng mạng.

Tạo QR bằng công cụ cục bộ:

```bash
python3 -m venv .venv-qr
.venv-qr/bin/pip install 'qrcode[pil]'
.venv-qr/bin/python scripts/create_pairing_qr.py \
  --endpoint https://secondsight.local:8765 --output pairing.png
```

Công cụ hỏi token/khóa bằng nhập ẩn hoặc đọc `SECONDSIGHT_TOKEN` và `GRAPHOPPER_API_KEY`. Không đưa khóa vào đối số lệnh. Ảnh QR có chứa thông tin xác thực, chỉ dùng cục bộ với người hỗ trợ. Trong app chọn **Cài đặt → Quét QR cấu hình một lần**, hoặc **Dán cấu hình từ người hỗ trợ**. Những lần sau không cần nhập lại.

## Thử trên thiết bị thật

- Mở mic trong dẫn đường và lệch tuyến, thử ba lệnh; xác minh cập nhật GPS không đóng mic.
- Bấm nút tai nghe/kính trên thiết bị mục tiêu; kiểm tra cả trường hợp OS không chuyển nút.
- Bật/tắt “Hey Aurelia”, nói câu không có tên gọi, thử khi app đọc, cảnh báo, ra nền và từ chối quyền.
- Có/không/hủy khi trùng tên; im lặng; cảnh báo xen đúng lúc nói “có”.
- Camera/LiDAR lỗi và telemetry hết hạn; xác minh chỉ đọc một lần, phát sinh lại thì đọc lại.
- Thử âm thanh điện thoại/kính, từ chối xác nhận, Pi chưa có endpoint hoặc chưa có loa; không được bắt đầu giả.
- Cảnh báo dài hơn tám giây và hai cảnh báo liên tiếp; xác nhận chỉ đọc hướng dẫn hiện tại sau khi cảnh báo hết.
- QR hợp lệ, QR sai, camera bị từ chối quyền; xác minh không mất cấu hình cũ nếu hủy.
