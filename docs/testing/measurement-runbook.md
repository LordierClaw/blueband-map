# Một lần cài, đủ bằng chứng để chọn tối ưu

Mục tiêu: cả Bắt đầu, di chuyển, rẽ và đổi vùng đều **nhỏ hơn 1000 ms**.
Bản đo giữ nguyên thuật toán truyền hiện tại. Chưa có kết quả thực nghiệm chứng
minh đạt mục tiêu. IPA chưa ký cần quy trình ký/cài hiện có của dự án.

## Trước khi ra đường

1. Dùng IPA và RPK từ cùng source SHA trong gói bàn giao; đối chiếu SHA256SUMS.
   Ghi iPhone model, iOS đầy đủ (hiện là iOS 27), firmware Band đầy đủ, app/RPK
   version. “Firmware không đổi” chưa đủ để so sánh các lần chạy sau.
2. Bật Đo hiệu năng. Đặt mã ca ngắn như `fg-warm-01`, chọn nguồn GPS thật hoặc
   replay; chọn Tự động. Không nhập khóa, địa chỉ hay thông tin cá nhân vào mã ca.
3. Chọn Hiện số khung nếu quay video. Dùng thiết bị thứ hai quay cả iPhone và
   Band, nhìn thấy lúc bấm Bắt đầu và khi bản đồ đổi. Video cần đủ tốc độ khung
   để phân biệt gần ngưỡng 1 giây; ghi FPS và mọi gián đoạn.
4. Thử một phiên đứng yên ngắn, bấm Chụp chẩn đoán, chờ trạng thái nhận đủ rồi
   Dừng và export JSONL. Kiểm tra báo cáo trước khi thực hiện bài dài. Trace
   không có identity/transport hoặc báo mất sự kiện cần xử lý ngay.

## Các ca ngắn trong cùng bản cài

| Mã gợi ý | Cách chạy | Bằng chứng chính |
| --- | --- | --- |
| `fg-cold-01` | Mở ứng dụng, kết nối như sử dụng thực tế, bấm Bắt đầu ngay khi có thể | Start → xác nhận đầu tiên; ghi rõ GPS/cache/mạng đã sẵn hay chưa |
| `fg-warm-01` | Dừng rồi bắt đầu lại cùng tuyến | So sánh startup ấm; không trộn với cold |
| `fg-move-01` | Đánh dấu Di chuyển đã có bản đồ → Đổi vùng → Rẽ trước từng đoạn | Fix → khung xác nhận, cell thiếu, reset và callback |
| `bg-move-01` | Bắt đầu khi mở app rồi khóa iPhone và di chuyển | Mốc app background, GPS tiếp tục, thiếu khung hoặc chậm |
| `recovery-01` | Đánh dấu Khôi phục; để Band ngủ rồi đánh thức hoặc ngắt/kết nối lại | Trạng thái suspend, callback cũ, pending/abandoned, hiển thị phục hồi |
| `full-compare-01` | Chọn Toàn khung trước Start, lặp lại đoạn ngắn vừa đo | Đối chứng cùng bản cài, cùng tuyến/nguồn GPS |

Đánh dấu “Thấy đứng hình/sai hình” ngay khi gặp vấn đề; ghi thời điểm video vào
notes sau đó. Mốc này phản ánh quan sát của người thử, không tự tính pixel latency.
Không thao tác khi đang lái xe; nhờ người đi cùng đánh dấu/quay video.

Trước mỗi Dừng: bấm Chụp chẩn đoán và chờ nhận đủ hoặc ghi nhận timeout.
Sau mỗi Dừng: export Performance trace và lưu vào thư mục ca đó. Trace chỉ giữ
ba phiên gần nhất; không chờ đến phiên thứ tư mới export. Nếu app bị đóng/crash,
export ngay sau mở lại và giữ phiên thiếu kết thúc; không xóa bằng chứng lỗi.

## Thư mục mỗi ca

```text
fg-move-01/
  navigation.jsonl       # giữ bản export nguyên gốc
  run.json               # sao chép mẫu bên dưới, điền thông tin thực tế
  notes.txt              # thao tác, dấu hiệu, timestamp video
  video.mp4              # nếu quay; không suy ra pixel latency khi thiếu
  replay.csv / replay.gpx # chỉ khi dùng replay, đây là lịch phát dự kiến
```

```json
{
  "caseID": "fg-move-01",
  "sourceSHA": "FILL_FROM_HANDOFF",
  "iphoneModel": "FILL",
  "iosVersionAndBuild": "FILL",
  "bandFirmware": "FILL",
  "appVersionAndBuild": "FILL",
  "rpkVersionAndBuild": "FILL",
  "gpsSource": "device",
  "network": "FILL",
  "startConditions": {"connected": true, "gpsReady": true, "cache": "warm"},
  "videoFPS": null,
  "notes": "FILL"
}
```

Chạy `make perf-report RUN=/duong/dan/ca` rồi chọn `SESSION=...` tương ứng nếu
export chứa nhiều phiên. Giữ JSONL nguyên gốc; báo cáo là dữ liệu dẫn xuất.
Đọc `startupGate`, `measurementReadiness`, `subsecondGoal` cùng các gate cũ.
Exit code 0 chỉ có nghĩa phân tích chạy được, không có nghĩa độ trễ đạt.

Để kiểm tra toàn bộ bộ ca trước khi rời địa điểm thử, sao chép
`tools/perf/packet.example.json` thành `packet.json` trong thư mục cha các ca rồi
chạy `make perf-packet PACKET=/duong/dan/bo-ca`. Công cụ đọc các thư mục đã khai
báo, tìm phiên khớp mã ca duy nhất và chỉ rõ dữ liệu thiếu/sai phiên bản. Nếu cùng
mã ca được chạy nhiều lần, thêm `sessionId` đúng trong `packet.json`. Nó giữ riêng
kết quả độ trễ và trạng thái đủ dữ liệu: ca chậm/lỗi vẫn có thể đủ để phân tích,
không cần chạy lại chỉ để có PASS. Hash mã nguồn trong `run.json` là khai báo của
người thử, chưa phải bằng chứng xác thực binary trên thiết bị.

## Chỉ chạy dài khi ca ngắn đủ dữ liệu

| Quan sát | Bước tiếp theo |
| --- | --- |
| Trace thiếu/mất sự kiện, thiếu RPK/native callback | Sửa thu thập bằng chứng trước; không kết luận độ trễ |
| Start chậm dù fix mới nhanh | Xem GPS wait/route/render/transfer từ navigation.intent |
| BLE queue/ACK wait lớn ở cùng request | Thử lịch ưu tiên control/ACK trong vòng tối ưu kế tiếp |
| Cell chưa có/đổi hướng reset lâu | Thử prefetch/decode hoặc xử lý xoay, giữ budget |
| Confirm nhanh nhưng video đứng hình | Điều tra image decode/apply/scanout và lifecycle Band |
| Ca ngắn đủ dữ liệu | Chạy dài 20–30 phút để kiểm tra resource/lifecycle, vẫn export từng Stop |

Không đổi nhiều biến cùng lúc. Các tối ưu tiếp theo cần cùng bộ ca và cùng tiêu
chí, để so sánh với baseline này mà không phải cài thêm bản chỉ để thêm log.
