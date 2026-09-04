# Bàn giao sửa map đứng yên sau lần hiển thị đầu

iOS 0.5.17 (33). Giữ nguyên RPK 0.6.12 (27); không cần cài lại Band nếu đang ở bản này.

## Nguyên nhân trực tiếp

Log 0.5.16 (32) xác nhận Band đã hiển thị (`terminal=displayed`, ACK 18/18, transfer 4066 ms), GPS vẫn có 28 fix được nhận và tiến đến segment 7. Tuy vậy `displayedFixAgeMs` và `fixToDisplayMs` đều `none`.

RPK gửi ACK của `map.asset.end` khi file đã sẵn sàng, sau đó mới gửi `render.result` từ callback hoàn tất giải mã/hiển thị ảnh. Ở thứ tự này, iOS đã nằm trong `waitForResult`. Nhánh nhận kết quả cũ gọi `handleResult` trực tiếp, đặt trạng thái displayed, huỷ timeout và xoá `runContext`, nhưng **không resume continuation đang chờ**.

Hệ quả: `RouteCardRenderCoordinator.start` không trả về cho `AppModel.publish`; iPhone không gán `activeSceneID` và mốc thời gian frame. `sendNavigationUpdate` thoát vì chưa có scene; các GPS fix mới vẫn vào hàng đợi nhưng tác vụ refresh đầu không kết thúc để xử lý tiếp. Đây là lỗi điều phối bất đồng bộ phía iOS, không phải GPS dừng trong phiên log này.

Test cũ trả `render.result` ngay trong lúc gửi lệnh end, trước khi hàm ACK trả về. Nó chỉ chạy nhánh buffered nên bỏ sót thứ tự bình thường của RPK. Test mới đợi coordinator thực sự vào `waitingForBand` rồi mới trả kết quả, kiểm tra caller được giải phóng, ba map liên tiếp, kết quả trùng không ghi nhận hai lần; test AppModel cũng nhận kết quả muộn và kiểm tra hai frame theo GPS cùng các `nav.update`.

## Phạm vi sửa

Nhánh nhận kết quả trả kết quả cho tác vụ đang chờ; chính tác vụ đó hoàn tất xác nhận frame rồi trả quyền điều khiển cho AppModel. Kết quả tới trước khi đăng ký waiter được buffer, timeout được huỷ khi đánh thức waiter. Không sửa RPK, wire bytes, payload, UI/marker/route, renderer, lịch GPS hay chính sách API/cache.

## Kiểm tra một lượt

1. Ký/cài IPA mới, xác nhận **0.5.17 (33)**. Giữ RPK **0.6.12 (27)** và quyền Bluetooth + vị trí chính xác đã cấp. Kết nối và mở cùng tuyến kiểm tra.
2. Di chuyển/replay qua ít nhất 3 vị trí khác nhau. Phải có nhiều `band.displayed` và `nav.update`, mốc `fixToDisplayMs` hữu hạn, hướng dẫn/khoảng cách đổi theo tiến độ. Không dùng một frame đầu hoặc riêng `terminal=displayed` làm tiêu chí realtime.
3. Nếu bước 2 đạt, khoá iPhone và tiếp tục cùng tuyến 5 phút. Kiểm tra nhiều lần refresh, không lỗi payload/display; mục tiêu từng cập nhật cần thiết dưới 5000 ms. Nếu lỗi, dừng ở lỗi đầu và export log, không Start liên tục. Không thao tác khi lái xe.

Tiếp tục giới hạn bài kiểm tra ở một tuyến chính, tối đa 2 Route requests và dừng ở 200 style/tile requests nếu có bộ đếm provider; đây là ngân sách kiểm tra, không phải hard cap mới trong app. Reroute và radio thật vẫn cần số đo riêng.

## Bằng chứng

- [CI trước sửa](https://github.com/LordierClaw/blueband-map/actions/runs/33833940517), commit `89bbfc0`: hai test liên quan thất bại đúng dự kiến. Caller không được giải phóng trong cả ba lượt, AppModel không có frame thứ hai, không có mốc display và có 0 `nav.update`. Các test khác không có failure.
- Kết quả sau sửa và checksum được ghi sau khi xác minh. Chưa nghiệm thu bản sửa trên iPhone + Band; USB hiện nhận iPhone và xác nhận bản cài 0.5.16 (32), chưa phải bản sửa.
