# Độ trễ bản đồ sau bản sửa vòng đời ảnh

Ngày đối chiếu: 2026-10-11. Mã sản phẩm: `f274685b094a04a8b10f30327e67da7627040d34`; checkout có thêm tài liệu tại `9c6582a`. Cặp chạy thực tế: iOS **0.5.26 (42)** và Band **0.6.21 (36)**.

**Kết luận:** đường cập nhật bằng ô bản đồ chưa hoạt động trong lần chạy này. Toàn bộ 15 xác nhận hiển thị vẫn là ảnh toàn màn hình; riêng truyền ảnh mất trung vị 3,629 giây. Ưu tiên khôi phục việc chuẩn bị và giữ cache corridor, sau đó giảm việc tạo lại vùng bản đồ khi rẽ. Tăng cửa sổ truyền, tối ưu vài mili giây nén ảnh hoặc thêm test CI không giải quyết nút thắt đã đo.

## 1. Phạm vi và kết quả đo

Nguồn là file người dùng cung cấp `navigation.jsonl`, SHA-256 `bd32cea60007da28bf34fe7471962af241d2cec2aefc9d0cdb3638eda8d65a9b`. Bản sao, báo cáo máy và phép phân tích bổ sung nằm ngoài Git tại `E:/code/artifacts/map-latency-20261011/`. Không đưa tọa độ hay raw capture vào repository.

Export gồm hai phiên ngắn dùng iOS build 41 bị chặn vì sai cặp RPK, và phiên hợp lệ `4a699bb5-dfb4-4ea5-826e-7bd282da12d5`. Chỉ phiên hợp lệ được dùng dưới đây. Phiên bắt đầu 11:32:13 giờ Việt Nam, kéo dài **91,197 giây**, dùng replay trong app và kết thúc với lý do `stopped`. Có 86 fix được chấp nhận, 15 fix có xác nhận, 71 fix không có xác nhận; không ghi nhận mất dòng, lỗi ghi hay cắt ngắn export.

| Phép đo | Trung vị | p95 | Ý nghĩa |
| --- | ---: | ---: | --- |
| Start đến xác nhận đầu | 7.692 ms | một mẫu | Chưa đạt khởi tạo dưới 1 giây |
| Timestamp fix đến xác nhận | 4.901 ms | 7.288 ms | 15/15 mẫu vượt 1 giây |
| Khoảng cách các frame xác nhận | 5.700 ms | 8.641 ms | Bản đồ có quãng đứng hình dài |
| Chuẩn bị frame được truyền | 239 ms | 310 ms | Có dư địa tối ưu, nhưng không phải phần lớn độ trễ |
| Encode frame được truyền | 10 ms | 16 ms | Không phải ưu tiên đầu |
| Truyền full frame | 3.629 ms | 4.041 ms | Nút thắt chính của đường đang chạy |
| Band decode full frame | 59 ms | 1.728 ms | Có một ngoại lệ rất chậm, cần giữ số đo này |
| Lệnh `map.stream.view` đến application ACK | 186 ms | 417 ms | Tiềm năng của lệnh nhỏ; chưa phải xác nhận đủ bản đồ |
| Lệnh `nav.update` đến application ACK | 321 ms | 786 ms | Cần tính thêm tuổi fix và lịch gửi |

Đơn vị trong bảng là mili giây; dấu chấm tách hàng nghìn. Percentile dùng nearest rank. Với 15 mẫu, p95 bằng mẫu lớn nhất; không coi đây là phân bố dài hạn. Không cộng các trung vị để suy ra một frame điển hình vì các mẫu không nhất thiết trùng nhau.

Đích đo là xác nhận Band nhận tại iPhone, chưa phải phép đo pixel trên màn hình. Người dùng báo chưa reboot trong lần này; 91 giây chưa đủ đối chiếu với lần trước reboot sau khoảng 225 giây. Native RAM vẫn chưa được đo.

## 2. Vì sao corridor chưa giúp được

Có **0 cell gửi thành công, 0 cell decoded và 0 viewport corridor được xác nhận đầy đủ**. Chín lần atlas miss đều không có atlas giữ lại. Sáu lần fallback `NAVIGATION_ERROR` xuất hiện khoảng **2.002 ms** sau atlas miss. Tới giây 90,864 mới có một `provider.style` thành công, mất **1.672 ms**; sau đó thấy tile-cache miss nhưng chưa có tile fetch hoàn tất trước khi dừng.

Đối chiếu mã:

- `apps/ios/Adapters/Vietmap/VietmapCPURenderer.swift`: HTTP transport mặc định timeout 2 giây; tải style khi cache rỗng. Công việc tải phụ thuộc task render hiện tại; sau tải có kiểm tra cancellation trước khi giữ kết quả.
- `apps/ios/App/AppModel.swift`: đổi zoom hoặc hướng quá 15 độ làm reset corridor. Trace có tám reset: một zoom và bảy heading. Mở stream rồi mới kiểm tra camera mới nhất cũng có thể tạo chuỗi open/close không tạo được cell.
- `apps/ios/Adapters/Vietmap/URLSessionHTTPTransport.swift`: mỗi request tạo một ephemeral session rồi hủy session. Không có session dùng chung rõ ràng để tái sử dụng kết nối. Trace hiện tại không có DNS/TLS metrics để định lượng chi phí này.
- `navigationErrorCode` gộp lỗi HTTP nền thành `NAVIGATION_ERROR`, làm mất domain/code gốc. Vì vậy **timeout là giả thuyết mạnh, chưa phải nguyên nhân đã được xác nhận bằng mã lỗi**. Những lượt bị đổi camera còn có thể bị hủy trước khi tải xong.

Lần trước đã thấy một cell mất 21,267 giây ở đường CPU với cache ấm. Đây vẫn là vấn đề riêng. Trong lần này, chưa có bằng chứng renderer CPU đi qua tải style để tới bước vẽ atlas; không gán sáu khoảng chờ 2 giây cho vẽ geometry.

Các test cache hiện có dùng một road layer rỗng. Fixture vẽ khác có geometry nhưng nhỏ. Chúng kiểm tra đúng việc tái sử dụng và kết quả hình học, không đại diện cho chi phí vẽ vùng đô thị dày đặc.

## 3. Truyền tin và callback native

Full-frame transfer **đã dùng sliding window 4**. Bốn chunk đầu được gửi gần nhau; chunk kế tiếp được bổ sung khi từng ACK tới. Đề xuất “đổi từ 1 lên 4” không áp dụng cho mã đang chạy.

232 lệnh `map.asset.chunk` có thời gian đến application ACK trung vị 717 ms, p95 1.019 ms, tối đa 1.197 ms. Trong khi đó, iPhone local write queue p95 chỉ 0,544 ms, tối đa 2,100 ms; xử lý/gửi SPP ACK cục bộ p95 0,576 ms. Vì thế ưu tiên hàng đợi ACK trên iPhone chưa phải tối ưu chính theo trace này. Các số đo local không đo thời gian sóng Bluetooth hay xử lý ở firmware.

Native pending tăng từ 2 lên 155 trong chín snapshot. Snapshot cuối có 455 attempted, 300 succeeded, 0 failed, 155 pending, 0 abandoned. Đối chiếu cho thấy:

- Bộ đếm tuân theo `attempted = succeeded + failed + pending + abandoned`.
- Trước snapshot cuối, iPhone đã nhận 456 SPP data frame; snapshot lấy trước khi gửi report và ACK của chính request nên không thể so sánh hai bộ đếm như cùng một thời điểm.
- Toàn phiên có 502 SPP data frame nhận liên tiếp theo sequence modulo 256 và 502 SPP ACK được ghi thành công phía iPhone.
- Không phải toàn bộ callback của ACK-only đều thiếu: số callback thành công lớn hơn nhiều tổng message envelope. Cũng không phải chỉ message envelope bị thiếu callback.

**Pending callback không đồng nghĩa 155 gói chưa gửi hay 155 buffer RAM bị giữ.** Dữ liệu có thể tới iPhone mà success/fail callback của API Band vẫn không hoàn tất. Đây là bất thường cần đo, không đủ kết luận memory leak hoặc nguyên nhân reboot. `maxCallbackMs=1330` chỉ mô tả callback đã hoàn tất.

Phép đo bổ sung có ích nhất: chia bộ đếm theo ACK-only/message, số callback tới/được chấp nhận/bị loại do owner cũ, tuổi callback chưa hoàn tất lâu nhất và một mẫu ID hữu hạn. Cuối replay có một đoạn ngừng phát dữ liệu ngắn với deadline cố định để quan sát khả năng thoát hàng chờ. Không chuyển mọi native send sang chờ callback nối tiếp: nếu callback thực sự bị bỏ, cách đó có thể khóa luôn đường phản hồi.

## 4. Bài học từ các repository tương tự

Các nguồn được ghim commit để tránh trôi phiên bản. Chúng cung cấp cách tổ chức dữ liệu và xác nhận; chưa có nguồn nào dưới đây chứng minh stream bản đồ dưới 1 giây trên đúng Band 10/iOS của dự án.

| Nguồn | Điều có thể áp dụng | Giới hạn |
| --- | --- | --- |
| [HyperMap README](https://github.com/flash555588/HyperMap/blob/e04736adfd5aca778de3d1b4e76bae9e13ab989a/README.md), [Vela map page](https://github.com/flash555588/HyperMap/blob/e04736adfd5aca778de3d1b4e76bae9e13ab989a/watch/src/pages/map/map.ux) | Điện thoại chuẩn bị PNG; Band lưu file, dùng cache lân cận; vị trí/tuyến được cập nhật riêng. Có quan tâm tới API Vela cũ. | Android companion qua SDK khác đường iOS raw BLE. README đặt chu kỳ GPS 15 giây/25 m, map 60 giây/75 m; không phải benchmark dưới 1 giây. Tác giả tránh một số transform vì lỗi trên Vela cũ, không chứng minh firmware này có cùng lỗi. |
| [BangleApps openstmap](https://github.com/espruino/BangleApps/blob/878e2c01653ea0233a8327d6bc27f4fa5ddae2be/apps/openstmap/openstmap.js), [marker overlay](https://github.com/espruino/BangleApps/blob/878e2c01653ea0233a8327d6bc27f4fa5ddae2be/apps/openstmap/app.js), [route prefetch](https://github.com/espruino/BangleApps/blob/878e2c01653ea0233a8327d6bc27f4fa5ddae2be/apps/openstmap/routeplan.js) | Tile địa lý ổn định; vẽ vùng giao viewport; marker/course tách khỏi nền; chuẩn bị tile dọc tuyến. | Phần cứng và graphics API khác. Học cách phân tách vòng đời, không sao chép API hay suy ra tốc độ Vela. |
| [Gadgetbridge Xiaomi BLE V2](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/commit/4d294c0870cb20e9424fee558471fb087c117500/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/xiaomi/XiaomiBleProtocolV2.java), [WriteAction](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/commit/4d294c0870cb20e9424fee558471fb087c117500/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/btle/actions/WriteAction.java) | Tham khảo negotiation, phân mảnh, ACK và quản lý lần ghi đang chờ. Phải phân biệt BLE với transport khác. | Không có benchmark map dưới 1 giây. `XiaomiSppProtocolV2` của repo dùng Bluetooth Classic; không lấy window 128 của nó áp sang BLE. |
| [BandReader Android](https://github.com/zhaoyutiandc/BandReader_Android/blob/8aba961a7bcba0c5b7080e443dda780ec694f73d/app/src/main/java/com/example/bandReader/MainViewModel.kt), [Band file handling](https://github.com/zhaoyutiandc/BandReader_band/blob/590110677527e4b4e83ade6a99cf0b329368f0ff/src/app.ux) | Tách success của API gửi với `chunk_saved` sau ghi file. Hữu ích để thiết kế telemetry theo từng tầng. | Chunk 2.000 ký tự ở SDK không phải MTU BLE hoặc throughput đo được. |

Chỉ tham khảo nguyên lý, không nhập mã bên ngoài. Tài liệu [Vela transform](https://iot.mi.com/vela/quickapp/en/components/general/animation-style.html) có phép quay, nhưng khả năng API không bảo đảm clipping, memory và độ mượt trên firmware Band 10.

## 5. Phương án tối ưu được khuyến nghị

### Bước đầu: làm corridor hiện có thực sự hoạt động

Tách công việc chuẩn bị nguồn bản đồ khỏi một camera/fix cụ thể. Có một lần tải style đang chạy dùng chung theo navigation owner và revision của cấu hình; giữ kết quả hợp lệ qua thay đổi hướng. Hủy và loại kết quả cũ khi Stop/đổi key. Chuẩn bị trước vùng bắt đầu và phần tuyến phía trước khi đã biết đích, đồng thời giữ giới hạn HTTP body, cache và số request đang chạy.

Bổ sung begin/end/error cho các bước style, tile fetch/decode, project/draw, crop/encode. Lỗi chỉ ghi stage, domain/code được cho phép, trạng thái cancellation và thời gian; không ghi URL, key hoặc body. Nếu đo session reuse, dùng task metrics đã lọc. Chỉ nới timeout sẽ làm fallback chờ lâu hơn; nó không đáp ứng mục tiêu khởi tạo.

Sau khi xác định lỗi, cân nhắc session dùng lại với delegate quản lý request hữu hạn, giữ redirect rejection, streaming size limit, cancellation và exactly-once completion. Không suy rằng session reuse tự đem lại một mức tiết kiệm cụ thể khi chưa có metrics.

Với CPU atlas, dùng một fixture tổng hợp đủ roads, polygons, labels và geometry ngoài viewport. Đo số feature/vertex qua từng bước, loại sớm geometry không giao vùng vẽ có gutter. Giữ kiểm tra tương đương hình ảnh ở rìa cell, stroke và label; không dùng ngưỡng wall-clock simulator làm test bắt buộc dễ chập chờn.

### Hướng dài hạn: nền ổn định và cập nhật trạng thái nhỏ

Tiếp tục kiến trúc corridor, nhưng giảm phụ thuộc của cache vào heading và tiến độ tô tuyến. Nền bản đồ, tuyến, marker và HUD có vòng đời khác nhau. Chỉ vị trí/khung nhìn mới nhất nằm trên đường cần phản hồi dưới 1 giây; dữ liệu nặng được chuẩn bị trước theo tuyến và giữ có giới hạn. Thiếu coverage phải được ghi là miss, không tính giữ ảnh cũ thành cập nhật thành công.

| Cách xử lý hướng | Lợi ích | Chi phí và quyết định |
| --- | --- | --- |
| Sửa corridor camera hiện tại, chuẩn bị trước vùng/camera kế tiếp | Giữ trải nghiệm đang có; ít thay đổi giao thức hơn | Cache vẫn có thể vô hiệu khi rẽ bất ngờ; chưa đủ cơ sở cam kết mọi lần rẽ dưới 1 giây |
| Nền north-up ổn định, quay marker | Ít reset; RAM và coverage dễ giới hạn nhất | Thay đổi trải nghiệm heading-up; chỉ là lựa chọn, chưa mặc định áp dụng |
| Tile địa lý ổn định, quay khung nhìn trên Band | Có thể giữ heading-up mà không truyền lại nền mỗi lần rẽ | Cần kiểm chứng transform/clipping và ngân sách ảnh trước; thay đổi contract phải có ADR/vector độc lập/hardware cases |

Không đơn giản gắn `rotate` vào container đang có. Viewport 212×520 quay 45 độ có bounding box khoảng 518×518; nếu lấy mọi tile của bounding box thì ở vị trí lưới bất lợi có thể cần 6×6 tile, vượt giới hạn 24 resident hiện tại. Thuật toán giao polygon có thể giảm số này nhưng còn phải tính đồng thời viewport cũ/mới khi chuyển cảnh. Không tăng cap để né thiết kế bộ nhớ.

`map.stream.view` hiện chỉ truyền offset/sequence và vị trí đích, chưa truyền heading. Tách overlay hoặc thêm rotation là thay đổi kiến trúc thật, không phải chỉnh tham số một dòng. Giữ nguyên Xiaomi framing/crypto; mọi thay đổi wire phải theo yêu cầu repository.

Lịch `nav.update` hiện chờ ACK rồi ngủ thêm một giây. Với ACK trung vị 321 ms, chính lịch này có thể làm chỉ dẫn mới chậm dù bản đồ đã được sửa. Chuyển sang lịch theo deadline và lấy bản mới nhất, vẫn giữ số lệnh đang chờ hữu hạn. Đây là luồng chỉ dẫn; không đồng nhất nó với thời gian `map.stream.view`.

### Khởi tạo hoàn toàn mới vẫn là một giới hạn riêng

Style request thành công duy nhất mất 1,672 giây, chưa gồm tile, dựng ảnh hay truyền Band. Khi chưa có dữ liệu cục bộ và còn phụ thuộc mạng ngoài, không thể bảo đảm toàn bộ cold start dưới một giây. Muốn tiến gần yêu cầu phải chuẩn bị cache trước, hoặc cung cấp dữ liệu offline phù hợp. Báo riêng thời gian chuẩn bị, Start đã sẵn sàng và Start hoàn toàn mới; không đổi mốc đo hay dùng màn hình placeholder/route-only để nhận PASS cho bản đồ đầy đủ.

## 6. Một lần replay thu được đủ bằng chứng

Giữ mục tiêu người dùng chỉ cần cài một cặp và bấm một lần; không yêu cầu di chuyển ngoài đường. Khi triển khai đợt tối ưu, gộp các pha vào cùng một lượt tự động có nhãn:

1. Ghi rõ cache/connectivity ban đầu; đo Start đến xác nhận đầu. Chuẩn bị trước cũng có thời gian riêng.
2. Chạy đoạn thẳng trong vùng đã cache, rồi qua ranh giới tile; thu cache hit/miss, cell stored/decoded và viewport confirmation.
3. Rẽ 90/180 độ, đổi zoom và đổi vùng đã định trước; ghi reset reason, owner/generation và coverage còn thiếu.
4. Dừng producer trong một đoạn ngắn có deadline để đo pending callback có giảm không. Sau đó thực hiện Stop và chuẩn bị export, vẫn kết thúc được nếu peer mất kết nối.
5. Tổng thời gian khoảng 5 phút để vượt mốc reboot trước đó. Có thể giữ màn hình điện thoại mở trong lần đầu nhằm cô lập renderer/transport; kiểm thử background là pha riêng, không gộp kết quả active/background.

Một export phải trả lời được: thời gian nằm ở mạng, dựng ảnh, lệnh/ACK, decode hay chờ coverage; callback pending thuộc lớp nào; bước nào đã bị hủy. Kiểm tra tự động trước bàn giao phải chứng minh replay thực sự phát fix, kết thúc được khi lỗi, và export tồn tại. Dữ liệu replay không thay cho phản hồi Band. Phép đo pixel/video chỉ cần cho lần xác nhận mục tiêu cuối cùng, không bắt người dùng quay lại mỗi vòng debug.

## 7. Giảm thời gian CI mà vẫn giữ kiểm tra có ích

Đối chiếu workflow hiện tại:

- `repo-checks.yml` chạy `make test` ở mọi push/PR, đã bao gồm Swift, Band, protocol và kiểm tra script.
- `band-checks.yml`, `swift-checks.yml`, `protocol-lab-checks.yml` lại chạy các suite tương ứng khi đường dẫn thay đổi. Band còn build/upload thêm một RPK.
- Thay đổi chỉ có tài liệu cũng làm workflow tổng chạy toàn bộ suite và tạo RPK.
- `ios-checks.yml` chạy simulator test, sau đó build Release arm64 và upload IPA. Đây là kiểm tra Apple SDK khác Linux, không phải toàn bộ đều trùng.

Phương án: một workflow sở hữu suite Linux chuẩn; các workflow chuyên biệt chỉ phục vụ chạy thủ công khi điều tra. Với thay đổi chỉ có docs, giữ check tổng trả trạng thái rõ ràng nhưng bỏ bước build/test nặng bằng điều kiện nội bộ; tránh làm required check treo do bỏ cả workflow. Chỉ tạo IPA/RPK phát hành ở checkpoint bàn giao hoặc yêu cầu rõ ràng. Kiểm tra push/PR trùng phải tính branch protection và merge ref trước khi đổi trigger.

Trong phát triển: failing behavioral test cho lỗi đang sửa, rồi test liên quan. Trước tuyên bố bản sửa hoạt động vẫn chạy `make test`, `git diff --check` và kiểm tra iOS cần thiết một lần trên mã cuối. Không chạy lại toàn bộ vì sửa tài liệu. Các test chờ deadline có thể dùng clock điều khiển được khi clock đó thật sự chạy qua đường cần kiểm tra; không xóa kiểm tra Stop/disconnect/lifecycle để giảm vài giây.

Không dùng subagent cho phần phát triển tiếp theo trừ khi người dùng yêu cầu. Quy ước này được bổ sung vào `AGENTS.md`.

## 8. Trạng thái đợt nghiên cứu

Đã phân tích trace bằng `make perf-report` và đối chiếu source/ACK/callback, đọc các nguồn trên, rà workflow. Đợt này chỉ cập nhật tài liệu/quy ước làm việc, không sửa runtime, không thay wire, không chạy thêm GitHub Actions và không tạo IPA/RPK mới. Những phương án ở mục 5–7 chưa phải các thay đổi đã triển khai hay kết quả phần cứng đã đạt.

Lệnh tái lập báo cáo: `make perf-report RUN=E:/code/artifacts/map-latency-20261011 SESSION=4a699bb5-dfb4-4ea5-826e-7bd282da12d5` với Python được cấu hình theo môi trường. Báo cáo máy cho kết quả FAIL mục tiêu dưới một giây; đó là kết quả quan sát, không phải analyzer chạy lỗi.
