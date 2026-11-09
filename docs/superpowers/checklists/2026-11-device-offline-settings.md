# Kiểm trên máy — Dùng khi mất sóng, Cài đặt và log

Những bước không agent nào làm được: bản đồ offline thật của MapLibre, Chế độ máy bay, tắt hẳn app. Mỗi task của
kế hoạch `docs/superpowers/plans/2026-11-09-offline-and-settings.md` chép bước kiểm của mình vào đây, đã chỉnh theo
code thật; chưa bước nào được làm. Bản build: Release, mở từ màn hình chính, trừ khi bước ghi khác. Điền cột
**Kết quả** (Đạt / Không đạt, kèm điều thấy được).

## § 1 — Task 1: style của gói nằm trong app; gói Toàn tuyến

Trước khi tạo một gói, và mỗi lần mở app, app nạp style đóng trong app vào cơ sở dữ liệu của MapLibre dưới URL mà
gói ghi (`https://jpy27.delphyra.tech/map/jp27-light@<tên build>.json`); tên miền đó không cần trả lời. Nếu MapLibre
không đọc style đã nạp, gói sẽ hỏi tên miền đó và không bao giờ tải được: vùng ghi "Không kết nối được, đang thử
lại" dù có mạng. Khi đó cần phương án khác; đường lui là gắn lại tên miền cho Worker của site.

Làm trên bản cài mới (xoá app JP27 trước bước 1), để bước 5 chưa có ảnh bản đồ nào được lưu.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Có mạng (Wi‑Fi). Cài đặt › Dùng khi mất sóng › Nara › Tải. | Nara qua "Đang chuẩn bị…", "Đang tải · x %", tới "Đã tải · <dung lượng>". Không lúc nào ghi "Không kết nối được, đang thử lại" mà đứng ở 0 % (nếu có: MapLibre không đọc style đã nạp, xem đoạn trên). | |
| 2 | Bật Chế độ máy bay. Mở tab Bản đồ ở Nara, zoom từ 9 tới 16 (thu nhỏ tới cả vùng, phóng to tới phố). | Đủ đường, khối nhà, chữ ở mọi mức zoom đó. Nếu vùng vẫn báo không kết nối được: MapLibre không đọc style đã nạp; đường lui là gắn lại tên miền cho Worker. | |
| 3 | Tắt Chế độ máy bay. Tải một vùng lớn (Tokyo); khi tới khoảng 20 %, vuốt tắt hẳn app (app switcher). Bật Chế độ máy bay, mở app, vào Dùng khi mất sóng. Rồi tắt Chế độ máy bay. | Khi máy bay: Tokyo ghi "Chờ có mạng · x %". Tắt máy bay: Tokyo tải tiếp từ chỗ đã dừng tới "Đã tải", không báo lỗi style và không ghi "Không kết nối được, đang thử lại" khi đã có mạng. | |
| 4 | Có mạng. Tải "Toàn tuyến" (dòng đầu tiên của danh sách). Bật Chế độ máy bay, mở tab Bản đồ, thu nhỏ tới cả Kantō–Kansai. | "Toàn tuyến" tới "Đã tải · <dung lượng>" (vài MB, vài trăm ô). Khi máy bay: có nền bản đồ (bờ biển, đường lớn, tên thành phố) ở zoom 5–10, cả ở chỗ giữa các vùng. | |
| 5 | Vẫn Chế độ máy bay. Mở trang một ngày đi qua hai vùng (ví dụ ngày chuyển từ vùng này sang vùng kia) mà chưa mở lần nào trên bản cài này, nên ảnh bản đồ của nó chưa được lưu. | Ảnh bản đồ của ngày vẽ được, có nền (nhờ Toàn tuyến đã tải), không phải ô trống hay chỉ có đường đi trên nền trơn. | |
| 6 | Cố gắng tối đa, đạt cũng chứng minh ít: chỉ hỏng khi MapLibre đã đẩy style ra khỏi bộ nhớ đệm, mà không có cách bắt nó làm thế. Có mạng. Tải một vùng lớn chưa có (Kyoto, Uji), ở khoảng 20 % chạm vòng để dừng ("Tạm dừng · x %"). Đừng tắt app. Dùng bản đồ sống ở mức phố thật lâu, lướt nhiều khu ở các vùng khác (để bộ nhớ đệm khoảng 50 MB của MapLibre đầy và bỏ bớt đồ cũ). Quay lại, chạm vòng để tải tiếp. | Vùng tải tiếp tới "Đã tải", không ghi "Không kết nối được, đang thử lại" khi có mạng (trước khi chạm, app nạp lại style dưới URL của gói). | |
