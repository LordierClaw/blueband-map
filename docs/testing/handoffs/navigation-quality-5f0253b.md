# Bàn giao chất lượng raster dẫn đường — 5f0253b

## Artifact

- IPA: `BlueBandMap-unsigned.ipa` — `0.5.7 (23)`, build bởi GitHub Actions iOS run `33600780548` từ `main` commit `5f0253b2b852c9c4c617e74937c447f1f48b1ca2`.
- RPK: `dev.lordierclaw.bluebandmap.band.debug.0.6.9.rpk` — `0.6.9 (24)`, build và verify bằng `make test-rpk` từ cùng commit.
- Bundle local `artifacts/handoff` chỉ giữ cặp IPA/RPK hiện tại; artifact 0.5.6/0.6.8 đã được thay thế.

## Những gì thay đổi

- Vietmap render snapshot heading-up ở scale 2 rồi chỉ downsample một lần bằng nội suy chất lượng cao về đúng khung truyền `212×520`. Camera vẫn xoay trước khi raster hóa nên route, đường và nhãn không còn bị xoay lại ở lớp bitmap chất lượng thấp.
- Encoder vẫn dùng bảng màu 16 màu và admission ladder hiện có. Payload gửi Band vẫn bị chặn cứng ở `8192 bytes`; ảnh nguồn chỉ được chấp nhận ở đúng 1× hoặc 2× và ảnh đầu ra luôn là PNG `212×520`.
- Preview trên iPhone đổi sang nội suy chất lượng cao để phản ánh sát hơn raster thực gửi Band.
- Marker bản thân đổi sang resource cache-busted `marker-cursor-v3.png`: cursor xanh đậm `#14804a`, không viền trắng, có tip/notch cùng nằm trên trục route giữa. Marker vẫn cố định ở lower-center `(106,374)` và hướng thẳng lên.
- Marker điểm đến ngoài viewport dùng margin riêng `2 px`, gần rìa hơn nhưng validator iOS/RPK vẫn yêu cầu toàn bộ chevron `24×24` nằm trong vùng nhìn thấy của màn hình cong.
- Tên đường được mở rộng tới `126 px`; phần chỉ đường tiếp tục không có panel/gradient background theo thiết kế đã duyệt.

## Kiểm tra tự động đã hoàn tất

- Chuỗi chuẩn `make clean && make bootstrap && make test && make lint && scripts/verify-no-secrets.sh && git diff --check`: pass.
- Local: Swift `161/161`, Band `26/26`, protocol-lab `19/19`; metadata, smoke và handoff tests đều pass.
- GitHub Actions tại commit `5f0253b`: iOS checks `33600780548`, Band package checks `33600780526`, Swift package checks `33600780549` và Repository checks `33600780523` đều success.
- IPA: checksum tải về trùng checksum do Actions tạo; ZIP hợp lệ, Mach-O arm64, bundle `dev.lordierclaw.bluebandmap`, version/build `0.5.7/23`, iOS tối thiểu `17.0`.
- RPK: ZIP hợp lệ, toolkit `2.0.5`, package `dev.lordierclaw.bluebandmap.band`, version/build `0.6.9/24`, `minAPILevel: 1`; resource cursor mới có mặt và mọi resource bắt buộc đều qua verifier.
- Test hồi quy giữ nguyên hai lỗi nghiêm trọng: payload vượt `8192 bytes` bị từ chối trước khi cấp phát/truyền; frame chỉ được publish sau khi ảnh và overlay đã được chuẩn bị nguyên tử. Đây là bằng chứng code/package, chưa thay thế kiểm tra trên Band thật.

## Manual test cơ bản

Hãy dừng xe hoặc nhờ hành khách quan sát thiết bị.

1. Gỡ bản RPK cũ nếu AstroBox còn giữ cache, cài `dev.lordierclaw.bluebandmap.band.debug.0.6.9.rpk`, rồi xác nhận AstroBox không báo `third-party app install failed: InstallFailed`.
2. Cài/mở IPA `0.5.7 (23)`, kết nối Band và chọn một tuyến có đoạn đầu chéo so với hướng Bắc, có tên đường và điểm đến ở xa.
3. Chờ frame đầu tiên. Trên iPhone không được xuất hiện `MAP_PAYLOAD_TOO_LARGE`; trên trạng thái ứng dụng không được xuất hiện `BAND_DISPLAY_FAILED`.
4. Kiểm tra route đầy đủ và tên đường trên Band: đường/nhãn phải rõ hơn sau khi map xoay heading-up, không bị co thành một đoạn ngắn hoặc lệch khỏi vị trí thực.
5. Kiểm tra marker bản thân: cursor xanh đậm, không viền trắng, không mất/lõm góc ngoài hình học đã duyệt; tip nằm đúng giữa route, marker cố định tại lower-center và hướng thẳng lên.
6. Chọn điểm đến ngoài viewport ở trái, phải và một góc trên. Chevron phải gần rìa hơn bản 0.6.8 nhưng còn nguyên vẹn, không bị cắt bởi mép cong.
7. Kiểm tra phần chỉ đường: tên đường tận dụng gần hết chiều rộng bên phải; không có panel hoặc gradient background; khoảng cách vẫn gọn theo `m`/`km`.
8. Di chuyển qua ít nhất một ngã rẽ. Map/route phải cập nhật theo hướng di chuyển trong khi marker bản thân vẫn cố định. Export debug log và xác nhận có `band.displayed`, không có `BAND_DISPLAY_FAILED` cho frame vừa kiểm tra.

Chỉ đánh dấu đạt trên Xiaomi Smart Band 10 sau khi hoàn thành các bước trên; compilation, simulator, test và CI không được tính là bằng chứng phần cứng.
