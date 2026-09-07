# Bàn giao phục hồi map và chỉ dẫn vòng xuyến

iOS **0.5.19 (35)** + Band **0.6.14 (29)**. Cần cài cả hai; IPA cần ký trước khi cài.

## Đã sửa

- Tên đường giữ một dòng, căn giữa cùng trục với khoảng cách. Không thêm câu dài trên màn hình nhỏ.
- Vòng xuyến dùng ký hiệu trung tính [Mapbox directions-icons](https://github.com/mapbox/directions-icons/tree/9016ba92176cf1a8207cc1c4005b951fe49d59cb), thêm số lối ra ở giữa. Ví dụ API thật trả “lối rẽ 2” tại Nguyễn Khuyến thì icon hiện số 2, không tự vẽ mũi tên rẽ phải. Số lối ra không đồng nghĩa góc rẽ: không mặc định lối 2 luôn là đi thẳng. Thiếu thông tin thì hiện vòng xuyến không số. Các icon khác giữ Material Icons Round.
- Sau timeout truyền/chờ hiển thị, iOS thực hiện reset có xác nhận của đúng lượt map. Band giữ ảnh đã xác nhận, chờ ghi file xong rồi giải phóng lượt cũ, bỏ callback đến muộn. Chỉ khi nhận đủ phản hồi reset và ACK, iOS mới dựng map theo GPS mới nhất; không cần Start/reconnect cho nhánh timeout này. GPS tiếp tục được xử lý trong lúc chờ, không gọi lại API map mỗi lần thử reset.
- Cửa sổ truyền navigation tăng từ 2 lên 4 chunk vốn đã được hỗ trợ. Giữ một map đang truyền, tối đa 8 KiB và giới hạn envelope hiện có. Không đổi byte giao thức Xiaomi, kích thước bản đồ, marker, màu route hay renderer.

## Bằng chứng và giới hạn

File test ngày 07/09 chỉ dài **1.025 byte**, bị cắt trước sự kiện mất hiển thị. Phần còn lại ghi `transferMs=4499 window=2` và `fixToDisplayMs=5454`; chưa đủ để kết luận sự kiện nào xảy ra lúc blur trên thiết bị. Test đã tái hiện và sửa lỗi timeout khóa mọi map tiếp theo. Đây là xác nhận nhánh lỗi trong mã, chưa phải khẳng định đã chứng minh nguyên nhân duy nhất của lần test bị cắt.

[CI trước sửa](https://github.com/LordierClaw/blueband-map/actions/runs/34079820465) có 85 test, 2 lỗi đúng kỳ vọng: khóa sau timeout và cấu hình window chưa tối ưu. Cùng payload **7.416 byte**, giả lập ACK **500 ms**, thời gian window 2 = **4,13 s**, window 4 = **2,09 s**. Đây là số đo kiểm thử; không phải cam kết độ trễ BLE thực tế hay tổng GPS → Band.

Theo [Vela background running](https://iot.mi.com/vela/quickapp/en/guide/framework/other/background-running.html), JS app có thể bị dừng khi xuống nền. Bản này phục hồi truyền map khi Band hoạt động lại; không tuyên bố Band vẫn render liên tục lúc màn hình tắt. iPhone vẫn giữ luồng GPS/Bluetooth nền hiện có. Cần thử riêng thông báo/khóa iPhone và thông báo/tắt màn Band.

## Tối ưu tiếp theo đã cân nhắc

| Phương án | Đánh giá |
| --- | --- |
| Cửa sổ 4 chunk | Đã triển khai, phép đo cho thấy giảm thời gian chờ ACK; không tăng API hay kích thước frame. |
| Preload tile gần chỗ rẽ trên iOS | Có ích nếu log đầy đủ cho thấy tải tile lạnh chiếm phần lớn thời gian. Hiện đã có cache tile/style hữu hạn; cần số đo cache/mạng trước khi thêm request dự đoán. |
| Dựng trước ảnh tại vị trí tương lai | Có thể giảm chờ nhưng dễ hiện sai vị trí/góc khi người dùng giảm tốc hoặc đổi hướng. Chỉ nên chuẩn bị trước rồi kiểm tra lại GPS trước khi dùng. Chưa đưa vào bản này. |
| Gửi tile/delta và ghép động trên Band | Phải thêm quản lý tile, góc xoay, scene và bộ nhớ; khi camera xoay thì nhiều vùng thay đổi cùng lúc. Cần benchmark phần cứng về decode/composition trước khi thay kiến trúc ảnh đơn đã hiển thị được. |

## Một lượt kiểm tra ngắn

1. Cài đúng hai phiên bản. Đi qua vòng xuyến và một chỗ rẽ; kiểm tra số trong icon, tên đường một dòng nằm giữa, map/marker rõ.
2. Trong cùng phiên, lần lượt để thông báo che Band, để Band tự tắt rồi bật lại, sau đó khóa iPhone. Không bấm Start lại. Khi Band hoạt động lại, map phải tự tiếp tục với vị trí mới.
3. Xuất **file đầy đủ**, không chỉ chép phần đầu log. Ghi rõ màn nào bị che/tắt và map có tự chạy lại hay không. Kiểm tra `map.resume.start/result`, `band.displayed`, `window=4`, `fixAgeMs` và khoảng cách giữa các frame. Mục tiêu <5 s cần được kiểm chứng bằng nhiều frame thực tế; nếu còn lỗi, giữ log của lần lỗi đầu.
