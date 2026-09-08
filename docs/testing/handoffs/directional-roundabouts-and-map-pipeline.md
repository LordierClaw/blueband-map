# Bàn giao icon vòng xuyến và pipeline map

Cài cả **iOS 0.5.20 (36)** và **Band 0.6.15 (30)**. IPA unsigned cần ký trước khi cài. Mã ứng dụng/artifact từ `5e948c76aeed6c8bdda6eab5e51ec131af88d421`; các commit kiểm thử/tài liệu sau đó không thay mã ứng dụng. `SHA256SUMS` đi kèm xác định cặp file.

## Thay đổi

- Vòng xuyến có geometry rõ hiện icon chuẩn với hướng đi thẳng/trái/phải; quay lại dùng icon U-turn có sẵn. Không suy hướng từ số lối ra hoặc heading=0. Tính hướng tiếp cận trước cung vòng xuyến so với hướng thoát sau cung. Geometry thiếu/không rõ giữ icon trung tính + số nếu có. Tên đường vẫn một dòng căn giữa, không thêm text dài.
- Trong lúc ảnh A chờ Band hiển thị, iPhone có thể dựng/nén ảnh B. Chỉ giữ một ô chuẩn bị kế tiếp, vẫn chỉ truyền một ảnh tại một thời điểm. GPS mới được gộp; ảnh chuẩn bị bị bỏ nếu route đổi hoặc GPS mới cho thấy camera đã quá cũ/lệch. Stop hủy ô chuẩn bị, callback cũ không khôi phục màn hình đã dừng. Timeout/reset vẫn dùng cơ chế đã có.
- Thêm `map.pipeline`: `queueMs`, `prepareMs`, `encodeMs`, `readyWaitMs`, `transferMs`, `txToDisplayMs`, `bandWriteMs`, `bandDecodeMs`, `frameGapMs`. `prepareMs` bao gồm dựng và nén; không cộng thêm `encodeMs` vào nó. `txToDisplayMs` bao gồm bắt tay/truyền/chờ kết quả hiển thị; không cộng tiếp `transferMs` vào nó. `frameGapMs=0` ở frame đầu vì chưa có frame trước.
- Giữ nguyên renderer, màu route, map 212×520, marker cố định, giới hạn 8 KiB, window 4 và byte Xiaomi. Không tăng cửa sổ BLE hoặc thêm dependency. Cache tile/tải song song hiện có được giữ nguyên.

## Bằng chứng

- `make test`, `make lint`, `git diff --check` đạt; 181 test Swift portable và 36 test Band đạt.
- [iOS CI](https://github.com/LordierClaw/blueband-map/actions/runs/34242532102): 89 test, 0 lỗi, xuất IPA. Test tái hiện trước sửa đã thất bại đúng nhánh không dựng B trong lúc chờ A; sau sửa kiểm tra overlap, bỏ camera cũ, stop và các nhánh GPS/background/timeout hiện có đều đạt.
- [CI cuối, bổ sung đổi route](https://github.com/LordierClaw/blueband-map/actions/runs/34250292153): **90 test, 0 lỗi**, build IPA thành công. Route thay thế loại ảnh chuẩn bị của route trước. Test phát từng mẫu GPS sau khi mẫu trước được xử lý, đúng cơ chế chỉ giữ GPS mới nhất; không phát dồn ba mẫu rồi nhầm rằng cả ba đã được xử lý.
- [Swift CI](https://github.com/LordierClaw/blueband-map/actions/runs/34242532045), [Band CI](https://github.com/LordierClaw/blueband-map/actions/runs/34242532195), [Repository CI](https://github.com/LordierClaw/blueband-map/actions/runs/34242532030) đạt. PNG đã xem ở kích thước native; gói cuối được kiểm tra phiên bản, quyền nền, toàn bộ PNG và license khớp source.

Không coi test/CI là chứng minh thiết bị đạt 1 giây. Overlap giảm phần chờ nối tiếp giữa các frame, không giảm trực tiếp thời gian BLE của từng ảnh. Màn Band tắt có thể dừng JS; tính năng này không tuyên bố render liên tục khi Band ngủ.

## Một lượt test thiết bị

1. Đi qua vòng xuyến đi thẳng và một lối trái/phải; kiểm tra mũi tên theo hướng tiếp cận, không theo số lối ra. So sánh `roundaboutDirection` trong các dòng `step[...]` của log. Geometry mơ hồ được phép dùng icon trung tính, không được chỉ sai hướng.
2. Khi đang di chuyển, thử thông báo/tắt màn Band rồi bật lại, sau đó khóa iPhone riêng; không bấm Start lại. Map phải phục hồi theo vị trí mới. Dừng rồi bắt đầu route khác để kiểm tra ảnh cũ không quay lại.
3. Xuất toàn bộ log bản 0.5.20. Đối chiếu `map.render.start`, `map.transfer.start`, `band.displayed fixAgeMs`, `map.pipeline` và `map.prepared.discard`. Cần nhiều frame warm/cold, không chỉ một frame tốt. Mục tiêu 1 giây phải đánh giá cả tuổi GPS lúc hiển thị và khoảng cách giữa các frame.

Preload tile dự đoán chỉ thêm khi số đo chỉ ra tải tile lạnh chiếm đáng kể độ trễ; chưa bật thêm API dự đoán. Dịch/ghép ảnh động trên Band vẫn là thử nghiệm kiến trúc riêng nếu BLE ảnh đơn không đạt ngân sách, không đưa vào bản này để tránh thay UI đã ổn khi chưa có phép đo thiết bị.
