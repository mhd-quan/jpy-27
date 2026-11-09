# Số đo nền — trước khi sửa phần mượt (Phase 4–5)

Phase 4–5 chỉ có nghĩa khi so được trước và sau trên cùng kịch bản. File này là bảng **trước**: đo trên bản
build của baseline commit, chưa có code nào của Phase 4–5. Chỉ người dùng đo, trên máy thật; agent không đo
và không điền ô nào ở đây.

Baseline commit: `a99614013cf7fe6fc6ef2a121737196c0b578491` (`a996140`, "Measure transitions: signposts from tap to
settled, MetricKit hitch ratio in Diagnostics, baseline"). CI "App builds" xanh, 0 warning.

Lấy đúng bản này để build, lúc nào cũng được (không cần đo trước khi Phase 4–5 tiếp tục):

```bash
git fetch origin && git switch --detach a99614013cf7fe6fc6ef2a121737196c0b578491
```

Đo xong thì quay về nhánh đang dùng (`git switch -`).

## Cách đo

1. **Bản build.** Bản **Release** từ đúng baseline commit trên (scheme `Run` đã là Release). Cài lên máy.
2. **Máy.** Sạc đầy, nhiệt độ bình thường (không vừa sạc nhanh, không để nắng), tắt Chế độ nguồn điện thấp,
   đóng các app khác.
3. **Mở app từ màn hình chính**, không mở từ Xcode. Instruments gắn vào app đang chạy (chọn máy, chọn tiến
   trình `JP27`), trừ S10.
4. **Mỗi kịch bản 5 lần**, giữ **trung vị** của mỗi cột. Giữa hai lần, quay lại đúng màn bắt đầu và chờ yên
   khoảng 2 giây.

## Cài Instruments

- Template **Animation Hitches**.
- Thêm instrument **SwiftUI** (bật View Body và View Properties).
- Thêm instrument **os_signpost**. Đọc dòng của subsystem `tech.delphyra.jp27`, category `perf`.
  - **Khoảng** (interval) mang tên của chuyển cảnh: `push.today`, `push.plan`, `push.talk`, `push.spend`
    cho một trang đẩy vào tab, và `sheet.place`, `sheet.ride`, `sheet.expense`, `sheet.atPlace`, `sheet.menuScan`,
    `sheet.listen`, `sheet.fujiFinder`, `sheet.fujiSpot`, `sheet.journal`, `sheet.settings` cho một sheet.
  - Khoảng bắt đầu lúc chạm (sheet: lúc app mở sheet; trang đẩy: lúc đường dẫn của tab dài thêm, ngay sau
    cú chạm).
  - Trong khoảng có **event** `first-frame`: trang đích vừa xuất hiện.
  - Lời kết của khoảng nói nó kết thúc ra sao:
    - `settled`: chuyển cảnh xong, đúng như mong đợi;
    - `cap`: trang đã xuất hiện 1 giây mà chưa nghe UIKit báo xong;
    - `replaced`: một chuyển cảnh khác bắt đầu trước;
    - `timeout`: 3 giây sau lúc chạm vẫn chưa xong.

    Lần đo nào kết thúc khác `settled` thì ghi chú lại.
  - Cùng các tên ấy cũng hiện trên log của MetricKit (category `perf`). Chỉ đọc dòng `tech.delphyra.jp27`.

## Đọc các cột

- **Chạm → khung đầu (ms):** từ đầu khoảng tới event `first-frame`. Kịch bản không có khoảng: từ cú chạm tới
  khung đầu tiên đổi trên track Animation Hitches.
- **Số hitch** và **tổng thời gian hitch (ms):** track Animation Hitches, trong khoảng signpost (từ đầu tới
  lời kết). Kịch bản không có khoảng: trong lúc thao tác, từ cú chạm/vuốt tới khi màn đứng yên.
- **Số lần body:** instrument SwiftUI › View Body, số lần body của view trang đích (cột "View đích") chạy
  trong cùng khoảng ấy.
- **Ảnh:** chụp cửa sổ Instruments (track Hitches, os_signpost, View Body) của một lần đo, cho S1–S5.

## Kịch bản

| Mã | Kịch bản | Signpost | View đích | Chạm → khung đầu (ms) | Số hitch | Tổng hitch (ms) | Số lần body | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | Trang chủ: chạm thẻ ngày giữa carousel → trang ngày zoom mở | `push.today` | `DayView` | | | | | |
| S2 | Tab Bản đồ: chạm ghim → sheet địa điểm | `sheet.place` | `PlaceView` | | | | | |
| S3 | Lịch trình → trang Fuji (Cẩm nang › Fuji) | `push.plan` | `FujiView` | | | | | |
| S4 | Trang Fuji → thẻ điểm ngắm (chạm một điểm trong danh sách) | `sheet.fujiSpot` | `FujiSpotPage` | | | | | |
| S5 | Trang địa điểm: vuốt 3 ảnh, dừng | — (cả cú vuốt) | `PlaceView` | | | | | |
| S6 | Tab Bản đồ: vuốt nhanh dòng thời gian qua 8 mục | — (cả cú vuốt) | `MapTab` | | | | | |
| S7 | Chi tiêu: chạm "Ghi chi" | `sheet.expense` | `ExpenseEditor` | | | | | |
| S8 | Sổ tay: thẻ câu toàn màn hình, xoay ngang/dọc (nút xoay trên thẻ) | — (từ chạm nút xoay tới khi đứng yên) | `TalkShowCard` | | | | | |
| S9 | Trang ngày: chạm dấu tích 5 lần | — (cả 5 lần chạm) | `DayView` | | | | | |
| S10 | Mở app nguội, trước chuyến | — (xem dưới) | `RootView` | | | | | |

**S10 (mở app nguội).** Tắt hẳn app (vuốt khỏi app switcher), chờ 10 giây, mở từ màn hình chính. Cột "Chạm →
khung đầu" là thời gian mở app. Thêm (không thay template trên): template **App Launch** của Instruments cho
thời gian tới khung đầu; và sau khi MetricKit gửi số (thường sau một ngày dùng), dòng "mở app" ở Cài đặt ›
Chẩn đoán › Số đo (trung vị của iOS). Ghi cả hai vào ô Ghi chú.

## Ảnh Instruments

| Mã | Ảnh |
| --- | --- |
| S1 | |
| S2 | |
| S3 | |
| S4 | |
| S5 | |

## Số đo trong app (MetricKit)

Sau ít nhất một ngày dùng bản baseline, Cài đặt › Chẩn đoán › Số đo:

| Ngày | Giật khi cuộn | Giật mọi lúc | Mở app (trung vị) |
| --- | --- | --- | --- |
| | | | |

| Chuyển cảnh | Trung vị (ms) | Số lần | Giật |
| --- | --- | --- | --- |
| `push.today` | | | |
| `push.plan` | | | |
| `sheet.place` | | | |
| `sheet.fujiSpot` | | | |
| `sheet.expense` | | | |

Nút "Chia sẻ JSON" ở cuối trang gửi bản gốc của MetricKit, để xem kỹ hơn trên máy tính.
