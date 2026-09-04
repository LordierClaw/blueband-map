# Bàn giao sửa phục hồi truyền map

Ngày: 2026-09-04. iOS **0.5.16 (32)** + RPK **0.6.12 (27)**. Cần cập nhật cả hai.

## Nguyên nhân và giới hạn

Log 0.5.15 vẫn timeout tại ACK 3/18 dù đã gửi tuần tự. Chưa có mã lỗi native trong log để khẳng định nguyên nhân trực tiếp trên thiết bị.

Đã tái hiện lỗi RPK xoá trạng thái map khi native send timeout 204, khiến retry không thể tiếp tục; bản này giữ lại chunk và cơ chế ACK lệnh trùng. Disconnect thật vẫn dọn phiên. Đồng thời chặn iPhone render/tải snapshot mới khi phiên truyền đã yêu cầu reconnect. Giữ nguyên UI, map/route/marker, giới hạn 8 KiB, renderer, GPS policy và Xiaomi wire bytes.

Thêm chẩn đoán tự động đúng một lần khi truyền lỗi: `peer=rpk27/chunk/off480/got960/err204` lần lượt là RPK build, giai đoạn nhận cuối, offset cuối, số byte đã nhận liên tục và mã send lỗi gần nhất. Đây là ví dụ, không phải số đo thiết bị. `peer=unavailable` nghĩa là không thu được phản hồi, không phải Band không nhận chunk. Xem [ADR 0016](../../adr/0016-preserve-map-state-on-native-send-timeout.md).

## Kiểm tra tự động

- Test lỗi native timeout đã đỏ trước sửa. Replay 100 ảnh 8 KiB có callback bất đồng bộ, mất ACK/error 204 và gửi lại cùng lệnh; kiểm tra byte/hash, publish, marker và giới hạn file.
- iOS test đã đỏ trước sửa với 2 render thay vì 1 sau lỗi terminal; test chẩn đoán cũng đỏ trước khi bổ sung.
- `make test`: portable Swift 174, RPK 33 (gồm build/kiểm tra archive), protocol-lab 19, location-runtime 15; metadata/provider-script/handoff checks đạt. `make lint`, secret scan và `git diff --check` đạt. Provider-script tests dùng fake curl, không phải API thật.
- RPK dependencies vẫn có 14 audit warnings (3 low, 11 high) như bản trước; không tự đổi toolchain/dependencies trong bản sửa này.
- Các test native/file/decoder dùng mô phỏng. Không thay thế iPhone + Band, không chứng minh độ trễ <5 giây khi khoá màn hình.

## Một lượt kiểm tra thiết bị, dừng ở lỗi đầu

1. Ký/cài IPA unsigned và cài RPK mới trong `artifacts/handoff`; đối chiếu version và `SHA256SUMS`. Cấp Bluetooth, vị trí và Precise Location khi được hỏi. Kết nối sạch, mở RPK, bắt đầu một tuyến ngắn. Map đầu phải có route/marker và log `band.displayed`.
2. Nếu map không lên: **không Start lặp lại**. Đợi khoảng 5 giây để phép hỏi chẩn đoán hữu hạn kết thúc, export log, ghi màn hình Band (LOADING MAP / ĐANG CHỜ KẾT NỐI / app thoát), firmware và phiên bản iOS. Không gửi key/raw capture. Dừng bài tại đây.
3. Chỉ khi map đầu đạt: đi bộ an toàn hoặc replay cùng tuyến, khoá iPhone 5 phút, ít nhất 10 refresh. Cần `fixToDisplayMs` hữu hạn <5000, không `BAND_DISPLAY_FAILED`/`MAP_PAYLOAD_TOO_LARGE`. `violations=0` khi chưa display không tính là đạt. Sau đó thử ngắt/kết nối lại một lần; Stop phải dừng GPS navigation.

Giới hạn bài test: tối đa 2 Route requests, không cố tình reroute; theo dõi và dừng ở 200 style/tile requests nếu có bộ đếm provider. Đây là ngân sách bài test, không phải hard cap HTTP của app. Không đo được thì báo `NEEDS-MEASURE`. Không thao tác khi lái xe.

## Bằng chứng bàn giao

- Commit nguồn IPA/RPK: `2f6f72ae254d26ab0e6489b5e433a4c2736c95b8` trên `main`; commit sau chỉ cập nhật bằng chứng bàn giao.
- [iOS CI](https://github.com/LordierClaw/blueband-map/actions/runs/33828764075): success, **79/79 XCTest**, build unsigned arm64 và kiểm tra metadata đạt. Hai test từng đỏ tại [CI trước sửa](https://github.com/LordierClaw/blueband-map/actions/runs/33827826566) nay đạt; có thêm kiểm tra số không hợp lệ, phản hồi sau disconnect và diagnostic nằm trong phần đầu export.
- [Band CI](https://github.com/LordierClaw/blueband-map/actions/runs/33828764150) và [Repository CI](https://github.com/LordierClaw/blueband-map/actions/runs/33828764255): success. Entry JS của RPK tải từ CI khớp byte với bản build/test cục bộ; ảnh marker/mũi tên/HUD giữ nguyên byte so với RPK 0.6.11.
- `BlueBandMap-unsigned.ipa`: **3,560,952 bytes**, SHA-256 `be0e128d84999d3036bc26a130a7ae21f0209c62ccf1235430f11f7532bdb242`; hash tải về khớp hash CI.
- `dev.lordierclaw.bluebandmap.band.debug.0.6.12.rpk`: **32,936 bytes**, SHA-256 `bcbea2837efe122b737b81b4ddb11325d1919bee3147d22be5ca531a7fb974b8`.
- IPA tải về đã kiểm tra ZIP, Mach-O arm64, bundle ID, iOS minimum 17.0, version/build, iPhone-only, không có chữ ký/provisioning profile. Có `UIBackgroundModes=location,bluetooth-central`, mô tả quyền Bluetooth/location và xin precise location tạm thời. Metadata không chứng minh người dùng đã cấp quyền hoặc iOS cho phép chạy lúc khoá màn hình trong điều kiện thực tế.

Chưa nghiệm thu phần cứng: `lsusb` không có iPhone; `idevice_id -l` không truy cập được thiết bị. Không có bản realtime known-good đã được chứng minh để hứa rollback. Thư mục handoff chỉ giữ cặp mới; IPA 0.5.15 có thể lấy lại từ [CI cũ](https://github.com/LordierClaw/blueband-map/actions/runs/33787726371) nếu còn thời hạn lưu trữ, còn RPK 0.6.11 có thể build lại từ nguồn commit `5bc2f7a` (không cam kết cùng checksum archive).
