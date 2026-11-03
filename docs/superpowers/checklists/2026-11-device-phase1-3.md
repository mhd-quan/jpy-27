# Kiểm trên máy — Phase 1–3

Những bước không agent nào làm được (AlarmKit reo thật, hai máy ghép sổ, GPS, nền, Instruments). Mỗi task
chép bước kiểm của mình vào đây, đã chỉnh theo code thật; Task 6.1 của plan chạy hết danh sách này trên
máy thật trước khi phát hành bản Phase 1–3. Bản build: Release, mở từ màn hình chính, trừ khi bước ghi
khác (công tắc Chẩn đoán chỉ có trong bản Debug).

## Task 1.1 — Báo thức: giữ cái còn cần, chỉ thay khi cái mới đã đặt

Bản **Debug** (nút "Báo thức thử sau 2/5 phút" ở Cài đặt › Chẩn đoán chỉ có trong Debug), giờ thật (không
chạy thử). AlarmKit không chạy trên simulator. Hai nút cùng đặt báo thức cho một chuyến giả, theo đường của
chuyến đang theo dõi (hỏi quyền, chỉ thay khi cái mới đã đặt).

1. **Báo thức sát giờ không bị huỷ khi mở lại app.** Cài đặt › Chẩn đoán › "Báo thức thử sau 2 phút" (cho
   phép báo thức nếu được hỏi). Về màn hình chính, mở lại app ở khoảng giây 75. → Báo thức reo ở phút thứ 2.
   Bấm "Đã thức". Làm lại, lần này vuốt tắt hẳn app (app switcher) rồi mở lại ở giây 75 → vẫn reo (app đọc
   lại báo thức đã lưu, không coi nó là báo thức lạ để huỷ).
2. **Thay thế chỉ khi cái mới đã đặt.** Bấm "Báo thức thử sau 2 phút", rồi ngay sau đó "Báo thức thử sau
   5 phút". → Chỉ một báo thức reo, ở phút thứ 5; phút thứ 2 im.
3. **Quyền bị tắt thì cái cũ vẫn còn.** Bấm "Báo thức thử sau 2 phút". Cài đặt iOS › JP27 › tắt Báo thức.
   Quay lại app, bấm "Báo thức thử sau 5 phút" (dời hơn 2 phút: app thử đặt cái mới và bị từ chối). → Báo
   thức phút 2 vẫn reo. Không reo thì thử riêng phần của iOS: bật lại quyền, đặt "2 phút", tắt quyền, không
   bấm gì thêm — nếu vẫn không reo, iOS gỡ báo thức của app khi tắt quyền (không phải lỗi app); ghi lại.
   Bật lại quyền sau bước này.
4. **Chạy thử không đặt báo thức thật.** Cài đặt › Chuyến đi › Chạy thử: bắt đầu một lần chạy thử. Bấm
   "Báo thức thử sau 2 phút", và theo dõi một chuyến tàu trong lúc chạy thử nếu có. → Không báo thức nào reo.
   Kết thúc chạy thử.
5. **Báo thức theo lịch tàu (ngày đi thật, bản Release).** Tối hôm trước một chuyến tàu dài (≥ 25 phút, ví dụ
   Romancecar), mở app một lần. Hôm đó mở app khoảng 45 giây trước giờ báo thức (4 phút trước giờ tới ga). →
   Báo thức vẫn reo.
6. Cài đặt › Chẩn đoán: sau các bước trên không có dòng "Lỗi báo thức gần nhất", trừ khi iOS không cho đọc
   danh sách báo thức lúc quyền tắt (bước 3: dòng "Đọc báo thức: …"). Có dòng nào thì chép nguyên văn vào báo cáo.
