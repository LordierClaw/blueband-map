# Test full luồng tại chỗ

Cặp phiên bản: **iOS 0.5.27 (43)** + **RPK 0.6.22 (37)**.
Chỉ bàn giao artifact sau khi kiểm thử và xác minh gói của cùng commit.

## Cài và chạy một lần

1. Cài IPA bằng cách ký/sideload đang dùng; IPA bàn giao chưa ký. Cài RPK mới, mở BlueBandMap trên Band, kết nối iPhone và chờ xác thực. Kiểm tra hai phiên bản phía trên. Giữ các khóa Vietmap đã lưu và kết nối mạng.
2. Trong phần điều hướng, chọn chế độ bản đồ **auto**, bấm **Chạy test full luồng (~5 phút)**. Giữ iPhone mở ở màn hình điều hướng và Band mở app trong lượt này. Không cần di chuyển thật, nhập điểm đến, tự rẽ, bấm zoom hay đánh dấu từng đoạn. Không cần Developer Mode để tạo GPS.
3. Đợi app tự dừng rồi chọn **Tệp/Files → Lưu** trong hộp thoại xuất kết quả. Nếu đóng hộp thoại, bấm **Lưu kết quả test (.jsonl)**. Gửi file JSONL vừa lưu cùng ghi chú Band có lag, thoát app hay hiện logo khởi động lại hay không.

Không chạy lại chỉ để lấy PASS. Một lượt chậm hoặc lỗi vẫn có giá trị phân tích. Lưu kết quả trước khi chạy bài khác; recorder giữ tối đa ba phiên gần nhất.

## Bài tự chạy những gì

Sau kiểm tra phiên bản/chẩn đoán, app dùng tuyến giả lập cố định và phát tọa độ 1 Hz. Tọa độ và tuyến là dữ liệu tổng hợp; tải dữ liệu bản đồ Vietmap, dựng ảnh, truyền Bluetooth, giải mã/hiển thị trên Band và phản hồi đều đi qua luồng thật. Bài này không gọi dịch vụ tìm tuyến cho tuyến giả lập, không xác nhận GPS thật hay khả năng khóa iPhone. Điểm đến điều hướng thường ngày không bị ghi đè.

| Thời gian từ lúc bắt đầu tuyến | Hoạt động tự động |
| --- | --- |
| 0–30 giây | Di chuyển ngắn, cho cache hình thành |
| 30–90 giây | Di chuyển sang vùng bản đồ mới |
| 90–150 giây | Tiếp tục tuyến qua các đoạn đổi hướng |
| 150–190 giây | Đổi zoom từ 17 xuống 16 |
| 190–280 giây | Trở lại zoom 17, tiếp tục di chuyển/rẽ đến cuối tuyến |
| 280–290 giây | Dừng các nguồn phát ảnh/vị trí, đo callback tồn đọng |
| Sau 290 giây | Lấy chẩn đoán cuối tối đa 8 giây, tự Stop và xuất log |

Các mốc là lịch phát; đổi hướng/vùng thành công chỉ được tính khi có phản hồi tương ứng. Không coi marker phase hay nhịp phát 1 Hz là bằng chứng update <1 giây. Thời gian đầu kiểm tra RPK/tải ảnh có thể làm tổng lượt lâu hơn 5 phút.

## Dừng và xử lý lỗi

Nút **Dừng** trên thanh công cụ iPhone vẫn dùng được trong toàn bộ lượt, kể cả đang chờ bản đồ hoặc chẩn đoán. Dừng không chờ BLE. Ảnh cuối còn trên Band không có nghĩa iPhone vẫn gửi: xem trạng thái đã dừng và kết quả xuất log.

App lấy chẩn đoán mỗi 10 giây với deadline 8 giây, chỉ một nhóm yêu cầu đang chờ. Sai RPK, mất kết nối, lỗi gửi hướng dẫn hoặc Band không phản hồi sẽ kết thúc và chuẩn bị log với lý do riêng. Khi iPhone còn chạy, phát hiện im lặng có thể mất khoảng 18 giây. Giới hạn cứng nguồn replay là 600 giây; không phát bù dồn dập các vị trí cũ sau một lần treo/ngủ.

Nếu Band hiện logo và reboot: giữ iPhone mở để lưu kết quả; không cần mở lại app Band hay chạy thêm. Nếu hộp thoại chưa xuất hiện, bấm **Dừng**, rồi **Lưu kết quả test (.jsonl)**. Phân biệt reboot có logo với chỉ thoát về mặt đồng hồ.

## Cách đọc kết quả

Trace có profile `full-flow-v1`, các phase, fix phát/được xác nhận, thời gian tải style/tile/decode/draw/encode/transfer, lỗi provider đã lược thông tin nhạy cảm, và số hình học bị loại/số phép chiếu được tái sử dụng. Chẩn đoán Band có bộ đếm callback ACK/message riêng và tối đa 16 mẫu timestamp đang chờ. Đây không phải phép đo RAM native; không kết luận OOM từ số pending.

Mục tiêu vẫn là Start→xác nhận và GPS→xác nhận đều <1000 ms, gồm cả rẽ/đổi vùng. Start có tính cả kiểm tra RPK trước replay và có event riêng để tách thời gian. Xác nhận giao thức không thay thế thời điểm pixel thật hiện trên Band. Nếu có video bằng thiết bị khác, gửi kèm FPS; video hữu ích nhưng không bắt buộc để xuất và phân tích JSONL. Chưa có kết luận phần cứng đạt <1 giây hay hết reboot.
