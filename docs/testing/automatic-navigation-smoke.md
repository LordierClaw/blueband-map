# Test tự động tại chỗ

Cặp phiên bản: **iOS 0.5.26 (42)** + **RPK 0.6.21 (36)**.
Chỉ bàn giao artifact sau khi CI của bản tương ứng đã kiểm thử và xác minh gói.

Bài này thay GPS thật bằng tọa độ phát trong app, còn lấy tuyến, dựng bản đồ,
truyền Bluetooth và xác nhận từ Band dùng luồng thật. Không cần di chuyển ngoài
đường, máy tính phát GPS hay Developer Mode chỉ để tạo tọa độ. Không dùng bài
này để xác nhận Core Location khi khóa iPhone hoặc kết luận Band không crash.

## Một lần chạy

1. Cài đúng cặp IPA/RPK bàn giao, kết nối và chờ xác thực. Mở app trên Band.
   Giữ iPhone và Band mở trong bài đầu. Các khóa bản đồ đã lưu vẫn được dùng.
2. Bấm **Chạy test tự động**. App kiểm tra phiên bản và chẩn đoán Band trước,
   rồi phát tuyến mẫu cố định với tốc độ 10 m/s và nhịp 1 Hz. Điểm đến điều hướng
   hằng ngày không bị ghi đè. Theo dõi trạng thái; không cần tự đánh dấu đoạn.
3. Khi bài kết thúc hoặc lỗi, màn hình lưu file tự mở: chọn thư mục trong
   **Tệp/Files → Lưu**. Nếu đóng hộp thoại, bấm **Lưu kết quả test (.jsonl)**.
   Gửi JSONL này cùng ghi chú
   nhìn thấy trên Band. Nếu quay video, dùng thiết bị khác và ghi FPS.

Nút **Dừng** trên thanh công cụ luôn sẵn khi đang chạy. Dừng trên iPhone không
chờ BLE. Ảnh cuối trên Band có thể còn nguyên; dòng trạng thái iPhone và các
event Stop/end xác định phiên có thực sự dừng hay không. Không coi ảnh đứng
yên sau Stop là bằng chứng ứng dụng còn gửi bản đồ.

## Kết quả và giới hạn

- Sai/thiếu phiên bản RPK: app kết thúc với lý do cụ thể và giữ log; không bắt
  người dùng chạy dài mới tìm ra cặp cài không khớp.
- Khi đang phát tuyến, app lấy chẩn đoán mỗi 10 giây, mỗi lần có deadline 8 giây;
  chỉ cho phép một cặp yêu cầu đang chờ. Việc lấy chẩn đoán vẫn chạy khi chờ tuyến
  hoặc dựng bản đồ. Đây là nhịp đo sức khỏe, không phải nhịp cập nhật bản đồ.
- Mất kết nối, gửi cập nhật điều hướng thất bại hoặc hết hạn chẩn đoán đang chạy:
  dừng tại iPhone và chuẩn bị export với lý do riêng, không chờ lấy chẩn đoán cuối.
  Nếu chưa có sự kiện mất kết nối/lỗi gửi, phát hiện im lặng có thể mất khoảng
  18 giây (10 giây tới mẫu tiếp theo + 8 giây chờ), khi iPhone còn hoạt động.
- Hết tuyến, lỗi, hoặc giới hạn 600 giây phát: tự kết thúc; không phát bù một loạt
  tọa độ cũ sau khi app bị treo/ngủ. Timestamp phát thực tế được lưu riêng.
- Cuối tuyến chờ tối đa 3 giây cho lệnh tới đích, rồi tối đa 8 giây lấy chẩn đoán.
  Nút Dừng vẫn dùng được trong thời gian này. ACK chỉ xác nhận nhận lệnh;
  log không coi ACK là bằng chứng Band đã vẽ chữ ARRIVED.
- Không chạy ca tiếp theo trước khi lưu kết quả; recorder vẫn giữ tối đa 3 phiên.
- Một bài chậm/lỗi vẫn là dữ liệu hữu ích. Không cần chạy lại chỉ để có PASS.
- Nếu Band hiện logo rồi khởi động lại: giữ iPhone mở và lưu JSONL được chuẩn bị.
  Không cần mở lại app Band hoặc chạy lượt thứ hai. Ghi rõ có logo khởi động,
  khác với trường hợp chỉ thoát về mặt đồng hồ. Nếu hộp thoại chưa hiện, bấm
  Dừng trên iPhone rồi Lưu kết quả test (.jsonl).
- Ngủ/thoát Band hoặc khóa/mở iPhone thật là các ca riêng. Không đánh dấu chúng
  đã thử chỉ bằng cách gọi hàm hay thay đổi GPS mô phỏng.

Start→xác nhận và GPS→xác nhận được chấm riêng, đều có mục tiêu <1000 ms. Thời gian
kiểm tra RPK đầu lượt vẫn nằm trong Start→xác nhận và có event riêng để phân tích.
Việc phát đúng 1 Hz không chứng minh khung cập nhật trong 1 giây. Video vẫn cần để xác
nhận thời điểm pixel thật trên màn Band; ACK không thay thế quan sát màn hình.

App tự gắn phase theo fix: rẽ dựa trên đổi hướng; đổi vùng/cached dựa trên ô còn
thiếu trong yêu cầu viewport. Chỉ có marker không được tính là đã test thành
công: phải có xác nhận tương ứng. Một lượt không nhận được xác nhận rẽ/đổi vùng
sẽ còn thiếu bằng chứng; app không tự ghi PASS.
