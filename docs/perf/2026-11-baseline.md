# Số đo nền — app trước Phase 4–5

Phase 4–5 làm app mượt hơn; chỉ biết có mượt hơn không khi so được trước/sau trên cùng kịch bản, cùng máy, cùng
cách đo. Tài liệu này là phần **trước**: mười kịch bản S1–S10, cách đo, và bảng để điền. Số do người dùng đo trên
máy và điền vào; ô trống là chưa đo. Các task sau dùng lại mã S1–S10 trong
[`2026-11-device-perf-phase4-5.md`](2026-11-device-perf-phase4-5.md).

Baseline commit: (điền sau)

Bản đo được build từ đúng commit này: nó là app cũ, chỉ thêm mốc đo (Task 0.2, "Bước 1"). Không có gì chạy khác đi.

## Mốc đo trong app

App đặt mốc bằng signpost (subsystem `tech.delphyra.jp27`, category Points of Interest), nên chúng hiện ngay trong
Instruments, ở dòng **Points of Interest** của instrument os_signpost.

**Chuyển trang.** Mỗi lần chạm mở một trang là một khoảng `transition`:

- **Bắt đầu** lúc chạm, nhãn `nơi chạm → trang`, ví dụ `today → day`, `map → place`.
- Sự kiện **`first-frame`** ngay trước khung đầu của trang đích (`onAppear` của trang).
- **Kết thúc** khi chuyển xong. Lời kết thúc nói vì sao: `settled` (đã xong), `dismissed` (trang đóng trước khi xong),
  `superseded` (chạm khác tới trước khi trang hiện), `expired` (trang hiện sau hơn 3 giây, không ghép).

SwiftUI không báo lúc một push, một sheet hay một zoom xong. "Xong" là một mốc chờ cố định tính từ khung đầu:

- 350 ms cho trang đẩy vào;
- 500 ms cho sheet, thẻ câu, và zoom từ thẻ ngày ở trang chủ.

Vì vậy **độ dài khoảng không phải số đo của animation.** Cái giá thật của transition đọc ở track Hitches trong khoảng
đó.

**Sự kiện** (một khoảnh khắc, không có độ dài):

| Sự kiện | Khi nào |
| --- | --- |
| `map.fly` | bản đồ được yêu cầu bay tới một chỗ (mỗi mục mà dòng đọc của dòng thời gian chạm tới, mỗi lần chạm) |
| `place.photo` | trang địa điểm: dừng ở một ảnh khác |
| `phrase.turn` | thẻ câu: chạm nút xoay |
| `day.check` | chạm dấu tích một điểm |

**Cài đặt › Chẩn đoán › Số đo** (có trong mọi bản, cả Release) cho số tự đo để đối chiếu:

- **Chuyển trang:** từ lúc mở app, theo từng nhãn, có số lần và trung vị của chạm → khung đầu và chạm → xong.
- **Số lần** của mỗi sự kiện.
- **MetricKit:** báo cáo hằng ngày của iOS.
- **Chia sẻ JSON:** gửi các báo cáo MetricKit đi.

## Cách đo

1. **Bản build.** Mở `ios/JP27.xcodeproj` ở đúng baseline commit. Product › Profile (⌘I) build bản Release.
2. **Máy.** Sạc đầy, nhiệt độ bình thường (không vừa sạc nhanh, không để nắng). Tắt Chế độ nguồn điện thấp. Đóng các app
   khác.
3. **Mở app** từ màn hình chính, không từ Xcode. Trong Instruments, chọn tiến trình JP27 đang chạy (Attach), không
   Launch.
4. **Template:**
   - Template **Animation Hitches**.
   - Thêm instrument **SwiftUI**: View Body, View Properties.
   - Thêm instrument **os_signpost**, nếu template chưa có dòng Points of Interest.
5. **Mỗi kịch bản 5 lần.** Ghi số của từng lần, lấy trung vị điền vào bảng. Giữa các lần, quay về đúng điểm xuất phát
   và chờ khoảng 2 giây cho yên.
6. **Đọc số:**
   - **Chạm → khung đầu (ms):** từ đầu khoảng `transition` tới sự kiện `first-frame` của nó. Dùng Inspection Range:
     chọn đúng khoảng đó.
   - **Số hitch, tổng thời gian hitch (ms):** trên track Hitches của Animation Hitches, tính trong khoảng `transition`.
     Ở S5, S6, S8 (phần xoay) và S9 không có khoảng: tính từ sự kiện đầu tiên tới 1 giây sau sự kiện cuối.
   - **Số lần body chạy:** của view trang đích, ở SwiftUI › View Body, trong cùng khoảng. Tên view trong bảng dưới.
     Chỉ đếm view đó, không đếm modifier bọc quanh nó.
7. **Ảnh chụp Instruments** cho S1–S5. Một ảnh mỗi kịch bản, lần gần trung vị nhất, thấy cả dòng Points of Interest
   và Hitches. Lưu cạnh file này: `docs/perf/2026-11-baseline/S1.png` … `S5.png`.

## Mười kịch bản

| Mã | Kịch bản | Bắt đầu từ | Mốc | View trang đích |
| --- | --- | --- | --- | --- |
| S1 | Trang chủ: chạm thẻ ngày giữa carousel → trang ngày zoom mở | Hôm nay, trước chuyến, thẻ ngày 6 ở giữa | `transition` `today → day` | `DayView` |
| S2 | Tab Bản đồ: chạm ghim → sheet địa điểm | Bản đồ, một điểm dừng đang được chọn (chạm lần đầu chỉ bay tới; chạm lại ghim đó mở sheet) | `transition` `map → place` | `PlaceView` |
| S3 | Lịch trình → trang Fuji | Lịch trình › Cẩm nang › Fuji | `transition` `plan → fuji` | `FujiView` |
| S4 | Trang Fuji → thẻ điểm ngắm | Trang Fuji, chạm một điểm ngắm trong danh sách | `transition` `fuji → fujiSpot` | `FujiSpotPage` |
| S5 | Trang địa điểm: vuốt 3 ảnh, dừng | Trang một địa điểm có từ 4 ảnh | 3 × `place.photo` | `PlaceView` |
| S6 | Tab Bản đồ: vuốt nhanh dòng thời gian qua 8 mục | Bản đồ, bảng ở giữa, đầu ngày | các `map.fly` (ghi cả số lần) | `MapTab` |
| S7 | Chi tiêu: chạm "Ghi chi" | Chi tiêu | `transition` `spend → expense` | `ExpenseEditor` |
| S8 | Sổ tay: thẻ câu toàn màn hình, xoay ngang/dọc | Sổ tay, chạm một câu, rồi xoay ngang và dựng lại | `transition` `phrase`; 2 × `phrase.turn` | `TalkShowCard` |
| S9 | Trang ngày: chạm dấu tích 5 lần | Một trang ngày | 5 × `day.check` | `DayView` |
| S10 | Mở app nguội, trước chuyến | Vuốt JP27 khỏi đa nhiệm, chờ 10 giây, mở từ màn hình chính | không có mốc trong app; template **App Launch** | — |

S10 không có mốc trong app. iOS có thể khởi động app ở nền (vị trí, làm mới nền), nên một khoảng "từ lúc khởi động"
có thể kéo dài nhiều giờ. Đo bằng template **App Launch** (5 lần, thời gian tới khung đầu). Số của MetricKit đọc ở
Số đo, dòng "Mở app" (trung vị một ngày dùng thật).

## Kết quả — trung vị của 5 lần

Ngày đo: · Máy: · iOS: · Pin lúc đo:

| Mã | Chạm → khung đầu (ms) | Số hitch | Tổng hitch (ms) | Body trang đích (lần) | Ảnh | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | | | | | | |
| S2 | | | | | | |
| S3 | | | | | | |
| S4 | | | | | | |
| S5 | — | | | | | |
| S6 | — | | | | — | số `map.fly`: |
| S7 | | | | | — | |
| S8 | | | | | — | |
| S9 | — | | | | — | |
| S10 | (App Launch, ms:) | | | — | — | |

"—": không áp dụng (kịch bản không có chạm mở trang, hay không cần ảnh).

## Số đo trong app, cùng buổi đo

Chép từ Cài đặt › Chẩn đoán › Số đo, ngay sau khi đo xong S1–S9, không mở lại app giữa chừng.

| Nhãn | Số lần | Khung đầu (ms) | Xong (ms) |
| --- | --- | --- | --- |
| `today → day` | | | |
| `map → place` | | | |
| `plan → fuji` | | | |
| `fuji → fujiSpot` | | | |
| `spend → expense` | | | |
| `phrase` | | | |

## MetricKit — một tuần dùng thật

iOS gửi mỗi ngày một báo cáo; app giữ 14 báo cáo gần nhất trong `Caches/metrics/`. Cuối tuần, mở Số đo, chép các dòng,
rồi bấm "Chia sẻ JSON" để lưu các file. Caches có thể bị iOS dọn khi máy đầy, nên đừng để quá lâu.

| Ngày | Giật khi cuộn (ms/s) | Giật khi chuyển động (ms/s) | Mở app (ms) | Ghi chú |
| --- | --- | --- | --- | --- |
| | | | | |
| | | | | |
| | | | | |
| | | | | |
| | | | | |
| | | | | |
| | | | | |
