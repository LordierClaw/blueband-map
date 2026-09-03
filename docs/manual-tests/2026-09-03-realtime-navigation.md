# Manual test — GPS realtime và dẫn đường khi khóa iPhone

Bản kiểm tra: **IPA 0.5.11 (27)** + **RPK 0.6.11 (26)**. RPK không thay đổi; nếu đã cài đúng 0.6.11 thì chỉ cần cập nhật IPA. IPA unsigned cần được ký theo quy trình sideload đang dùng.

## Quyền và chuẩn bị

1. Mở IPA, kết nối Band, nhập/chọn các key đang sử dụng và chọn điểm đến.
2. Trong Settings → Privacy & Security → Location Services → BlueBandMap: cho phép **While Using the App**, bật **Precise Location**. Cấp Bluetooth khi được hỏi. App có thể xin vị trí chính xác tạm thời khi bắt đầu điều hướng nếu Precise đang tắt.
3. Bấm bắt đầu dẫn đường khi IPA còn ở foreground; chờ GPS tốt và map đầu tiên đã xuất hiện rồi khóa máy. Kiểm tra thêm một lần khóa ngay khi app đang render map đầu tiên.
4. Không force-quit app trong bài đo khóa màn hình. Phiên dẫn đường chủ động dùng background location + Bluetooth và chỉ báo vị trí theo [cơ chế Apple](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background). Always không phải điều kiện bắt buộc để tiếp tục phiên này; force-quit/relaunch là trường hợp khác.
5. Dùng tuyến có rẽ trái, phải, đoạn cong, qua ranh giới tile và một đoạn cho phép thử đi lệch tuyến. Người quan sát nên là hành khách; có thể dùng bộ giả lập GPS đã chuẩn bị trước đó.

## Các ca bắt buộc

| Ca | Thao tác | Tiêu chí đạt |
|---|---|---|
| Hồi quy UI | Dẫn đường foreground 2 phút | Map/route/marker và box chỉ dẫn giữ kiểu hiển thị đã được chấp nhận; cursor cố định `(106,374)`; không có marker méo/lệch. |
| Khóa màn hình | Khóa iPhone và tiếp tục di chuyển ít nhất 10 phút | Map, hướng, bước rẽ và khoảng cách tiếp tục đổi trên Band; không đen/loading xen giữa các frame. |
| Chuyển trạng thái | Khóa/mở ít nhất 5 lần, gồm lúc đang render và đang truyền map | Giữ frame đã xác nhận; frame mới hoàn tất sau chuyển trạng thái. Khóa ngay sau fix cuối rồi đứng yên cũng phải nhận map. |
| Hướng và hình học | Rẽ trái/phải, quay đầu tại nơi phù hợp, đi qua đường cong và giao lộ | Map xoay theo hướng; route và destination không drift so với map. Khi khóa, kiểm tra chữ Việt, đường sắt/nét đứt và vùng nước/công trình. |
| Đổi tile | Đi đủ xa để rời viewport cũ | Map mới tải được; không mất một mảng ở ranh giới tile, không có `MAP_PAYLOAD_TOO_LARGE` hoặc `BAND_DISPLAY_FAILED`. |
| Reroute | Đi lệch tuyến có chủ đích | GPS/chỉ dẫn tiếp tục hoạt động trong lúc gọi route API; route mới thay thế route cũ sau khi thành công. |
| GPS xấu | Mô phỏng sai số lớn hoặc vào nơi GPS yếu rồi trở lại | Trạng thái GPS yếu rõ ràng, không nhảy theo fix sai; tự phục hồi khi fix tốt trở lại. |
| Mạng lỗi | Tắt dữ liệu mạng ngắn rồi bật lại khi đang di chuyển | Giữ map cuối; không spam retry mỗi fix; tile đã tải được tiếp tục tái sử dụng; tự cập nhật lại khi có mạng. |
| Dừng/khởi động lại | Stop rồi Start nhanh, lặp lại 3 lần | Phiên mới vẫn nhận GPS; callback phiên cũ không dừng phiên mới. |
| Quyền bị từ chối | Từ chối vị trí hoặc tắt Precise rồi thử lại | IPA hiển thị đúng vấn đề và đường vào Settings; không chờ GPS vô hạn dưới trạng thái đang dẫn đường bình thường. |
| Kết thúc | Stop hoặc tới đích | Không có frame mới phát sinh từ phiên cũ; background location/Bluetooth activity được giải phóng theo vòng đời điều hướng. |

## Đo ngưỡng dưới 5 giây

- Chỉ bắt đầu bài đo ổn định khi GPS chính xác, mạng và BLE tốt. Tách thời gian lấy GPS đầu tiên và route API ban đầu khỏi nhịp cập nhật khi đang di chuyển, nhưng vẫn ghi nhận chúng.
- Trong debug export, kiểm tra **`band.displayed ... fixAgeMs=`**. Đây là tuổi của fix gốc tại thời điểm Band xác nhận scene; không dùng riêng `snapshotMs` để kết luận độ trễ tổng.
- Với ít nhất 20 frame liên tiếp ở foreground và 20 frame khi khóa: từng `fixAgeMs` phải **< 5000**, và khoảng cách giữa hai `band.displayed` khi vẫn di chuyển cũng phải **< 5000 ms**. Không có frame mới cũng là lỗi, dù bộ đếm latency chưa tăng.
- So sánh `gps.health`/`guidance.fix`, `map.render.start`, `map.rendered`, `map.transfer.start`, `band.displayed` để xác định phần bị chậm. Kiểm tra header `location`, `app`, `mapFreshness.displayedFixAgeMs` và `mapLatency.violations`.
- Export ngay sau ca lỗi vì nhật ký chỉ giữ vòng sự kiện gần nhất. Gửi log kèm video Band và mô tả iPhone đang khóa/mở, tốc độ di chuyển, tình trạng mạng/GPS. Không gửi AuthKey, key Vietmap hay credential Apple.

## Ranh giới kiểm chứng

Test tự động và IPA build không xác nhận hành vi iPhone/Smart Band 10 thật. Chỉ đánh dấu đạt realtime khóa màn hình và `<5 s` sau khi hoàn thành các ca/đo trên. Renderer nền giữ camera, màu và route nhưng dùng font hệ thống và đặt nhãn trên đoạn đường gần thẳng; cần đối chiếu tính dễ đọc với renderer SDK foreground.
