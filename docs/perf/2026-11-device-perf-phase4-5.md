# Đo và kiểm trên máy — Phase 4–5

Những bước không agent nào làm được: đo bằng Instruments, nhìn animation, MetricKit sau một ngày dùng. Mỗi task của
Phase 4–5 chép bước của mình vào đây, dưới tiêu đề của task, đã chỉnh theo code thật.

**Điền gì.** Mỗi bước có ô kết quả: điền **Đạt / Không đạt**, hay con số, kèm ghi chú khi cần.

**Bản build.** Release, mở từ màn hình chính, trừ khi bước ghi khác. Product › Profile (⌘I) cũng build Release.

**Kịch bản.** Mã S1–S10 là mười kịch bản của [`2026-11-baseline.md`](2026-11-baseline.md):

| Mã | Kịch bản |
| --- | --- |
| S1 | Trang chủ → trang ngày |
| S2 | Bản đồ: ghim → sheet địa điểm |
| S3 | Lịch trình → Fuji |
| S4 | Fuji → điểm ngắm |
| S5 | Trang địa điểm: vuốt ảnh |
| S6 | Bản đồ: vuốt dòng thời gian |
| S7 | Chi tiêu: "Ghi chi" |
| S8 | Thẻ câu, xoay |
| S9 | Trang ngày: dấu tích |
| S10 | Mở app nguội |

Một bước đo kịch bản thì đo như file đó tả: 5 lần, lấy trung vị, so với bảng nền.

## Bước 1 — Task 0.2: mốc đo, Số đo, MetricKit

Bản Release ở baseline commit. Instruments: Animation Hitches + os_signpost (dòng Points of Interest), Attach vào JP27
đã mở từ màn hình chính.

| # | Bước | Đạt khi | Kết quả | Ghi chú |
| --- | --- | --- | --- | --- |
| 1 | Chạy S1, S2, S3, S4, S7 và phần mở thẻ của S8, mỗi cái một lần. | Mỗi lần chạm có đúng một khoảng `transition` ở Points of Interest, có sự kiện `first-frame`, kết thúc `settled`. Nhãn là `today → day`, `map → place`, `plan → fuji`, `fuji → fujiSpot`, `spend → expense`, `phrase`. | | |
| 2 | Cùng các lần ở bước 1, nhìn track Hitches. | Khung cuối của animation (zoom, sheet trồi lên, trang trượt vào) nằm trước cuối khoảng. Nếu animation còn chạy sau khi khoảng đã hết, ghi kịch bản và quãng còn lại (ms): mốc chờ 350/500 ms phải tăng. | | |
| 3 | Mở một sheet (S2) rồi vuốt đóng ngay, trong nửa giây. Mở lại. | Khoảng thứ nhất kết thúc `dismissed`. Lần mở lại có khoảng mới, kết thúc `settled`. | | |
| 4 | Chạy S5, S6, S9 và phần xoay của S8. | Các sự kiện `place.photo`, `map.fly`, `day.check`, `phrase.turn` hiện ở Points of Interest, mỗi hành động một lần. `map.fly` không hiện liên tục từng khung khi chỉ cuộn trong một mục. | | |
| 5 | Sau bước 1–4, mở Cài đặt › Chẩn đoán › Số đo. | Phần "Chuyển trang" có các nhãn ở bước 1, đúng số lần, có số ms. Bên dưới có số lần của các sự kiện ở bước 4. | | |
| 6 | Kiểm MetricKit: Xcode › Debug › Simulate MetricKit Payloads, khi app chạy từ Xcode. Hoặc dùng app một ngày, mở lại hôm sau. | Số đo › MetricKit có một dòng ngày: giật khi cuộn, giật khi chuyển động, mở app, các signpost. "Chia sẻ JSON" bấm được và gửi được file. Nếu sau hai ngày vẫn trống, xem Cài đặt › Quyền riêng tư & Bảo mật › Phân tích & Cải tiến: iOS có thể chỉ gửi khi bật chia sẻ với nhà phát triển (chưa kiểm). | | |
| 7 | Dùng app như thường vài phút. Zoom vào và ra ở thẻ ngày, sheet địa điểm, thẻ câu, nạp tiền, mua sắm. Vuốt lùi, chồng sheet lên sheet. | Mọi thứ chạy như bản trước Task 0.2. Không có gì khác ngoài dòng "Số đo" mới trong Chẩn đoán. | | |
| 8 | Đo nền S1–S10 theo `2026-11-baseline.md`. | Bảng "Kết quả" ở đó đã điền đủ. | | |
