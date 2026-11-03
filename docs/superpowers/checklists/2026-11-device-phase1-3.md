# Kiểm trên máy — Phase 1–3

Những bước không agent nào làm được (AlarmKit reo thật, hai máy ghép sổ, GPS, nền, Instruments). Mỗi task
chép bước kiểm của mình vào đây, đã chỉnh theo code thật; Task 6.1 của plan chạy hết danh sách này trên
máy thật trước khi phát hành bản Phase 1–3. Bản build: Release, mở từ màn hình chính, trừ khi bước ghi
khác (công tắc Chẩn đoán chỉ có trong bản Debug).

## Task 1.1 — Báo thức: giữ cái còn cần, chỉ thay khi cái mới đã đặt

Bản **Debug** (các nút "Báo thức thử sau 2/5 phút" và "Báo thức trong hệ thống" ở Cài đặt › Chẩn đoán chỉ có
trong Debug), giờ thật (không chạy thử). AlarmKit không chạy trên simulator. Hai nút báo thức thử cùng đặt báo
thức cho một chuyến giả, theo đường của chuyến đang theo dõi (`.ride`: hỏi quyền, chỉ thay khi cái mới đã
đặt). Chúng **không** tái hiện lỗi báo thức theo lịch bị huỷ khi còn 45 giây: chỉ bước 7 (ngày đi thật) làm
được; logic đó do test TripKit `keepsWantedAlarmDueIn45Seconds` giữ.

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
4. **Mở app không làm tắt báo thức đang reo.** Bấm "Báo thức thử sau 2 phút", về màn hình chính và để nó reo.
   Trong lúc nó reo, mở app (từ nền) → vẫn reo tới khi bấm "Đã thức". Trong lúc reo, Cài đặt › Chẩn đoán ›
   "Báo thức trong hệ thống": ghi lại dòng nó hiện (mong đợi "đang reo 1"; nếu là "đang chờ" thì AlarmKit
   không báo trạng thái reo và app có thể huỷ nó, ghi rõ). Làm lại lần nữa, lần này vuốt tắt hẳn app trước
   phút 2 rồi mở app khi báo thức đang reo → vẫn reo tới khi bấm "Đã thức".
5. **Không có quyền thì app không bỏ gì.** Bấm "Báo thức thử sau 5 phút". Cài đặt iOS › JP27 › tắt Báo thức.
   Mở lại app (từ nền, rồi một lần sau khi vuốt tắt hẳn app). → Cài đặt › Chẩn đoán không có dòng "Lỗi báo
   thức gần nhất". Bật lại quyền trước phút 5 rồi mở lại app → báo thức vẫn reo ở phút 5 (nếu lúc không có
   quyền app đã bỏ nó, lần mở có quyền này sẽ huỷ nó như báo thức lạ). Nếu bước 3 cho thấy iOS gỡ báo thức khi
   tắt quyền, bước này không reo vì iOS; ghi lại.
6. **Chạy thử không đặt báo thức thật.** Cài đặt › Chuyến đi › Chạy thử: bắt đầu một lần chạy thử. Bấm
   "Báo thức thử sau 2 phút", và theo dõi một chuyến tàu trong lúc chạy thử nếu có. → Không báo thức nào reo.
   Kết thúc chạy thử.
7. **Báo thức theo lịch tàu (ngày đi thật, bản Release).** Tối hôm trước một chuyến tàu dài (≥ 25 phút, ví dụ
   Romancecar), mở app một lần. Hôm đó mở app khoảng 45 giây trước giờ báo thức (4 phút trước giờ tới ga). →
   Báo thức vẫn reo.
8. Cài đặt › Chẩn đoán: sau các bước trên không có dòng "Lỗi báo thức gần nhất". Có dòng nào thì chép nguyên
   văn vào báo cáo.

## Task 1.2 — Đặt lại nhắc giờ, geofence, báo thức thành một việc: chạy nền chờ nó xong, chạm và mở app dồn lại

Dòng "Đặt lại nhắc giờ, geofence, báo thức" ở Cài đặt › Chẩn đoán có trong mọi bản build: số lần đặt lại từ
lúc mở app, đọc khi trang Cài đặt mở ra (đóng rồi mở lại Cài đặt để thấy số mới). Số về 0 hay 1 giữa chừng là
iOS đã tắt app ở nền: làm lại bước đó. Bước 3 và 4 cần chạy app từ Xcode (debugger).

1. **Mở app trước chuyến chỉ đặt lại một lần** (bản Release, trước ngày đi, đã cho phép vị trí). Mở Cài đặt ›
   Chẩn đoán, ghi số ở dòng trên. Đóng Cài đặt, về màn hình chính, chờ vài giây, mở lại app, mở lại Cài đặt →
   số tăng đúng 1. Làm 3 lần. Tăng 2 thì ghi lại: vị trí mà app hỏi lúc mở (`requestLocation`) lại đặt lại thêm
   một lần.
2. **Chạm dấu tích không còn đặt geofence trên khung của nó** (Instruments › Time Profiler, bản Release qua
   Profile của Xcode, quyền vị trí Luôn luôn, trong một ngày của chuyến hay một lần chạy thử). Chạm dấu tích
   10 lần ở danh sách Hôm nay, mỗi lần cách nhau khoảng một giây. Trong call tree, dưới `AppModel.toggleDone`
   (khung của lần chạm) **không có** `LocationService.updateFences`, `CLLocationManager startMonitoring(for:)` /
   `stopMonitoring(for:)`, `NSUserDefaults setObject:forKey:` gọi từ `updateFences`, `ReminderPlanner`,
   `NotificationService.schedule`; chúng hiện khoảng 0,3 s sau, dưới `AppModel.reschedule`. **Còn được phép** trong
   khung của lần chạm: `Shared.snapshot` (UserDefaults của widget) và `WidgetCenter reloadTimelines` khi điểm kế
   tiếp đổi, `savePace` (UserDefaults) khi đánh dấu một điểm tới bằng đi bộ, và lần lưu SwiftData.
3. **Background refresh chỉ trả về khi đã đặt xong.** Đặt breakpoint ở `AppModel.reschedule` và ở dòng
   `publishSnapshot(force: true)` cuối `AppModel.refreshInBackground`. Về màn hình chính cho app vào nền, bấm Pause
   trong Xcode, rồi trong LLDB:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"tech.delphyra.jp27.refresh"]`,
   rồi Continue. → Breakpoint ở `reschedule` chạm trước, rồi breakpoint cuối `refreshInBackground`, cả hai *trước*
   dòng log "task completed" của BGTaskScheduler trong console.
4. **Chạm rồi rời app ngay vẫn đặt xong ở nền.** Đặt breakpoint ở `AppModel.finishRescheduleInBackground`. Chạm
   dấu tích rồi vuốt về màn hình chính ngay (trong khoảng 0,3 s) → breakpoint chạm. Mở lại app, chờ vài giây, rời
   app mà không chạm gì → breakpoint không chạm.
5. **"Đã tới" trên màn hình khoá đặt lại ở nền** (chạy từ Xcode, quyền vị trí Luôn luôn, trong một ngày của chuyến
   hay một lần chạy thử, quán ăn kế tiếp của lịch hôm nay chưa tích). Đặt hai breakpoint dạng log (Action: lệnh
   `bt 3`, tick "Automatically continue after evaluating actions"): một ở `AppModel.finishRescheduleInBackground`,
   một ở dòng `requestReschedule()` trong closure `location.onMoved` (`AppModel.init`). Ở nền, mỗi khi iOS báo một
   vị trí mới (thay đổi đáng kể) mà máy đã đi 500 m hay đã qua 10 phút từ lần trước (lần đầu từ lúc mở app luôn
   tính), `onMoved` chạy, gọi `finishRescheduleInBackground` và thêm một lần đặt lại: đếm số lần nó chạm. Mở Cài
   đặt › Chẩn đoán, ghi số lần đặt lại. Khoá máy. Tới gần quán đó (hoặc Debug › Simulate Location trong Xcode, một
   điểm ngay ở quán) cho tới khi thông báo của quán hiện ra với nút "Đã tới". Trên màn hình khoá, giữ thông báo,
   bấm "Đã tới". Mở khoá, mở app: quán đã tích. Nhắc giờ thuộc quán đó (nếu có, ví dụ giờ đặt bàn còn ở phía
   trước) không reo vào giờ của nó. Mở lại Cài đặt → số tăng **2 + số lần `onMoved` chạm**: 1 cho "Đã tới", 1 cho
   lần mở lại app (ít hơn chỉ khi hai lần đánh thức tới cùng lúc và gộp vào một lần chạy). **Đạt** khi đường "Đã
   tới" tự nó cho đúng một lần đặt lại ở nền: trong log, đúng một lần `finishRescheduleInBackground` có backtrace
   đi qua `AppModel.notificationAction`; các lần còn lại đi qua closure `onMoved`. Để so: khoá rồi mở lại mà không
   bấm gì → tăng 1 + số lần `onMoved` chạm, và không lần nào đi qua `notificationAction`.
6. **Tàu tới ga khi máy khoá** (chỉ kiểm được vào ngày đi: cần một chuyến tàu được theo dõi thật, với Live
   Activity; trước đó ghi "chưa kiểm, ngày đi"). Nối Xcode, đặt hai breakpoint log như bước 5. Theo dõi chuyến,
   ghi số lần đặt lại, khoá máy trước ga cuối. Trên tàu, khi máy khoá, vị trí vẫn được theo dõi và iOS báo thay
   đổi đáng kể liên tục, nên `onMoved` sẽ chạm nhiều lần: đếm chúng. Khi tàu tới ga → những chặng của chuyến đã
   tích (mở app để xem), và mở lại Cài đặt → số tăng 2 + số lần `onMoved` chạm (tới ga ở nền, mở lại app; ít hơn
   chỉ khi hai lần đánh thức gộp làm một). **Đạt** khi đường tới ga tự nó cho đúng một lần đặt lại ở nền: đúng
   một lần `finishRescheduleInBackground` có backtrace đi qua `AppModel.rideArrived`. Không nối Xcode thì không
   đếm được `onMoved`: chỉ kiểm các chặng đã tích, con số không dùng để kết luận.
7. **Di chuyển đáng kể ở nền** (significant change) không ép được trên máy: iOS tự quyết khi nào báo. Đường này
   chỉ được kiểm bằng đọc code: `LocationService.locationManager(_:didUpdateLocations:)` gọi `moved(to:)` chỉ khi
   app không ở trên màn hình → `onMoved` → `AppModel.requestReschedule` rồi `finishRescheduleInBackground`.

## Task 1.3 — Tiền: một validation cho mọi đường vào, tổng không bao giờ trap

File thử: `docs/superpowers/fixtures/overflow.csv` (2 dòng ngày 20/10/2026: dòng 2 là ¥9.223.372.036.854.775.807,
dòng 3 là ¥1). Chép file sang máy (AirDrop vào Tệp, hoặc iCloud Drive). Không chạy thử (rehearsal): chạy thử ghi
vào sổ riêng của nó.

1. **Gộp file có số tiền vô lý.** Chi tiêu › menu "…" › "Gộp file sổ chi" › chọn `overflow.csv`. **Đạt** khi alert
   hiện đúng "Đã thêm 1 khoản, bỏ qua 1 dòng không hợp lệ (dòng 2)." và tab Chi tiêu vẫn mở: vòng tròn "Đã chi"
   cộng thêm ¥1 (sổ trống thì bằng ¥1), ngày 20/10 trong sổ có một khoản ¥1 "· máy kia". Gộp lại lần nữa → "Không
   thêm khoản nào, bỏ qua 1 dòng không hợp lệ (dòng 2)." Tắt hẳn app (vuốt khỏi đa nhiệm), mở lại, vào Chi tiêu → không crash. Xoá khoản ¥1 sau khi kiểm.
2. **Xuất rồi gộp lại chính file của mình.** Menu "…" › "Xuất sổ chi (CSV)" › Lưu vào Tệp. Gộp file vừa lưu →
   "Sổ đã có đủ các khoản trong file." (không "cập nhật" khoản nào: file không bao giờ mới hơn khoản trên máy).
   Mở file trong Numbers: cột `luc` vẫn dạng `2026-10-20T03:01:00.000Z`, chữ tiếng Việt đọc đúng.
3. **Khoản đã lưu từ trước mà không hợp lệ** (chỉ có khi máy đã gộp một file như vậy bằng bản trước 1.3; bản
   này không lưu được dòng nào như thế, nên thường ghi "không có dữ liệu cũ, bỏ qua"). Nếu có: đầu sổ có mục
   "Khoản cần sửa" với khoản đó, chân mục "Số tiền ngoài khoảng ¥1–¥9.999.999 nên không được cộng vào tổng nào…";
   vòng tròn, hai ví, Ngân sách, Nhật ký ngày đó không cộng nó. Bấm "Sửa" → bàn phím bắt đầu từ ¥0, nút lưu tắt
   cho tới khi gõ số; gõ 1200, lưu → khoản về đúng ngày trong sổ, mục "Khoản cần sửa" biến mất. Với khoản khác,
   "Xoá" → mất khỏi sổ. App không tự xoá khoản nào.
4. **Bàn phím.** Ghi chi: gõ 9999999 rồi thêm một số → không đổi, không rung; "000" trên ¥10.000 → không đổi.
   Dán một ghi chú rất dài (hơn 500 ký tự) → ô ghi chú dừng ở 500 ký tự.
5. **Hai máy** (khi kiểm Task 1.5): máy A có một khoản không hợp lệ cũ (bước 3) → đồng bộ với máy B → máy B không
   nhận khoản đó, sổ B không crash; `LedgerSync.rejected` trên B = 1 (Task 1.5 hiện ra; trước đó chỉ xem được bằng
   debugger).

## Task 1.4 — Lưu bền: lỗi ghi tới UI, không còn lưu im lặng

Bản **Debug**: công tắc "Giả lỗi lưu" và nút "Thử ghi trùng chỉ số" ở Cài đặt › Chẩn đoán chỉ có trong Debug.
Dùng giờ thật, không chạy thử, trừ khi bước ghi khác.

Khi "Giả lỗi lưu" bật:
- Mọi lần lưu báo lỗi "Giả lỗi lưu (Chẩn đoán)" cho tới khi tắt. Mở lại app thì công tắc tắt.
- Lỗi xảy ra trước khi ghi gì, nên trên máy không có gì đổi.
- Hai bản chép dự phòng không bị ảnh hưởng: gộp sổ phụ, và chép sang sổ chạy thử.

Tắt công tắc sau mỗi bước.

**Đạt chung** cho mọi bước có lỗi lưu:
- Alert "Chưa lưu được" hiện ở chỗ đang nhìn, tức trên sheet đang mở nếu có, không phải sau sheet.
- Nội dung alert là "<việc>: Giả lỗi lưu (Chẩn đoán)".
- Máy rung lỗi (`fail`), không rung `done`.
- Thứ vừa chạm trở về như trước.

1. **Sửa một khoản chi.**
   - Bật "Giả lỗi lưu". Chi tiêu › chạm một khoản trong sổ › đổi số tiền › Lưu.
   - **Đạt** khi alert "Khoản chi: …" hiện **trên** editor, editor không đóng, và số vừa gõ còn nguyên.
   - "Thử lại" → alert hiện lại (vẫn lỗi). "Để sau" → alert đóng, editor vẫn mở.
   - "Huỷ" → khoản trong sổ vẫn số cũ, không hiện số chưa từng được ghi.
   - Làm lại với nút "+" (Ghi chi). Sau "Huỷ", sổ không có khoản mới.
   - Tắt công tắc, sửa lại rồi Lưu → editor đóng, rung `done`, sổ có số mới.
2. **Rút tiền và Đã mua.**
   - Công tắc bật. Chạm ví tiền mặt › chọn ¥10.000 › Lưu.
     - **Đạt** khi alert "Rút tiền: …" hiện trên sheet và sheet ở lại. Sau "Huỷ", ví không đổi.
   - Chi tiêu › Mua sắm › chạm dấu tròn một món › Lưu.
     - **Đạt** khi alert "Khoản chi: …" hiện trên sheet.
     - Sau "Huỷ", món không được đánh dấu, và sổ không có khoản ¥ nào cho món đó: món và khoản đi cùng một lần ghi.
3. **Đánh dấu điểm.**
   - Công tắc bật. Lịch trình › một ngày › chạm dấu tròn của một điểm.
     - **Đạt** khi alert "Đánh dấu điểm: …" hiện, có "Thử lại" và "Để sau".
     - Dấu tròn trở lại rỗng, máy rung `fail`, không rung `done`.
     - "Thử lại" → alert hiện lại.
   - Tắt công tắc, chạm lại → dấu ở lại, rung `done`.
   - Bỏ một dấu khi công tắc bật → alert "Bỏ đánh dấu: …", dấu còn nguyên.
   - Nhấn giữ một điểm › "Bỏ điểm này" → alert "Bỏ điểm: …", điểm không mờ đi.
4. **Alert trên sheet, không phải sau nó.**
   - Công tắc bật. Bản đồ › chạm một địa điểm có trong lịch để mở thẻ địa điểm (sheet).
   - Chạm biểu tượng lịch → trang ngày mở trong sheet. Chạm dấu tròn một điểm.
   - **Đạt** khi alert hiện trên sheet đó, ngay lúc chạm.
   - **Không đạt** nếu không có alert nào, hoặc alert chỉ hiện sau khi đóng sheet. Khi đó ghi lại, vì nghĩa là
     `Presentation.swift` không đưa được alert lên sheet trên cùng.
5. **Hôm nay, trong lúc chạy thử.**
   - Bật chạy thử ở một ngày đi, rồi bật công tắc.
   - Chạm nút dấu tích "Đã tới" của thẻ điểm kế → alert, không rung `done`, thẻ không đổi.
   - Nếu có băng trễ giờ, chạm "Bỏ …" → alert "Bỏ điểm theo gợi ý: …", không rung `warn`, băng còn đó.
6. **Gộp file khi lưu lỗi.**
   - Công tắc bật. Gộp `docs/superpowers/fixtures/overflow.csv` (xem Task 1.3).
   - **Đạt** khi alert hiện "Chưa lưu được khoản nào trong file: Giả lỗi lưu (Chẩn đoán)", không bao giờ "Đã thêm 1 khoản".
   - Sổ không đổi.
7. **Xoá và khoản trùng.** Công tắc bật, rồi:
   - Vuốt xoá một khoản → alert "Xoá khoản chi: …", khoản còn trong sổ.
   - Nếu có thẻ "Có thể ghi trùng", chạm một trong hai nút → alert "Xoá khoản chi: …" hoặc "Giữ cả hai khoản: …".
     Thẻ còn đó, không rung `done`.
   - Mua sắm › bỏ dấu một món đã mua → alert "Bỏ đã mua: …". Món còn dấu, khoản của nó còn trong sổ.
   - Đồng bộ › "Không phải trùng" (chỉ khi có mục "Đã gộp vì ghi trùng") → alert "Khoản bị gộp nhầm: …" trên sheet Đồng bộ.
8. **Hai máy** (kiểm cùng Task 1.5).
   - Ghép A và B, đồng bộ một lần. Bật công tắc trên **B**. Sửa một khoản trên A.
   - **Đạt** khi dòng đồng bộ trên B (dưới hai ví) ghi "<tên A> ở gần · chưa lưu được sổ chi: Giả lỗi lưu (Chẩn đoán)".
     - Không có "đã đồng bộ" với giờ mới. Sheet Đồng bộ trên B ghi cùng dòng đó.
     - Sổ B không có thay đổi của A.
   - Tắt công tắc trên B. Sửa thêm một khoản trên A → B ghi "đã đồng bộ lúc <giờ mới>" và có cả hai thay đổi.
   - Trước Task 1.5, chỉ tắt công tắc thì không đủ để A gửi lại. Task 1.5 thêm ack/nack và gửi lại.
9. **SwiftData khi một lần ghi chạm `#Unique`.**
   - Vì sao cần: chưa biết SwiftData xử lý thế nào; bước này cho biết hai pha sắp lại index của 1.4 có cần không, và
     Task 2.1 cần gì khi bỏ unique theo index.
   - Bản Debug, công tắc **tắt**. Cài đặt › Chẩn đoán › "Thử ghi trùng chỉ số". Chép nguyên văn hai dòng hiện ra:
     "A↔B đổi chỗ: …" và "A chồng lên B: …".
   - Đọc kết quả:
     - "lỗi, không lưu (…)": SwiftData từ chối. Trước 1.4, lần sửa index đó bị nuốt và lặp lại mỗi lần mở app.
     - "lưu được, còn 2 dòng A@1 B@0" (đổi chỗ): đổi chỗ trong một lần ghi được.
     - "lưu được, còn 1 dòng …": SwiftData **gộp** hai dấu làm một, tức mất dấu im lặng. Hai pha là bắt buộc.
   - Nút tự dọn hai dòng thử (ngày "debug.unique", không thuộc lịch nào). Dòng "dọn không được" thì ghi lại.
10. **Dấu đi theo điểm sau khi lịch đổi** (cần build lại).
    - Bản Debug cài trên máy. Đánh dấu 3 điểm liền nhau ở cuối một ngày.
    - Trong `src/data/days.ts`, thêm một điểm vào đầu ngày đó, chạy `npm run ios:data`, rồi build và cài đè (dữ liệu giữ nguyên).
    - **Đạt** khi ba dấu vẫn ở đúng ba điểm cũ, nay mỗi điểm lùi xuống một dòng.
      - Không có alert "Chưa lưu được" khi mở.
      - Mở lại app lần nữa, dấu vẫn đúng.
    - Bỏ điểm vừa thêm, build lại để trả lịch về như cũ.
11. **Chỗ chưa che (ghi nhận, không phải lỗi).**
    - Lỗi lưu xảy ra ở nền, ví dụ một lần ghé (visit) hay "Đã tới" trên màn hình khoá đánh dấu điểm.
    - Nếu lúc đó đang mở một sheet riêng của Chi tiêu ("Sửa khoản chi", "Rút tiền", "Nạp Suica", "Đồng bộ"), alert chỉ
      hiện sau khi đóng sheet đó.
    - Nếu gặp mà alert không bao giờ hiện, ghi lại.
