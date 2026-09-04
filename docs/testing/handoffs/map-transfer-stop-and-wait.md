# Bàn giao kiểm chứng lỗi truyền map — iOS 0.5.15 (31)

Ngày: 2026-09-04. Trạng thái: kiểm thử tự động đạt; chưa nghiệm thu iPhone + Band.

## Điều đã xác định và giới hạn bằng chứng

Log `0.5.14 (30)` dừng tại `TRANSFER_TIMEOUT`, ACK `7/18`, `transferMs=5657`, `maxAckMs=659`, `window=2`. Route đã có và payload đã đến bước truyền. `TRANSFER_RECONNECT_REQUIRED` là refresh sau bị chặn vì phiên truyền đã timeout, không phải nguyên nhân ban đầu.

Chưa phân biệt được command bị mất, ACK bị mất hay Band không phản hồi; chưa chứng minh gửi đồng thời là nguyên nhân. Bản này chuyển mặc định sang gửi tuần tự, chờ ACK từng chunk (`window=1`) để loại bỏ việc chồng chunk. Đây là biện pháp giảm rủi ro cần kiểm chứng trên thiết bị, không phải tuyên bố đã sửa dứt điểm lỗi phần cứng. Gửi tuần tự có thể tăng thời gian truyền; phải đo lại mục tiêu dưới 5 giây.

Giữ retry cùng command đúng một lần của 0.5.14. Không đổi UI/UX, map/route/marker, renderer, GPS policy, API policy, payload 8 KiB, RPK hay Xiaomi wire bytes. Test khóa thứ tự ACK đã được bổ sung. Verifier IPA đọc version/build từ project metadata; một timeout của test chạy trên executor CI tăng từ 2 lên 10 giây, không đổi timeout GPS trong sản phẩm. Chi tiết: [ADR 0015](https://github.com/LordierClaw/blueband-map/blob/main/docs/adr/0015-hardware-safe-stop-and-wait-map-transfer.md).

## Gói hiện tại

Chỉ cần cập nhật IPA; giữ RPK đang cài nếu đã là `0.6.11 (26)`.

- IPA: `artifacts/handoff/BlueBandMap-unsigned.ipa`, iOS `0.5.15 (31)`, unsigned arm64, **3,556,848 bytes**.
  SHA-256: `e421366686b0cf427cc3f2a40fc47d98c2e811cc19d393f119726728b53941ca`.
- RPK: `artifacts/handoff/dev.lordierclaw.bluebandmap.band.debug.0.6.11.rpk`, `0.6.11 (26)`, giữ nguyên binary, **32,436 bytes**.
  SHA-256: `155a8019467bbc82d5149ab0e1c14e11b8fdb6f618e3ec915371d637884d1e4f`.
- Commit nguồn IPA trên `main`: `e781ee39afd43f37c7bb34901acc14c068a9da36`. Commit bàn giao sau đó chỉ sửa tài liệu.
- [iOS CI và IPA](https://github.com/LordierClaw/blueband-map/actions/runs/33787726371); [Repository checks](https://github.com/LordierClaw/blueband-map/actions/runs/33787726303): đều success.

## Đã kiểm tra

- `make test`: portable Swift 174, RPK 29, protocol-lab 19, location-runtime 15; metadata/provider-script/handoff checks đạt. Provider-script tests dùng fake curl, không phải phép đo API thật.
- `make lint`, secret scan và `git diff --check`: đạt.
- `npm ci` vẫn báo 14 dependency vulnerabilities của cây phụ thuộc RPK (3 low, 11 high); chưa đánh giá/sửa trong bản delivery này, không chạy tự động `audit fix` làm đổi toolchain.
- iOS CI: 76/76 XCTest đạt, gồm test không gửi chunk tiếp theo khi ACK trước còn chờ. XCTest chạy trên CI macOS, không chạy được trực tiếp trên Linux; không có kết quả XCTest đỏ-trước-sửa để tuyên bố ở đây.
- IPA tải từ CI đã đối chiếu hash, Mach-O arm64, version/build, bundle ID và cấu hình quyền. Có `UIBackgroundModes=location,bluetooth-central`, mô tả quyền Bluetooth/location và mục xin precise location tạm thời. Metadata đúng không chứng minh iOS đã cấp quyền hoặc cập nhật được lúc khóa màn hình.
- Chưa có iPhone/Band truy cập được để thực hiện bài test phần cứng trong lần bàn giao này.

## Bài test 5–10 phút

1. Kiểm tra `SHA256SUMS`, ký/cài IPA mới và xác nhận màn hình app báo `0.5.15 (31)`. Giữ RPK `0.6.11 (26)`. Đóng Mi Fitness trong phiên kết nối trực tiếp; kiểm tra key health chỉ hiện trạng thái hợp lệ, không chụp/xuất key.
2. Cấp Location + Precise Location khi app yêu cầu, bật Bluetooth; kết nối sạch đến `applicationReady`. Bắt đầu đúng một tuyến ngắn. Kỳ vọng map đầu có route/marker và `band.displayed`, không chỉ preview trên iPhone.
3. Di chuyển/replay cùng tuyến qua ít nhất 10 refresh khi mở màn hình. Kỳ vọng hình ảnh không hỏng, ACK hoàn tất với `window=1`. Đo độ trễ từ fix đến hình Band thực sự hiển thị, không dùng thời gian ACK thay thế.
4. Khóa iPhone, tiếp tục cùng tuyến ít nhất 5 phút và 10 refresh. Mục tiêu mỗi cập nhật do di chuyển có ý nghĩa hiển thị trong **dưới 5 giây** dưới tín hiệu bình thường. Không thao tác điện thoại/Band khi đang lái xe; dùng replay trước, người đi cùng quan sát hoặc dừng an toàn.
5. Export log ngay sau bài test: cần `band.displayed`, `displayedFixAgeMs`/`fixToDisplayMs` hữu hạn và ACK đầy đủ; không có `TRANSFER_TIMEOUT`, `BAND_DISPLAY_FAILED`, `MAP_PAYLOAD_TOO_LARGE`. `violations=0` khi chưa có lần display nào không được tính là đạt độ trễ.
6. Sau khi bài chính đạt, ngắt Bluetooth một lần trong lúc truyền rồi kết nối lại. Kỳ vọng retry hữu hạn, trạng thái lỗi rõ ràng, không treo app; chủ động bắt đầu lại tối đa một lần và map phải trở lại. Stop navigation phải dừng phiên cập nhật vị trí.

Ngân sách kiểm thử thủ công: tối đa **2 Route v4 requests** (một lượt chính, một lượt phục hồi), không tìm kiếm nhiều điểm đến, không cố tình đi lệch tuyến. Giới hạn **200 TileMap/style/tile requests** cho toàn bài, theo dõi bằng bộ đếm phía provider và dừng nếu chạm ngưỡng. Đây là ngưỡng dừng của bài test, không phải giới hạn HTTP được thêm vào app; số tile thực tế phụ thuộc cache/viewport. Nếu không đo được số request, ghi `NEEDS-MEASURE`, không tự kết luận tối ưu API đã đạt.

## Dừng và phản hồi

Dừng ngay tại lỗi đầu, không bấm Start lặp lại: export log đầy đủ, ảnh màn hình Band, thời điểm, phiên bản iOS và firmware Band; không gửi key/device identifier/raw capture. Nếu map vẫn không hiện ở `window=1`, cần truy tiếp delivery/ACK từ bằng chứng đó, không tiếp tục hạ chất lượng renderer theo suy đoán.

Gửi `PASS-HW`, `FAIL-HW`, `BLOCKED-ENV` hoặc `NEEDS-MEASURE` cùng bước đầu tiên lỗi và số đo. Nếu chức năng chạy nhưng độ trễ từ 5 giây trở lên, bài độ trễ vẫn không đạt.

Phục hồi an toàn: Stop navigation, ngắt phiên BlueBand, mở lại Mi Fitness. IPA 0.5.14 đã thất bại trên thiết bị này nên không được coi là bản known-good; không có bản realtime known-good đã được chứng minh để hứa rollback. Artifact 0.5.14 vẫn có thể tải lại từ [CI cũ](https://github.com/LordierClaw/blueband-map/actions/runs/33780329301) để đối chiếu nếu còn trong thời hạn lưu trữ. Thư mục bàn giao hiện tại chỉ giữ IPA mới và RPK không đổi.
