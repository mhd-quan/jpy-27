# Đo trên máy — Phase 4–5

Những bước của Phase 4–5 cần app chạy thật: đo, chụp màn, duyệt thiết kế, thử trên máy. **Chỉ người dùng làm**,
trên máy thật, bản **Release**, mở từ màn hình chính (trừ khi bước ghi khác). Agent không có máy: không bước
nào ở đây đã được làm, và không ô nào được agent điền. Mỗi task chép bước của mình vào dưới tiêu đề của nó, đã
chỉnh theo code thật, kèm ô trống cho số hay kết luận. Bước đo một kịch bản ghi mã S1–S10 của
`docs/perf/2026-11-baseline.md`.

## 0.2 — Số đo: signpost, Chẩn đoán › Số đo, MetricKit

Bản Release của baseline commit, Instruments như `docs/perf/2026-11-baseline.md` § Cài Instruments.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | S1: trang chủ, chạm thẻ ngày → trang ngày | os_signpost (`tech.delphyra.jp27` / `perf`) có khoảng `push.today`, có event `first-frame` bên trong | |
| 2 | S2: tab Bản đồ, chạm ghim → sheet địa điểm | khoảng `sheet.place` có `first-frame` | |
| 3 | S7: Chi tiêu, chạm "Ghi chi" | khoảng `sheet.expense` có `first-frame` | |
| 4 | Ba bước trên, xem lời kết của khoảng | `settled`, kết thúc cùng lúc zoom dừng (không phải `cap` 1 giây sau khi trang hiện). Toàn `cap` nghĩa là UIKit không báo xong cho trang; ghi lại | |
| 5 | Mở và đóng nhanh vài sheet, vuốt về giữa chừng một trang đẩy, rồi dừng Instruments | mọi khoảng đều có lời kết (`settled`, `cap`, `replaced` hay `timeout`); không khoảng nào còn mở | |
| 6 | Sau ngày dùng đầu tiên (MetricKit gửi số mỗi ngày một lần; muốn thử ngay: bản Debug chạy từ Xcode, Debug › Simulate MetricKit Payloads), Cài đặt › Chẩn đoán › Số đo | có dòng "Theo ngày" và "Chuyển cảnh"; trước lần gửi đầu: "Chưa có số đo" | |
| 7 | Số đo › "Chia sẻ JSON", gửi sang máy tính | các file `metrics-….payload.json`, mở được, là JSON của MetricKit | |

## 4.1

## 4.2

## 4.3

## 5.8a

## 5.1a

## 5.1b

## 5.2

## 5.5

## 5.4

## 5.3

## 5.6

## 5.7

## 5.9

## 5.8b

## 6.2
