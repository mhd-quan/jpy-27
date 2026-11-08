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

Đo (bước 1–3): bản Release, Instruments như `docs/perf/2026-11-baseline.md`. Bước 2b và 4–9: bản Debug được, cần
Cài đặt › Chẩn đoán › "Ảnh bản đồ đã lưu" và "So khung bản đồ" (chỉ có trong bản Debug). Ảnh bản đồ nằm trong
`Caches/MapSnapshots`: `<frameID>-<hash>.jpg` và `.json` đi kèm (chỗ các ghim trên ảnh).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | S1: trang chủ, chạm thẻ một ngày đã mở trước đó trong lần chạy này → trang ngày | khung đầu của trang (event `first-frame` trong `push.today`) đã có ảnh bản đồ, không có ô xám | |
| 2 | S1 lần đầu cho một ngày chưa từng mở (hoặc sau khi xoá app): xem os_signpost | event `map.snapshot` (bản đồ vẽ ảnh) nằm sau lời kết `settled` của `push.today`, hoặc ≥ 400 ms sau `first-frame`; không có `map.snapshot` thứ hai cho cùng trang | |
| 2b | Mở trang một khách sạn có ảnh chưa tải (lần đầu, có mạng), trong lúc zoom | không có `map.snapshot` trong lúc zoom; nếu màu trang tới giữa chừng và đổi sáng/tối, ảnh bản đồ đổi một lần sau khi zoom dừng | |
| 3 | S9: trang ngày, chạm dấu tích 5 lần | không có `map.snapshot` nào trong 5 lần chạm; ghim của điểm vừa đánh dấu đổi xám ngay trên ảnh | |
| 4 | Chẩn đoán › "Ảnh bản đồ đã lưu": ghi số; mở trang ngày, đánh dấu 5 điểm, bỏ đánh dấu; quay lại Chẩn đoán | số ảnh không đổi (một ảnh cho mỗi khung) | |
| 5 | Chẩn đoán › "So khung bản đồ", vài ngày (cả ngày đi bộ ngắn), cả "Bản đồ thật chồng lên ảnh"; chụp màn | ảnh và bản đồ thật đóng khung giống hệt: cùng tâm, cùng mức phóng, đường và ghim trùng nhau | |
| 6 | Trang khách sạn › "Quanh khách sạn": chạm bản đồ, kéo ngay | ảnh ở yên tới khi bản đồ thật vẽ xong rồi mờ đi, không có khung trống hay xám; kéo được ngay từ lần chạm đầu | |
| 7 | Như bước 6 ở chế độ máy bay (vùng chưa tải) | ảnh rời đi chậm nhất khoảng 3 giây sau khi chạm | |
| 8 | Duyệt thiết kế, sáng và tối: trang ngày có vài điểm đã đánh dấu; so ghim đã ghé trên ảnh với tab Bản đồ cùng ngày; so ảnh cũ (trước bản này) với ảnh mới | ghim đã ghé trên ảnh đọc như trên bản đồ thật (xám, viền, số trắng; viền dày hơn khoảng 1 pt, số là font hệ thống); nút "kéo" trên nền thẻ đục, không còn kính mờ. Ghi nhận xét | |
| 9 | Mở lại app sau khi đã mở nhiều trang (thư mục quá 40 MB), hoặc ngay sau khi cài bản này lên bản cũ | Chẩn đoán › "Ảnh bản đồ đã lưu" không còn "ảnh kiểu cũ" và dưới 40 MB | |

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
