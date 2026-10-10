# Measurement candidate 2026-10-10

Bản này bổ sung phép đo để chọn tối ưu cho mục tiêu **khởi tạo, di chuyển, rẽ
và đổi vùng đều dưới 1000 ms**. Chưa có trace/video từ thiết bị thật để nghiệm thu
độ trễ hoặc tương thích iOS 27 và firmware Band 10 hiện tại.

- Source SHA: `0947f7b9824eb13b6ea25722b3214673079f57a9`.
- Nhánh: `codex/map-diagnostics`, base `07cb57977b0133b91a1e25937ea69b5b241384b4`.
- iOS: `0.5.24 (40)`; RPK: `0.6.19 (34)`.
- Trạng thái: CI đạt; đã tải và kiểm tra cặp artifact của source SHA trên.

## Nội dung đã triển khai

Start được ghi trước kiểm tra điều kiện và xử lý điều hướng, nên chờ GPS/route/
bootstrap không biến mất khi có fix mới. Metadata mã ca, nguồn GPS, chế độ map
và marker được chốt cho cả phiên. Có chế độ toàn khung để so sánh ngay trong
cùng bản cài, đánh dấu cached/coverage/turn/recovery và ghi nhận lỗi thấy trên màn.

Trace nối request/topic với hàng đợi BLE, số lần gọi native write, byte đã thử
gửi, retry và thời gian chờ ACK trên đường nhận. Band trả bộ đếm native send và
thời gian callback bằng yêu cầu chẩn đoán riêng, giới hạn kích thước; thiếu callback
không được coi là thành công tức thời. Chẩn đoán hết hạn độc lập sau 8 giây, kể cả
khi sender không phản hồi cancellation. Callback/lệnh cũ không đổi trạng thái lượt mới.

Analyzer giữ cách đọc trace cũ và thêm `startupGate`, `measurementReadiness`,
`subsecondGoal`, phân nhóm pha và bảng nối lệnh. Đồng hồ mâu thuẫn, trace thiếu,
session trộn hoặc khả năng peer chưa biết không tạo kết quả đạt. Pha lấy tại fix
gốc, tránh gán khung đến muộn vào ca rẽ vừa đánh dấu.

Xiaomi framing/authentication/encryption/segmentation, byte retry, cửa sổ chunk,
lịch truyền và budget file/node được giữ nguyên. Phần mở rộng ứng dụng nằm trong
[ADR 0021](../adr/0021-measurement-readiness.md), có vector độc lập 451 byte và
danh sách nghiệm thu phần cứng còn chờ.

## Bằng chứng test trước khi sửa

| Commit | Bằng chứng RED |
| --- | --- |
| `854eb98` | [Swift](https://github.com/LordierClaw/blueband-map/actions/runs/38032884444): 205 tests, 5 assertions thiếu telemetry mới; [Band](https://github.com/LordierClaw/blueband-map/actions/runs/38032884569): 2 test callback mới fail; [iOS](https://github.com/LordierClaw/blueband-map/actions/runs/38032884447): 2 assertions về Start bị từ chối |
| `f934246` | [iOS](https://github.com/LordierClaw/blueband-map/actions/runs/38033644759): 101 tests, chỉ assertion resource reply thiếu vẫn được báo đủ bị fail |
| `48125dd` | [iOS](https://github.com/LordierClaw/blueband-map/actions/runs/38034034740): 102 tests, 3 assertions tái hiện sender treo/guard lượt kế tiếp và 1 assertion resource thiếu; analyzer tái hiện 6 assertions sai trước khi sửa |

Một reviewer độc lập đã rà toàn nhánh và nêu 4 điểm quan trọng: deadline chờ
sender, gán pha tại confirmation, ưu tiên FAIL sai khi startup thiếu contract,
và anchor startup mâu thuẫn. Đã chấp nhận và sửa cả 4 với regression tương ứng;
không có mục nhỏ bị hoãn từ review này.

## Xác minh cuối và artifact

- [Canonical Linux checks](https://github.com/LordierClaw/blueband-map/actions/runs/38034618574): `make lint`, `make test`, Gitleaks đều đạt. Analyzer 47/47, Swift 205/205, Band 57/57, protocol lab 19/19; các kiểm tra shell/metadata/syntax/location/handoff đều đạt.
- [Apple simulator/device build](https://github.com/LordierClaw/blueband-map/actions/runs/38034618403): 102/102 tests, gồm hai regression diagnostic deadline/resource; Release arm64 build và kiểm tra unsigned device artifact đạt.
- `git diff --check` trên toàn nhánh đã đạt.
- Windows: 46/47 analyzer tests đạt; test bảo vệ symlink cũ bị chặn bởi
  `WinError 1314`. Không bỏ/giảm test; Linux CI phải chạy đủ 47 tests.

Artifact được lấy từ hai run trên tại đúng source SHA; đã kiểm tra digest ZIP,
version bên trong IPA/RPK và tạo `SHA256SUMS`. IPA là unsigned, cần quy trình ký/cài
hiện có. Tài liệu có thể có commit mới hơn; source SHA của binary vẫn là mã ghi trên.

| File | SHA-256 |
| --- | --- |
| `BlueBandMap-unsigned.ipa` | `f70dfc0df4d8aaa250c802b7f566ad68e2e44de2621d48dfea97b076a35aade4` |
| `dev.lordierclaw.bluebandmap.band.debug.0.6.19.rpk` | `ad4f3bda76efbde6761e508002713d38dc8e30ea2fe0b1ca955c3543c39ead16` |

Gói local: `E:/code/blueband-map/artifacts/measurement-0947f7b/`, có `HANDOFF.md`,
`RUNBOOK.md`, `provenance.json`, `SHA256SUMS` và `case-template/`. Binary và dữ liệu
thu thực tế nằm ngoài Git. Hai ZIP artifact gốc được giữ trong `ci-archives/`.

## Bước nghiệm thu trên thiết bị

Dùng [runbook](measurement-runbook.md): ca đứng yên ngắn để kiểm tra đủ chẩn đoán,
cold/warm Start, cached/coverage/turn, khóa iPhone, Band sleep/wake/recovery và
đối chứng full-frame. Export sau từng Stop trước khi phiên thứ tư loại phiên cũ.
Giữ trace lỗi/thiếu và video; chỉ chạy dài sau khi ca ngắn có đủ dữ liệu.

ACK hoặc native success chưa xác nhận pixel vật lý. Bộ đếm file/node chưa đo RAM
native. Không suy kết quả dưới 1 giây từ simulator, build hoặc deterministic tests.
Tối ưu scheduling/prefetch/xử lý rẽ tiếp theo được chọn theo bằng chứng này, theo
[nghiên cứu](../research/2026-10-10-subsecond-map-streaming.md).
