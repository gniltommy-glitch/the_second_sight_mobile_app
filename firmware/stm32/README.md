# STM32F411E-DISCO · firmware integration

`mahony.c` là lõi fusion C độc lập, không phải image firmware đã nạp bo. Dự án gốc là app Flutter và Pi simulator, chưa có STM32CubeIDE/HAL project. Tạo project cho đúng revision bo rồi tích hợp như sau:

1. Dùng [BSP STM32F411E-Discovery chính thức](https://github.com/STMicroelectronics/32f411ediscovery-bsp). Khởi tạo accelerometer/gyro với `BSP_ACCELERO_Init` và `BSP_GYRO_Init`; đọc `BSP_ACCELERO_GetXYZ` và `BSP_GYRO_GetXYZ`. Đọc magnetometer qua driver LSM303DLHC/LSM303AGR tương ứng revision bo. Gyro có thể là L3GD20 hoặc I3G4250D. Kiểm tra WHO_AM_I và data-ready, không giả định mọi bo cùng IC.
2. Tại 100 Hz, trừ bias gyro, đổi đơn vị gyro sang rad/s, hiệu chỉnh offset/scale accelerometer, hard/soft iron magnetometer. Đưa cả ba cảm biến về cùng hệ trục x trước, y phải, z xuống; đầu vào `a` là hướng trọng lực (đảo dấu specific force nếu driver trả về specific force). Tích hợp dt đo bằng timer, không dùng hằng số nếu vòng lặp có jitter.
3. Gọi `mahony_init` một lần, rồi `mahony_update(&filter, gyro, gravity, magnetic, dt)`. Mẫu lỗi, bão hòa, mất data-ready hoặc từ trường bất thường phải đặt calibration validity false; mất sensor thì không gửi một quaternion cũ với sequence mới.
4. Sau khi bias/calibration/mounting hợp lệ và filter hội tụ, gọi `imu_packet(..., calibrated, yaw_offset_degrees)` ở 20 Hz. Offset bao gồm declination để heading tham chiếu Bắc thật giống GPS và hiệu chỉnh hướng lắp bo. `calibrated` không được đặt true cố định.
5. Gửi buffer hoàn chỉnh qua HAL UART (115200, 8N1, logic 3.3 V, chung GND) hoặc USB OTG CDC. USB ST-LINK là cổng debug; không mặc định coi đó là USB CDC dữ liệu của firmware. Bật hỗ trợ printf float nếu toolchain dùng newlib-nano. Với USB CDC busy hoặc UART DMA, giữ buffer đến khi truyền hoàn tất và không chặn lấy mẫu IMU.
6. Trên Pi: `SECONDSIGHT_IMU_PORT=/dev/serial/by-id/<thiết-bị>` hoặc `/dev/serial0`, chạy server tham chiếu. UART cần cấu hình hệ điều hành và tắt serial console nếu trùng cổng. Phát hiện reset bo cần mở lại cổng receiver để reset sequence/timestamp baseline.

Packet JSON mỗi dòng: version 1, sequence tăng dần, timestamp_ms uptime bo, calibrated boolean, quaternion [w,x,y,z] đã bù yaw offset, heading/pitch/roll độ. Pi tự tính lại Euler từ quaternion thay vì tin các giá trị Euler rời rạc. Không đồng nhất uptime bo với UTC điện thoại.

Cần kiểm thử hardware: hiệu chuẩn, trục và dấu tại 0/90/180/270°, nghiêng bo, nhiễu từ Pi/pin, ngắt cáp, reset bo và tuổi dữ liệu. Chưa có cấu hình chân UART, Cube project hoặc thử nghiệm trên bo thật trong gói này.
