# Đo map realtime trên iPhone và Smart Band — T01–T07

Mục tiêu: chạy cùng tuyến GPS đã cố định, ghi đúng các thao tác thực tế và giữ đủ bằng chứng để so baseline với candidate. Đây là hướng dẫn chạy thiết bị; kết quả unit test, dry-run hoặc CI không thay thế kết quả iPhone/Smart Band.

## Chuẩn bị một lần

1. Ghi phiên bản/build iOS app, phiên bản/code RPK, iOS, firmware Band, mức pin, trạng thái sạc, quyền vị trí, chế độ tiết kiệm pin và cấu hình thời gian tắt màn Band. Giữ điều kiện giống nhau giữa baseline và candidate.
2. Cắm iPhone bằng USB vào Linux. Đảm bảo máy đã Trust, Developer Mode/DVT sẵn sàng; Band mở app BlueBand. Không bật ứng dụng fake GPS khác.
3. Mở terminal trong thư mục công cụ; kiểm tra đúng iPhone ngay trước mỗi lượt chạy:

   ```bash
   cd /home/hainn/blue/code/blueband-map-route-test
   idevice_id -l
   udid="$(idevice_id -l | head -n 1)"
   ```

   Nếu có nhiều iPhone, gán `udid` đúng máy cần đo. Không đưa UDID đầy đủ, AuthKey hoặc API key vào ghi chú chia sẻ.

4. Bật **Đo hiệu năng** trước khi Start; để **Hiện số khung khi quay video** tắt nếu không quay. Chuẩn bị đồng hồ bấm giờ (video là tùy chọn); ghi trạng thái khóa iPhone và ngủ/thức Band cùng mốc thời gian. CSV của công cụ chỉ là **tọa độ theo lịch phát**, không phải iPhone đã nhận GPS hoặc Band đã hiển thị.
5. Khi hướng dẫn nói **Export debug log**, chọn **Performance trace (.jsonl)** để lấy toàn bộ số đo; xuất thêm **Log tóm tắt (.txt)** khi gặp lỗi. Không chỉ gửi log tóm tắt vì bộ nhớ này giới hạn 120 dòng. Mỗi lượt dùng tên CSV mới. Giữ cùng nhau CSV, GPX, `*.run.json`, các bản **Export debug log**, video/ghi chú. Ghi case ID, run ID của GPS và session ID của app khi có trong bản xuất. Một lượt GPS có thể chứa nhiều phiên điều hướng app, nhất là T04/T05.

## Trình tự bắt buộc trước mỗi ca

1. Dừng phiên điều hướng cũ nếu còn. Chọn case rồi chạy lệnh tương ứng bên dưới. Không thay fixture hoặc seed giữa hai build.
2. Terminal hiện **PREPARE** trong 90 giây: GPS đứng yên tại điểm đầu của fixture. Trong 90 giây này, trên iPhone nhấn **Kết nối**, chờ mục **Handshake** hiển thị **Đã xác thực**.
3. Nhập/chọn điểm đến `20.9943658398093,105.78633688906575`, nhấn **Bắt đầu điều hướng**. Chờ Band hiện bản đồ đầu tiên và marker vị trí; ghi thời điểm thấy bản đồ.
4. Khi terminal in **RUN t=0**, bắt đầu đồng hồ cho ca. Mọi mốc `t=` bên dưới đều tính từ RUN, không tính từ lúc gõ lệnh hoặc nhấn Start.
5. Nếu RUN bắt đầu mà Band chưa có bản đồ đầu tiên: ghi **SETUP FAIL**, nhấn **Dừng điều hướng**, **Export debug log**, rồi Ctrl+C tại terminal. Giữ bằng chứng, khắc phục và chạy lại tên mới; không coi lượt này là số đo hiệu năng hợp lệ. Không chờ map lên giữa RUN rồi đổi lại `t=0`.

Ở cuối tuyến, terminal hiện **FINISHED** nhưng vẫn giữ GPS cuối. Luôn nhấn **Dừng điều hướng** và **Export debug log** trước, sau đó mới Enter để xóa GPS. Nếu ca kết thúc sớm, cũng Stop/export trước rồi Ctrl+C. Lỗi chương trình hoặc Ctrl+C sẽ cố dừng/wait DVT rồi clear GPS; không dùng Ctrl+C trước khi Stop trong lượt đo bình thường.

## T01 — Cả tuyến, iPhone foreground

```bash
python3 fake_gps_route.py play --test-session --case-id T01 --udid "$udid" \
  --seed 20260903 --log "runs/T01-$(date -u +%Y%m%dT%H%M%SZ).csv"
```

1. Làm đủ trình tự PREPARE ở trên. Giữ iPhone mở app, màn hình sáng suốt ca; ghi cấu hình ngủ/thức của Band.
2. Từ RUN `t=0` đến cuối tuyến, quan sát map/marker đổi vị trí, hướng rẽ, độ trễ thấy được, khung bị đứng, nhấp nháy hoặc mất marker. Ghi mốc lỗi chính xác; không suy ra map đã hiển thị chỉ từ terminal GPS.
3. Với fixture và seed mặc định, RUN dài 357 giây, có 358 điểm. Khi **FINISHED**, nhấn **Dừng điều hướng**, **Export debug log**, lưu bằng chứng T01, rồi Enter.

## T02 — Khóa iPhone ở giây 20

```bash
python3 fake_gps_route.py play --test-session --case-id T02 --udid "$udid" \
  --seed 20260903 --log "runs/T02-$(date -u +%Y%m%dT%H%M%SZ).csv"
```

1. PREPARE như trên; RUN `t=0` bắt đầu với iPhone foreground.
2. `t=20`: khóa màn hình iPhone bằng nút nguồn; ghi mốc thực tế. Giữ iPhone khóa đến cuối tuyến, quan sát Band và ghi các khoảng map đứng/mất cập nhật.
3. Khi **FINISHED**, mở khóa iPhone, nhấn **Dừng điều hướng**, **Export debug log**, rồi Enter. Ghi việc mở khóa có khiến map cập nhật dồn hay phục hồi hay không.

## T03 — Khóa/mở iPhone và ngủ/thức Band

```bash
python3 fake_gps_route.py play --test-session --case-id T03 --udid "$udid" \
  --seed 20260903 --log "runs/T03-$(date -u +%Y%m%dT%H%M%SZ).csv"
```

1. PREPARE, rồi bắt đầu đồng hồ ở RUN.
2. `t=30`: khóa iPhone.
3. `t=60`: cho màn Band ngủ/tắt; ghi mốc tắt thực tế. Dùng thao tác che màn nếu thiết bị đã hỗ trợ/cấu hình; nếu phải chờ timeout thì ghi đúng độ lệch.
4. `t=80`: đánh thức Band, tức 20 giây sau mốc ngủ mục tiêu. iPhone vẫn khóa. Ghi thời gian tới map đầu tiên sau wake và map có phản ánh vị trí mới hay không. Nếu ngủ thực tế khác `t=60`, giữ khoảng ngủ thực tế 20 giây và ghi cả hai mốc.
5. `t=120`: mở khóa iPhone, đưa app về foreground.
6. `t=150`: khóa iPhone lần nữa.
7. `t=180`: mở khóa, nhấn **Dừng điều hướng**, **Export debug log**, rồi Ctrl+C tại terminal. Ghi thời điểm Stop thực tế nếu thao tác mở khóa gây trễ.

## T04 — Stop/Start ba lần trong cùng lượt GPS

```bash
python3 fake_gps_route.py play --test-session --case-id T04 --udid "$udid" \
  --seed 20260903 --log "runs/T04-$(date -u +%Y%m%dT%H%M%SZ).csv"
```

1. PREPARE, giữ iPhone foreground. Không dừng hoặc khởi động lại công cụ GPS giữa các phiên app.
2. `t=45`: **Dừng điều hướng**, ngay lập tức **Export debug log** và lưu tên T04-session-1. Đợi đủ 5 giây tính từ Stop, mục tiêu `t=50`: **Bắt đầu điều hướng** với cùng điểm đến.
3. `t=90`: **Dừng điều hướng**, **Export debug log** thành T04-session-2. Đợi 5 giây, mục tiêu `t=95`: **Bắt đầu điều hướng**.
4. `t=135`: **Dừng điều hướng**, **Export debug log** thành T04-session-3. Đợi 5 giây, mục tiêu `t=140`: **Bắt đầu điều hướng**.
5. `t=180`: **Dừng điều hướng**, **Export debug log** thành T04-session-4, rồi Ctrl+C.
6. Ghi thời gian map đầu tiên của từng Start, session ID tương ứng và có map/marker cũ xuất hiện lại sau Stop hay không. Nếu xuất log mất hơn 5 giây, ghi thời gian Start thực tế và đánh dấu lệch lịch; không ghi khống mốc mục tiêu.

Phải xuất sau **từng Stop**. App chỉ giữ ba phiên gần nhất, nên chờ cuối ca mới xuất có thể mất phiên đầu. Giữ mọi bản export kể cả khi chúng chứa phiên trùng nhau.

## T05 — Mất kết nối và kết nối lại

```bash
python3 fake_gps_route.py play --test-session --case-id T05 --udid "$udid" \
  --seed 20260903 --log "runs/T05-$(date -u +%Y%m%dT%H%M%SZ).csv"
```

1. PREPARE, giữ iPhone foreground.
2. `t=60`: nhấn **Ngắt kết nối** trong app. Giữ nguyên cáp USB để GPS tiếp tục. Ghi thời điểm app báo ngắt kết nối và phiên điều hướng dừng.
3. Chờ 15 giây. `t=75`: nhấn **Kết nối**, chọn Band, mở RPK nếu cần, đợi **Handshake — Đã xác thực**. Ghi thời gian xác thực xong.
4. **Export debug log** cho phiên vừa bị ngắt. Nhấn lại **Bắt đầu điều hướng** thủ công, cùng điểm đến; ghi mốc Start thực tế.
5. Quan sát thêm 60 giây tính từ lúc bản đồ mới xuất hiện: dữ liệu cũ/cập nhật dồn và tính liên tục sau phục hồi. Nếu quá 90 giây không xác thực/hiện map mới, dừng và lưu lỗi.
6. **Dừng điều hướng**, **Export debug log** cho phiên mới, rồi Ctrl+C.

Hành vi hiện tại là disconnect sẽ dừng navigation. Ca này kiểm tra reconnect + Start thủ công; không đánh giá tự resume và không ghi việc cần Start lại là lỗi ngoài yêu cầu.

## T06 — Chạy liên tục 30 phút trong một phiên

```bash
python3 fake_gps_route.py play --test-session --case-id T06 --udid "$udid" \
  --seed 20260903 --minimum-speed-kph 4 --maximum-speed-kph 4 \
  --log "runs/T06-$(date -u +%Y%m%dT%H%M%SZ).csv"
```

1. PREPARE như trên, rồi giữ **một phiên điều hướng app duy nhất** trong 30 phút. Tại RUN `t=30`, khóa iPhone, giữ khóa đến `t=1800`; mở khóa để dừng. Đánh thức Band ở các mốc quan sát nếu cần, không mở lại RPK. Không Stop/Start hoặc lặp lại tuyến giữa chừng.
2. Tuyến mặc định 25–45 km/h chỉ dài 357 giây. Với 4 km/h, cùng fixture dài 3298 giây, đủ vượt 30 phút mà không ghép/lặp tuyến.
3. Tại RUN `t=300,600,900,1200,1500`, ghi pin, nhiệt cảm nhận, map có còn cập nhật và các quãng đứng/mất khung; không restart để “làm mới” phiên.
4. `t=1800`: nhấn **Dừng điều hướng**, **Export debug log**, sau đó Ctrl+C. Không chờ FINISHED và không clear GPS trước khi dừng app.

## T07 — Lặp trên candidate

1. Giữ trọn bằng chứng baseline T01–T06. Cài build candidate theo quy trình bàn giao riêng; ghi lại version/build app và version/code RPK thực tế.
2. Chạy lại T01–T06 theo đúng thứ tự, cùng fixture, seed, tốc độ, mốc thao tác, iPhone/Band và cấu hình nguồn/màn hình. Dùng `--case-id T07-T01` đến `T07-T06` và tên CSV mới tương ứng. Riêng T07-T06 vẫn dùng hai cờ tốc độ 4 km/h.
3. Đối chiếu từng cặp ca, không gộp foreground với locked hoặc phiên bị setup fail. Ghi cải thiện/hồi quy, dữ liệu thiếu và mọi lệch lịch.

## Ghi kết quả và xử lý lỗi

Mỗi ca ghi: PASS/FAIL/INCOMPLETE/SETUP FAIL; case/run/session ID; giờ UTC bắt đầu; mốc thao tác thực tế; thời gian bản đồ đầu tiên; độ trễ fix→Band khi log đủ bằng chứng; các khoảng không có khung mới; lỗi render/transfer/disconnect; liên kết bộ bằng chứng. Mục tiêu realtime là fix→Band dưới 1 giây (1000 ms); không thay số đo này bằng khoảng GPS→terminal hoặc tốc độ gửi gói.

Chỉ kết luận đạt khi có log app/Band và quan sát thiết bị hỗ trợ. Thiếu ACK hiển thị hoặc thiếu log phải ghi thiếu bằng chứng; không mặc định PASS. Ghi rõ các lỗi `map payload too large`, `band display failed`, marker mất hoặc map không cập nhật khi khóa màn.

Kiểm tra `*.run.json`: `outcome` phải phản ánh completed/interrupted hoặc lỗi thực tế; `resetOutcome` phải là `succeeded` sau lượt chạy thật. Các ca kết thúc sớm bằng Ctrl+C bình thường có `outcome: interrupted`; đây không tự động là FAIL của app. `outcome: running` sau khi tiến trình chết là bằng chứng chưa hoàn tất. Nếu reset thất bại, sau khi chắc chắn app đã Stop, chạy:

```bash
printf '\n' | /home/hainn/.local/bin/pymobiledevice3 developer dvt simulate-location clear \
  --userspace --udid "$udid"
```

Ghi kết quả clear thủ công vào ghi chú, không sửa sidecar để biến một reset thất bại thành thành công. Dry-run không tác động thiết bị, không chờ 90 giây hoặc Enter; nó chỉ kiểm tra/generate lịch và không chứng minh khả năng realtime trên phần cứng.

## Bộ kết quả cần gửi và cách đọc

Mỗi ca giữ một thư mục riêng, ví dụ `runs-evidence/T02-20260919/`, gồm:

- Bản export **Performance trace** gốc, các file CSV/GPX/`*.run.json` cùng lượt GPS.
- `notes.txt`: phiên bản hai app, firmware, pin đầu/cuối; mốc thao tác thực tế; lỗi quan sát được. Nếu crash, giữ log còn lại và ghi thời điểm; mở app lại để export trước khi Start thêm phiên.
- Log tóm tắt khi lỗi; video nếu có. Không bắt buộc quay video cho mọi ca.

Bạn có thể gửi nguyên thư mục này để tôi phân tích. Nếu tự tạo báo cáo trên Linux:

1. Sao chép đúng bản export cần đọc thành `navigation.jsonl` trong thư mục ca (giữ bản gốc). Với T04/T05, giữ mỗi lần export trong thư mục con riêng; **không nối các export trùng phiên**.
2. Chạy từ repo map:

   ```bash
   cd /home/hainn/blue/code/blueband-map
   make perf-report RUN=/duong/dan/tuyet/doi/runs-evidence/T02-20260919
   ```

3. Mở `report.md` để xem các session ID. Vì export giữ ba phiên gần nhất, chọn session đúng lượt Start và chạy lại:

   ```bash
   make perf-report RUN=/duong/dan/tuyet/doi/runs-evidence/T02-20260919 SESSION=session-id-can-doc
   ```

4. Kết quả gồm `report.md` (kết luận và mốc lỗi), `summary.json` (thống kê máy đọc được), `timeline.csv` (timeline/correlation từng sự kiện). Ba file output được ghi lại khi chạy lệnh lần nữa; file input được giữ nguyên.

Thời gian khởi động được báo riêng. GPS 1 Hz không đòi hỏi khoảng giữa hai khung nhỏ hơn 1 giây: cần đo độ trễ **từ timestamp GPS tới xác nhận khung từ Band**. Đây là xác nhận ứng dụng, chưa phải đo pixel vật lý. File/node là bộ đếm tài nguyên quan sát được; không dùng chúng để khẳng định RAM native an toàn. Log thiếu/hỏng, mất sự kiện hoặc session chưa kết thúc phải được giữ trạng thái thiếu bằng chứng.
