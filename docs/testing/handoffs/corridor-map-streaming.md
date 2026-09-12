# Bàn giao map dịch chuyển theo GPS

Cài theo cặp: **iOS 0.5.21 (37)** và **Band 0.6.16 (31)**. IPA unsigned cần ký trước khi cài. Source ứng dụng: `6db094b86f6862ecd811699b4cb7bd2cfcc858a2`. File trong `artifacts/handoff` và `SHA256SUMS` xác định đúng cặp build.

## Thay đổi

- Vòng xuyến trong tuyến mặc định của `blueband-map-route-test/fake_gps_route.py`: sửa nhận diện cung/đường thoát nằm bên trong interval Vietmap. Hướng đi thẳng đi xuyên parser → preview → cập nhật live thành icon vòng xuyến đi thẳng, không suy hướng từ số lối ra. Geometry không đủ tin cậy vẫn dùng icon trung tính.
- Sau ảnh khởi tạo, GPS gửi độ dịch chuyển nhỏ để Band dịch nền map dưới cursor cố định. Chỉ gửi mảnh PNG 128×128 bị thiếu; tải trước một dải phía trước theo hướng route, không tải toàn bộ vùng xung quanh.
- Route đã đi vẫn đổi màu: iPhone chỉ dựng lại những mảnh giao với đoạn vừa di chuyển. Hash giống nhau không gửi lại. Band giữ phiên bản cũ đến khi ảnh thay thế giải mã xong; marker đích đổi đồng thời với vị trí map.
- Band giữ tối đa 30 file mảnh, tối đa 24 image node hiển thị/chờ. Mỗi mảnh ≤8 KiB, chunk 216 byte, window 4. File đang ghi/xoá có tối đa một ô phụ; lỗi xoá chặn nhận thêm dữ liệu. iPhone cache hai atlas nền và tối đa 16 MVT/24 MiB, tối đa bốn HTTP request đồng thời.
- Đổi route/zoom/hướng camera lớn hoặc thiếu vùng không thể đáp ứng: giữ map đang thấy trong lúc chuẩn bị ảnh mới. Callback cũ không được thay scene mới. Band chưa hỗ trợ giao thức mới tự dùng đường ảnh toàn màn cũ.
- Không đổi bố cục HUD, tên đường ngắn một dòng/căn giữa, hình cursor hay byte Xiaomi. Luồng CPU, GPS navigation background và Bluetooth background vẫn dùng khi iPhone khoá.

## Kiểm chứng

- Linux: `make test`, `make lint`, `git diff --check`; 193 test Swift, 48 test Band, 19 test lab; thêm metadata/quyền nền, cú pháp iOS, GPS runtime, provider-script và handoff checks.
- CI iOS của phần tích hợp: [95 test + arm64 đạt](https://github.com/LordierClaw/blueband-map/actions/runs/34676221943). Test trước sửa đã tái hiện việc GPS vẫn tạo ba ảnh toàn màn thay vì một; sau sửa test background/cached movement đạt.
- CI bản cuối: [iOS 0.5.21](https://github.com/LordierClaw/blueband-map/actions/runs/34677326119): **95 test, 0 lỗi**, build/kiểm tra arm64 và xuất IPA đạt. Test tích hợp xác nhận di chuyển khi iOS vào nền không render lại toàn màn, chỉ dựng phần route đổi và lề mới; thay camera lớn mở scene/epoch mới. Đây là test tự động, không phải đo BLE trên Band thật.
- [Band CI](https://github.com/LordierClaw/blueband-map/actions/runs/34677326095), [Swift CI](https://github.com/LordierClaw/blueband-map/actions/runs/34677326082), [Repository CI](https://github.com/LordierClaw/blueband-map/actions/runs/34677326077) đạt. RPK tải từ CI: đúng version/code, 33 PNG khớp source, entry không có module helper gây lỗi firmware. Đã xem ảnh mosaic native 212×520 từ CI ở 0/45/90/180/270°, đối chiếu nền/route; không coi ảnh simulator là kiểm tra giải mã Vela.
- IPA tải về đã kiểm tra checksum gốc CI, Mach-O arm64, version/build, quyền Bluetooth/vị trí chính xác và `UIBackgroundModes=location,bluetooth-central`; không có provisioning profile hay chữ ký riêng. SHA-256 IPA: `cf76adecc932e1e361eb00c506e117c90b7f04b52832fbb220a50070ee353c6d`; RPK: `769cff4807b4a9fc7a03528aad4c7867ac155d364caae717193eb448bf5c7ca5`.
- Replay Band 600 bước: đủ coverage, không vượt giới hạn file/node. Đã kiểm tra timeout, sai hash/kích thước, callback cũ, đổi nội dung, mất kết nối, cleanup thất bại và giữ map khi phục hồi.

Đây chưa phải chứng minh thiết bị đạt 1 giây. Cache nóng không cần chờ gửi lại ảnh toàn màn; thời gian GPS/BLE/giải mã và RAM thật vẫn phải đo. Khóa iPhone khác với Band ngủ: nếu firmware Band tạm ngừng JS khi tắt màn thì app không thể cam kết vẽ trong lúc ngủ; cần xác nhận phục hồi vị trí mới khi bật lại. Phiên GPS đã khởi động dùng background activity và không tự pause: Apple hỗ trợ app có quyền When In Use nhận cập nhật qua [CLBackgroundActivitySession](https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession-4nl4y). Force-quit ứng dụng không nằm trong cam kết.

## Một lượt test thiết bị

1. Xác nhận đúng hai phiên bản trên. Bắt đầu điều hướng khi iPhone mở; cho quyền vị trí và bật vị trí chính xác. Chạy tuyến fixture hiện có, không gọi Route API liên tục.
2. Đi qua vòng xuyến Nguyễn Khuyến trên tuyến: phải hiện hướng đi thẳng. Khi chạy trên đoạn thẳng, map dịch dưới cursor, phần đường đã đi đổi màu, đích không trôi lệch. Tên đường vẫn gọn và căn giữa.
3. Khóa iPhone trong lúc đang di chuyển; thử thông báo/tắt màn Band rồi bật lại. Không bấm Start lại. Thử Stop rồi bắt đầu tuyến khác để kiểm tra scene cũ không quay lại.
4. Xuất log bản 0.5.21: xem `map.stream.open`, `map.stream.displayed fixAgeMs/frameGapMs`, `map.cell.ready`, `map.stream.fallback`, `band.displayed`. Mục tiêu cache nóng gần 1 giây; kiểm tra nhiều mẫu, không lấy một mẫu đẹp làm kết luận. Tách cold start/đổi camera khỏi cập nhật cache nóng. Đối chiếu cả việc thiếu khung hoặc gián đoạn khi blur.

Nếu lỗi, gửi log đầy đủ và một video ngắn có màn Band; không cần lặp lại nhiều chuyến trước khi đối chiếu chính xác `epoch/seq` và bản build.
