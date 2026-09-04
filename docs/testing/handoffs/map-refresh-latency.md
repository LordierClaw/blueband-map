# Bàn giao tối ưu refresh map và sửa HUD

Ngày 2026-09-04. iOS **0.5.18 (34)**, Band **0.6.13 (28)**. Cần cập nhật cả IPA và RPK.

## Nguyên nhân và thay đổi

- Tên đường ngắn bị đẩy sang phải do `.nav-street` có `text-align: right`, không phải Vietmap thêm khoảng trắng. Đổi sang căn trái trong cùng khung, không dời bố cục.
- Log 0.5.17 có GPS/chỉ dẫn gần 1 Hz, nhưng nhiều lượt render trả `MAP_INVALID_REQUEST`. Camera yêu cầu điểm rẽ kế tiếp luôn nằm phía trước hướng di chuyển. Đường vòng, quay đầu hoặc điểm trùng vị trí không thỏa điều kiện này ở bất kỳ zoom nào. Camera mới giữ khung heading-up cục bộ trong những trường hợp đó; vẫn fit điểm rẽ khi có thể. Test chạy mã camera thật tái hiện 14/14 trường hợp lỗi trước sửa và đạt 14/14 sau sửa.
- Một frame trong log mất 2.675 ms dựng ảnh và khoảng 7.666 ms truyền/hiển thị, tổng tuổi GPS khi hiển thị 11.347 ms. Ảnh vốn đã được chia chunk; trước đây mỗi chunk phải chờ ACK riêng. Navigation dùng cửa sổ **2 chunk**, tận dụng giao thức đã hỗ trợ sẵn. Không tăng envelope, không đổi wire Xiaomi, không bỏ ACK/hash/offset/retry, không gửi nhiều frame đồng thời. Coordinator vẫn giữ lựa chọn stop-and-wait cho các caller khác.
- Encoder so sánh PNG 16 màu đủ độ phân giải với JPEG rồi chọn ảnh nhỏ hơn; chỉ dùng fallback giảm chất lượng cũ nếu cả hai không vừa 8 KiB. Giữ màu xanh route `#168cff`. Không đổi độ phân giải, route geometry, font map, marker hoặc icon đích. Tile/style cache và cooldown lỗi provider vẫn giữ nguyên; không thêm API polling/prefetch hay tiled composition trên Band.
- Khi frame hoàn thành, dùng chỉ dẫn mới nhất đang chờ thay vì GPS cũ lúc bắt đầu dựng ảnh. Sửa hiện tượng trong log khoảng cách vừa xuống 326 m lại nhảy lên 442 m.
- Bộ ghi thống kê trước đây từ chối `cpu-cold/cpu-warm` rồi bỏ bản ghi, khiến `bandTransfer` có thể giữ số liệu của frame foreground cũ. Chấp nhận đúng hai trạng thái cache do renderer nền trả về; test AppModel sử dụng trạng thái CPU thật, kiểm tra số liệu window 2 sau khi hiển thị. Không mở validation cho chuỗi tùy ý.
- Thay sáu glyph tự vẽ bằng [Google Material Icons Round](https://github.com/google/material-design-icons/tree/0cbb08816df07faaae3dca060d4ebb10b66c214f/src/maps), rasterize offline thành RGBA PNG trong cùng ô 44x56. RPK chứa license Apache-2.0. Không thêm thư viện runtime/build; PNG, SVG gốc và hướng dẫn tái tạo được lưu trong repo. Roundabout là ký hiệu chung, không giả lập số lối ra mà giao thức hiện tại không có.

## Số đo và giới hạn

[CI tái hiện trước sửa](https://github.com/LordierClaw/blueband-map/actions/runs/33836159061) đã bắt được lỗi camera, chỉ dẫn cũ và encoder gửi ảnh lớn không cần thiết. Với fixture map, JPEG 8.050 byte trong khi PNG đủ độ phân giải chỉ 4.837 byte, PSNR 31,25 dB. Mô hình cùng payload 7.416 byte, ACK 500 ms đo được window 1 = 7,72 s, window 2 = 4,14 s. Đây là phép đo kiểm thử iOS, **không phải tốc độ BLE thật** và chưa tính mạng/provider hay lịch chạy khi khoá iPhone.

Sau khi khôi phục đúng màu route, cùng fixture còn 4.833 byte, PSNR 34,06 dB. Năm ảnh CPU xoay 0/45/90/180/270 độ giảm từ 6.201/8.107/5.243/5.629/6.671 byte xuống 2.207/4.031/1.721/1.854/2.581 byte. Đã đối chiếu ảnh xuất từ iOS: giữ hình học, tên đường và màu route; không dùng block pixel để đạt các số đo này.

Test RPK lặp 100 map 8 KiB, luân phiên stop-and-wait và đảo thứ tự hai chunk, mất ACK/native `204`, gửi lại lệnh y hệt, kiểm tra SHA/byte, công bố scene sau decode và số file hữu hạn. Không nới xử lý lỗi disconnect thật. Bản này không gọi Route API nhiều hơn hay thay cơ chế GPS/quyền vị trí.

Mục tiêu dưới 5 giây vẫn phải nghiệm thu trên iPhone + Band. Không coi một ảnh đầu, simulator, hay riêng `terminal=displayed` là bằng chứng realtime đạt yêu cầu. Độ trễ cold cache/mạng chậm cần được tách khỏi các cập nhật warm cache.

## Kiểm chứng và gói bàn giao

- Source iOS cuối: `1d16ed8db99a75832f7e5d99903859339aa410b0`, đã push `main`.
- `make test`: 175 Swift portable, 33 Band, 19 protocol-lab, 15 GPS runtime; các kiểm tra metadata/provider-script/handoff đều đạt. `make lint`, kiểm tra secrets và `git diff --check` đạt.
- [iOS CI cuối](https://github.com/LordierClaw/blueband-map/actions/runs/33837894296): **84 test, 0 lỗi**, build/kiểm tra ứng dụng arm64 và xuất unsigned IPA thành công. Ảnh CPU xuất từ lượt này khớp số byte bên trên; ảnh 45° giống từng byte với ảnh đã rà soát trực quan.
- [Swift package CI](https://github.com/LordierClaw/blueband-map/actions/runs/33837894344) và [Repository CI](https://github.com/LordierClaw/blueband-map/actions/runs/33837894318) cùng source cuối đều đạt.
- RPK lấy từ [Band CI](https://github.com/LordierClaw/blueband-map/actions/runs/33836798748), source `15ec41507e948bd4fa734d840b7be0ca9ab76bfd`. `apps/band` không thay đổi từ commit này tới source iOS cuối; toàn bộ PNG và license bên trong RPK đã so khớp với source hiện tại.
- Kiểm tra trực tiếp IPA: phiên bản 0.5.18 (34), `UIBackgroundModes` gồm `location` và `bluetooth-central`, có mô tả xin quyền vị trí/Bluetooth và temporary precise location. Bản sửa không thay cơ chế xin quyền đã có.
- Gói hiện tại đặt tại `artifacts/handoff`, kèm `HANDOFF.md` và `SHA256SUMS`. Không kèm khóa ký, profile hay credentials. IPA chưa ký, cần ký trước khi cài. Đây là xác nhận mã/CI/package, chưa phải nghiệm thu trên thiết bị thật.

| Artifact | Byte | SHA-256 |
| --- | ---: | --- |
| `BlueBandMap-unsigned.ipa` | 3561955 | `329b6924c6c338800d676729a43e90c072cfcedbf9543883e10208fd899837f9` |
| `dev.lordierclaw.bluebandmap.band.debug.0.6.13.rpk` | 41775 | `11debfb81b8973b19f2a61b72f03ec8defd697530998694868889f0a37ea7c51` |

Cặp cũ được thay khỏi thư mục bàn giao để tránh cài nhầm. Có thể tải lại [IPA 0.5.17](https://github.com/LordierClaw/blueband-map/actions/runs/33834420300) và [RPK 0.6.12](https://github.com/LordierClaw/blueband-map/actions/runs/33828764150) từ CI trong thời hạn lưu artifact; đã xác nhận chưa hết hạn lúc bàn giao.

## Một lượt kiểm tra thiết bị

1. Ký/cài IPA 0.5.18 (34), cài RPK 0.6.13 (28), xác nhận hai phiên bản. Giữ quyền Bluetooth, vị trí chính xác; bắt đầu navigation khi iPhone đang mở.
2. Dùng cùng tuyến thử qua Yên Bình, Nguyễn Khuyến, vòng xuyến và đoạn quay đầu. Kiểm tra tên ngắn bắt đầu sát phía trái khung chữ, icon rõ, map thay đổi liên tục và khoảng cách không nhảy về số cũ mỗi lần map xuất hiện.
3. Tiếp tục khoá iPhone 3–5 phút trong cùng phiên. Xuất log đầy đủ một lần. Kiểm tra nhiều `band.displayed` liên tiếp, `window=2`, `fixAgeMs`/`fixToDisplayMs` và khoảng cách giữa các frame. Mục tiêu cập nhật cần thiết <5000 ms; không có `MAP_INVALID_REQUEST`, payload-too-large hoặc band-display-failed.
4. Nếu gặp lỗi, giữ nguyên phiên và xuất log ở lỗi đầu; không Start liên tục. Gửi log kèm trạng thái màn hình và loại GPS (thật/replay). Không thao tác khi lái xe.
