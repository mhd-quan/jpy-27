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
   nhận khoản đó, sổ B không crash; dòng đồng bộ trên B kết thúc bằng "· không nhận 1 khoản" (Task 1.5 bước 5 có
   cách tạo một khoản như vậy mà không cần bản cũ).

## Task 1.4 — Lưu bền: lỗi ghi tới UI, không còn lưu im lặng

Bản **Debug**: mục chọn "Giả lỗi lưu" và nút "Thử ghi trùng chỉ số" ở Cài đặt › Chẩn đoán chỉ có trong Debug.
Dùng giờ thật, không chạy thử, trừ khi bước ghi khác.

"Giả lỗi lưu" có ba lựa chọn:
- **Tắt**: lưu như thường. Mở lại app thì luôn về Tắt.
- **Lần lưu tới**: chỉ lần lưu kế tiếp báo lỗi "Giả lỗi lưu (Chẩn đoán)", rồi tự về Tắt.
- **Mọi lần lưu**: lần lưu nào cũng báo lỗi, cho tới khi chọn Tắt.

Trong các bước dưới, "bật công tắc" là chọn **Mọi lần lưu**, "tắt công tắc" là chọn **Tắt**.
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
8. **Hai máy** (kiểm cùng Task 1.5, bước 1 ở đó).
   - Ghép A và B, đồng bộ một lần. Bật công tắc trên **B**. Sửa một khoản trên A.
   - **Đạt** khi dòng đồng bộ trên B (dưới hai ví) ghi "Chưa lưu được sổ chi của <tên A>: Giả lỗi lưu (Chẩn đoán)".
     - Không có "Đã đồng bộ" với giờ mới. Sheet Đồng bộ trên B ghi cùng dòng đó.
     - Sổ B không có thay đổi của A.
   - Đưa A ra xa (hoặc tắt hẳn app trên A, rồi mở lại app trên B).
     - **Đạt** khi B ghi "Đã đồng bộ với <tên A> lúc <giờ>" với giờ của lần đồng bộ **trước đó**, không phải giờ lúc lưu lỗi.
     - Nếu đã mở lại app trên B, chọn lại Mọi lần lưu **trước** khi đưa A lại gần.
   - Đưa A lại gần, rồi tắt công tắc trên B, không sửa gì thêm → trong khoảng 15 giây B ghi "Đã đồng bộ với <tên A> lúc
     <giờ mới>" và sổ B có thay đổi của A: từ Task 1.5, A gửi lại tới khi B báo đã lưu.
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
    - Cũng vậy với những thứ app không mở qua chồng sheet của nó: thẻ câu nói toàn màn hình của Nghe và dịch
      (`fullScreenCover` trong `TalkShared.swift`), màn chọn file khi gộp sổ chi, và bảng chia sẻ (sổ chi, file cứu dữ liệu).
      Alert có thể chỉ hiện sau khi đóng chúng.
    - Nếu gặp mà alert không bao giờ hiện, ghi lại.
12. **Nhật ký đang mở khi một lần lưu lỗi.**
    - Vì sao cần: lần lưu lỗi lấy lại mọi thứ chưa ghi (`rollback`), kể cả các điểm vị trí (Trace) đang chờ tự lưu, mà
      Nhật ký đọc qua `@Query`.
    - Đi bộ một quãng (vài phút, có vị trí) để có điểm vị trí mới chưa lưu. Hôm nay › Nhật ký, để trang mở.
    - Bật công tắc (Mọi lần lưu). Trên trang ngày, chạm dấu tròn một điểm → alert "Đánh dấu điểm: …".
    - Quay lại Nhật ký.
    - **Đạt** khi app không crash và Nhật ký không có dòng hay đường đi ma (một chỗ ghé hay đoạn đường không có thật,
      hay biến mất khi mở lại trang).
    - Ghi lại Nhật ký hiện gì: đoạn đường vừa đi còn hay mất một khúc cuối.
13. **"Lần lưu tới" rồi "Thử lại".**
    - Chọn **Lần lưu tới**. Chi tiêu › "+" (Ghi chi) › gõ ¥500 › Lưu.
    - **Đạt** khi alert "Khoản chi: Giả lỗi lưu (Chẩn đoán)" hiện trên editor, và editor còn số ¥500.
    - "Thử lại" → lưu được: editor đóng, rung `done`.
    - Sổ có **đúng một** khoản ¥500 mới, không phải hai.
    - Cài đặt › Chẩn đoán › "Giả lỗi lưu" đã tự về **Tắt**.

## Task 1.5 — Đồng bộ sổ chi có xác nhận: "Đã đồng bộ" chỉ khi máy kia đã lưu

Hai máy A và B cài bản này, ghép với nhau, mở JP27 ở gần nhau, đồng bộ đang bật. B (và C ở bước 6) cài bản
**Debug** để có "Giả lỗi lưu" (Task 1.4). Không chạy thử, trừ bước 3. "Dòng đồng bộ" là dòng dưới hai ví ở tab Chi
tiêu; sheet Đồng bộ (chạm dòng đó) › mục "Bây giờ" ghi cùng chữ.

Chữ mong đợi:
- Đã xong: "Đã đồng bộ với <tên> lúc <giờ>" (hôm khác: "… lúc <giờ> ngày <ngày>/<tháng>"). Biểu tượng hai mũi tên
  vòng khi máy kia đang ở gần.
- Đang gửi, máy kia chưa báo đã lưu: "<tên> ở gần · đang đồng bộ".
- Máy kia không lưu được: "<tên máy kia> chưa lưu được: <lỗi>". Máy này không lưu được: "Chưa lưu được sổ chi của
  <tên máy kia>: <lỗi>". Cả hai có tam giác đỏ thay cho biểu tượng thường.

1. **Lỗi lưu trên B, sửa trên A.**
   - Cả hai đang ghi "Đã đồng bộ với <tên máy kia> lúc <giờ>". Trên **B** bật "Giả lỗi lưu" › Mọi lần lưu.
   - Trên **A** sửa số tiền một khoản › Lưu.
   - **Đạt** khi, trong vài giây:
     - A ghi "<tên B> chưa lưu được: Giả lỗi lưu (Chẩn đoán)", B ghi "Chưa lưu được sổ chi của <tên A>: Giả lỗi lưu
       (Chẩn đoán)", cả hai có tam giác đỏ;
     - không máy nào có "Đã đồng bộ" với giờ mới; sổ B chưa có số mới.
   - Để vậy 30 giây: hai dòng giữ nguyên, app không chậm đi (A gửi lại mỗi 15 giây, không liên tục).
   - Trên B chọn "Giả lỗi lưu" › Tắt, không sửa gì thêm.
   - **Đạt** khi trong khoảng 15 giây cả hai ghi "Đã đồng bộ với <tên máy kia> lúc <giờ mới>", tam giác đỏ mất, sổ B có
     số mới.
2. **Chế độ máy bay.**
   - Sửa khi không có mạng:
     - Cả hai đã đồng bộ. Trên A bật Chế độ máy bay; ở Trung tâm điều khiển xem Wi‑Fi và Bluetooth **đều tắt** (iPhone
       nhớ nếu trước đây từng bật lại Wi‑Fi trong chế độ máy bay).
     - Chờ dòng của A thôi ghi "ở gần" (vài giây), rồi sửa một khoản trên A.
     - Tắt Chế độ máy bay trên A, không sửa gì thêm.
     - **Đạt** khi trong khoảng 30 giây khoản vừa sửa sang B, và cả hai ghi "Đã đồng bộ với <tên máy kia> lúc <giờ
       mới>". Nếu sau 1 phút A vẫn chưa thấy B ở gần, đưa JP27 trên A ra nền rồi mở lại, và ghi lại.
   - Gửi mà chưa được xác nhận:
     - Cả hai đã đồng bộ. Trên A sửa một khoản › Lưu, rồi **ngay** (trong 1 giây) bật Chế độ máy bay trên **B**.
     - Nhìn A cho tới khi A thôi ghi "ở gần". **Đạt** khi A ghi "Đã đồng bộ" với giờ mới **chỉ nếu** sổ B (vẫn trong
       chế độ máy bay) đã có số mới. Sổ B chưa có thì A ghi "<tên B> ở gần · đang đồng bộ", rồi khi mất kết nối "Đã
       đồng bộ với <tên B> lúc <giờ cũ>". Ghi lại trường hợp nào xảy ra.
     - Tắt Chế độ máy bay trên B. **Đạt** khi trong khoảng 30 giây sổ B có số mới, và cả hai ghi "Đã đồng bộ … lúc
       <giờ mới>".
3. **Chạy thử.**
   - Trên A bắt đầu chạy thử (Cài đặt › Chuyến đi › Chạy thử). **Đạt** khi A ghi "Đồng bộ tạm dừng trong lúc chạy thử";
     B, sau vài giây, ghi "Đã đồng bộ với <tên A> lúc <giờ cũ>".
   - Ghi một khoản trên A (vào sổ chạy thử), và sửa một khoản trên B.
   - **Đạt** khi B không có khoản của sổ chạy thử, và sổ chạy thử trên A không có thay đổi của B.
   - Kết thúc chạy thử. **Đạt** khi trong khoảng 30 giây cả hai ghi "Đã đồng bộ … lúc <giờ mới>": sổ thật của A có thay
     đổi của B, B vẫn không có khoản chạy thử.
4. **Máy còn bản cũ** (chỉ khi có sẵn một máy cài bản trước Task 1.5; làm máy B).
   - **Đạt** khi A ghi "Đã gửi cho <tên B> · chờ máy kia cập nhật app để xác nhận", không bao giờ "Đã đồng bộ" với
     giờ mới khi B ở gần; khoản sửa trên A sang B và ngược lại như trước; B (bản cũ) hiện như trước.
5. **Khoản máy kia không nhận.**
   - Trên A: Cài đặt (iPhone) › Cài đặt chung › Ngày & Giờ › tắt "Đặt tự động", đặt ngày **sau 2 ngày**. Mở JP27, ghi
     một khoản ¥100. Khoản này mang ngày sau 2 ngày, nên B (giờ đúng) không nhận.
   - **Đạt** khi trong khoảng 15 giây:
     - B ghi "Đã đồng bộ với <tên A> lúc <giờ> · không nhận 1 khoản", và sheet Đồng bộ › "Bây giờ" có thêm dòng
       "Không nhận 1 khoản trong sổ của <tên A>: số tiền, ghi chú hay ngày không hợp lệ.";
     - A ghi "Đã đồng bộ với <tên B> lúc <giờ>" (không có tam giác đỏ): B đã lưu mọi thứ nó nhận.
   - Để vậy 30 giây: hai dòng giữ nguyên.
   - Trên A xoá khoản ¥100, rồi bật lại "Đặt tự động". **Đạt** khi sau lần đồng bộ kế, B thôi ghi "· không nhận 1
     khoản".
6. **Ba máy** (chỉ khi có máy thứ ba C, bản Debug, ghép với A).
   - A, B, C mở JP27 ở gần nhau. Nếu B hay C hỏi ghép với nhau, bấm "Để sau". Trên **C** bật "Giả lỗi lưu" › Mọi lần
     lưu. Sửa một khoản trên A.
   - **Đạt** khi A ghi "<tên C> chưa lưu được: Giả lỗi lưu (Chẩn đoán)" dù B đã lưu: dòng nói về máy tệ nhất, không
     ghi "Đã đồng bộ" khi còn một máy chưa lưu.
   - Trên C chọn Tắt. **Đạt** khi trong khoảng 15 giây A ghi "Đã đồng bộ với … lúc <giờ mới>".

## Task 2.1c — Mỗi mục có ID riêng: dấu đã đi, điểm bỏ, "Đã tới", geofence, widget

**Quy tắc phát hành (bắt buộc).** Bản này đổi một lần các dấu đã đi và điểm bỏ cũ sang ID, theo lịch của chính
bản này. Phép đổi chỉ đúng khi lịch là lịch mà các dấu đó được ghi theo. Vì vậy bản phát hành mang thay đổi này
**không được** đồng thời:
- thêm hay bỏ mục ở một ngày có nơi lặp lại (ngày 1: RESOL Akihabara; ngày 8: wargo Gion);
- đổi `line`, `from`, `to`, `via` hay `path` của một chặng: đổi cái nào cũng đổi `leg.id`
  (`<line>.<from>.<to>.<hash via, path>`), tức tên cũ `move:…` mà dấu cũ của chặng đó mang, dù ID của mục
  (`m:<from>><to>`) có khi giữ nguyên.
Những sửa đó để bản sau.

**Máy thử, xoá app trước.** Làm trên một máy thử, không phải máy dùng cho chuyến: xoá app JP27 trước khi cài bản
cũ. Lý do: cờ "sổ thật đã đổi" (`records.ids`) nằm trong App Group, cài đè (kể cả cài bản cũ đè bản mới) không xoá
nó. Máy nào đã chạy một bản từ ab6aaff trở đi mà không xoá app sẽ giấu những dấu bản cũ ghi sau đó (đúng như thiết
kế), và bước kiểm báo hỏng dù code đúng. Xoá app cũng xoá sổ ghi chép và sổ chi trên máy đó.

**Một chu kỳ cũ → mới.** Làm A rồi B liền một mạch, đúng một lần cài bản cũ và một lần cài đè bản mới. Muốn làm
lại thì xoá app và bắt đầu lại từ A.
- **Bản cũ**: build từ commit **de66fb4**, Release. Không dùng 88adbea: bản đó đã ghi ID cho dấu mới nên không thử
  được phép đổi.
- **Bản mới**: build của task này, Debug (bước B4 cần "Giả lỗi lưu"; các bước khác như Release).
- Mô phỏng vị trí: chạy app từ Xcode, Debug › Simulate Location với một GPX ở quán cần tới. Không mô phỏng được
  thì bỏ A3, B2, B3 và làm C2 thay.

**A. Trên bản cũ** (xoá app, cài de66fb4, mở; cho phép thông báo và vị trí Luôn luôn).
1. Giờ thật, Kế hoạch:
   - Ngày 8 › nhấn giữ 09:30 "Thuê kimono ở wargo Gion" › Đã tới.
   - Ngày 1 › nhấn giữ 12:00 "Gửi hành lý" › Đã tới.
   - Ngày 8 › nhấn giữ 10:30 "Yasaka Jinja…" › Bỏ điểm này.
2. Cài đặt › Chuyến đi › Chạy thử: chọn ngày 8, 11:00 › "Chạy thử từ thời điểm này". Sổ chạy thử chép từ sổ thật.
3. Mô phỏng vị trí ở Gion Yorozuya (ngày 8, 12:30). Thông báo "Gion Yorozuya" có nút "Đã tới" hiện ra: **không**
   bấm. Đưa vị trí ra xa mọi quán.

**B. Cài bản mới đè lên** (không xoá app), mở app. Chạy thử vẫn chạy.
1. **Đạt** khi ngày 8 (sổ chạy thử): 09:30 đã đánh dấu, 14:30 "Trả kimono" chưa; Yasaka vẫn bị bỏ.
2. **"Đã tới" từ bản cũ.** Trung tâm thông báo › nhấn giữ thông báo Gion Yorozuya › Đã tới.
   - **Đạt** khi 12:30 Yorozuya chưa đánh dấu.
   - "Đã tới" chạy nền nên app không tự mở: lần mở app kế tiếp, tab Kế hoạch đang ở trang ngày 8.
3. **Geofence sau khi cập nhật.** App đã mở một lần sau khi cài. Khoá máy, mô phỏng vị trí ở Yamamoto Menzō (ngày
   8, 16:00).
   - **Đạt** khi thông báo "Yamamoto Menzō" có "Đã tới", và bấm nó đánh dấu 16:00 ở trang ngày 8.
4. **Cờ chỉ ghi sau khi đã lưu** (bản mới Debug). Cài đặt › Chẩn đoán › Giả lỗi lưu › Lần lưu tới. Ngay sau đó
   Cài đặt › Chuyến đi › Chạy thử › "Về giờ thật" (lần lưu kế tiếp là lần đổi sổ thật).
   - **Đạt** khi alert "Chưa lưu được" ghi "Dấu đã đi và điểm bỏ: Giả lỗi lưu (Chẩn đoán)". Bấm **Để sau**, không
     bấm Thử lại. Ngày 8 vẫn hiện 09:30 đã đánh dấu.
   - Tắt hẳn app, mở lại ("Giả lỗi lưu" đã tự về Tắt). **Đạt** khi 09:30 vẫn đã đánh dấu, 14:30 chưa.
   - Không làm bước này thì chỉ bấm "Về giờ thật".
5. **Sổ thật sau khi đổi** (chạy thử đã kết thúc).
   - **Đạt** khi ngày 8: 09:30 đã đánh dấu, 14:30 chưa, Yasaka bị bỏ, 12:30 và 16:00 chưa (dấu 16:00 ở sổ chạy thử,
     đã xoá). Ngày 1: 12:00 đã đánh dấu, 15:00 "Nhận phòng" chưa.
   - Tắt hẳn app, mở lại. **Đạt** khi vẫn như trên.
6. **Bỏ dấu tới được máy.** Nhấn giữ 09:30 › Bỏ đánh dấu; tắt hẳn app, mở lại.
   - **Đạt** khi 09:30 chưa đánh dấu, 14:30 vẫn chưa, ngày 1 không đổi.

**C. Sau chu kỳ** (bản mới, không cần bản cũ).
1. **Widget theo đúng mục.** Chạy thử vào một ngày của chuyến; thêm widget "Điểm tiếp theo" (cỡ vừa). Trong app đánh
   dấu mục kế tiếp. **Đạt** khi trong vài giây widget chuyển sang mục sau đó. Ngay sau một lần cập nhật từ bản trước
   task này, widget có thể chưa hiện trễ giờ hay gợi ý (tối đa 30 phút, tới khi mở app): nó dùng lịch của chính nó
   cho tới khi app gửi bản tóm tắt mới.
2. **Thử thay, bản Debug** (chỉ thay B2/B3 khi không mô phỏng được vị trí; B2 vẫn là bước chính). Cài đặt › Chẩn
   đoán có hai nút. Mỗi nút gửi ngay một thông báo cho quán đầu tiên chưa đánh dấu của ngày app đang hiện (ngày 1
   khi chưa tới chuyến: Tsumugi).
   - "Thông báo Đã tới thử, kiểu cũ": nhấn giữ banner › Đã tới, rồi đóng Cài đặt. **Đạt** khi không có gì được đánh
     dấu và tab Kế hoạch đang ở trang ngày đó.
   - "Thông báo Đã tới thử": nhấn giữ banner › Đã tới, rồi đóng Cài đặt. **Đạt** khi quán đó được đánh dấu ở trang
     ngày. Bỏ dấu để dọn.

## Task 3.1a — Bản đồ offline: style bất biến theo build trên site

**Quy tắc phát hành (bắt buộc).** Deploy site trước khi phát hành app. Từ Task 3.1b, app tải gói offline từ style
bất biến mà nó được build cùng: `https://jpy27.delphyra.tech/map/jp27-light@<jp27:build>.json`, với `<jp27:build>`
lấy từ `metadata["jp27:build"]` của `public/map/jp27-light.json` trong app (dạng `<build tile>-<8 hex>`, ví dụ
`20261025_080012_pt-f5133df5`). Site chưa có file đó thì mọi vùng tải mới báo lỗi.
1. Sau khi deploy, mở `https://jpy27.delphyra.tech/map/jp27-light@<jp27:build>.json` và bản `jp27-dark@…` (tên đúng
   như trong `public/map/` của commit phát hành). **Đạt** khi cả hai trả JSON (HTTP 200, không phải trang 404 hay
   HTML), và `metadata["jp27:build"]` trong đó đúng bằng tên file.
2. Các file `jp27-*@*.json` cũ vẫn còn trên site (không file nào bị xoá khi deploy): app đã cài vẫn xin file của nó.

## Task 3.1b — Bản đồ offline: "Xong" chỉ khi từng vùng xong, gói biết build tile nó giữ

**Chuẩn bị.** Site đã deploy với file `@` của build này (Task 3.1a bước 1). Bản mới: build của task này, Debug (bước
3 cần "Giả style khác bản"; các bước khác như Release). Dòng trên cùng của Cài đặt › Dùng khi mất sóng là dòng của
lần tải: đang chạy thì "Bản đồ 0/1 vùng · 42%", xong thì "Xong", "Đã dừng" hoặc "Bản đồ 8/10 vùng · 2 lỗi".
1. **Không tạo được vùng thì không "Xong".** Cài đặt iOS › Developer › Network Link Conditioner › "100% Loss", bật.
   Trong app: Dùng khi mất sóng › một vùng chưa tải (ví dụ Nara) › Tải, rồi rời app ngay.
   - **Đạt** khi dòng vùng ghi "Đang chuẩn bị…" rồi, trong khoảng 20 giây, "Không kết nối được máy chủ bản đồ" màu cam
     với nút "Thử lại"; Live Activity kết thúc với dòng "Bản đồ 0/1 vùng · 1 lỗi" (không phải "Xong"), thanh không
     đầy; mở lại Cài đặt thấy cùng dòng đó ở trên cùng.
   - Vẫn bật "100% Loss": tắt hẳn app, mở lại. **Đạt** khi Nara được thử lại một lần ("Đang chuẩn bị…") rồi lại ghi lỗi
     với "Thử lại", và dòng lần tải ghi "Bản đồ 0/1 vùng · 1 lỗi".
   - Tắt "100% Loss", bấm "Thử lại". **Đạt** khi Nara tải xong ("Đã tải") và dòng lần tải ghi "Xong".
2. **Mất mạng giữa chừng.** Xoá vùng Tokyo nếu đã có (vuốt trái › Xoá), bấm Tải; khi vòng tới khoảng 20 %, bật Chế độ
   máy bay.
   - **Đạt** khi dòng Tokyo ghi "Chờ có mạng · 2x %", dòng lần tải vẫn là tiến độ, không bao giờ "Xong"; Live
     Activity (nếu đã rời app) vẫn chạy.
   - Tắt Chế độ máy bay. **Đạt** khi Tokyo tải tiếp tới "Đã tải" và dòng lần tải ghi "Xong".
3. **Site không có style của app** (bản Debug). Cài đặt › Chẩn đoán › Giả style khác bản: bật. Tải một vùng chưa có.
   - **Đạt** khi dòng vùng ghi "Bản đồ trên web khác bản trong app — cập nhật app hoặc thử lại sau" với "Thử lại", và
     dòng lần tải ghi "Bản đồ 0/1 vùng · 1 lỗi".
   - Tắt công tắc, bấm "Thử lại". **Đạt** khi vùng tải xong.
4. **Vùng tải bằng bản cũ.** Máy thử: xoá app JP27 trước (cờ "đã hỏi tải lại", `map.reloadAskedFor`, nằm trong App
   Group, cài đè không xoá nó). Cài bản cũ build từ **a758481 hoặc cũ hơn** (Release), tải trọn vùng Nara. Cài bản
   mới đè lên (không xoá app), mở.
   - **Đạt** khi alert "Bản đồ offline cần tải lại" hiện một lần. Bấm **Để sau**. Cài đặt: "Dùng khi mất sóng" ghi
     "Cần tải lại"; trong trang có dòng cam "Nguồn bản đồ đã đổi, nên 1 vùng…", Nara ghi "Tải từ nguồn cũ, cần tải
     lại" với nút "Tải lại".
   - Tắt hẳn app, mở lại. **Đạt** khi alert **không** hiện nữa.
   - Bấm "Tải lại" ở Nara; ở khoảng 50 % bật Chế độ máy bay, mở bản đồ ở Nara, phóng to. **Đạt** khi bản đồ vẫn
     hiện (gói cũ còn tới khi gói mới tải xong). Tắt Chế độ máy bay, chờ xong. **Đạt** khi Nara ghi "Đã tải", dòng
     cam biến mất, và bản đồ Nara vẫn hiện khi bật lại Chế độ máy bay.
5. **Tạm dừng là "Đã dừng".** Bấm "Tải tất cả bản đồ", rời app, dừng từ Live Activity trên màn hình khoá.
   - **Đạt** khi mở lại app, dòng lần tải ghi "Đã dừng", các vùng đang tải ghi "Tạm dừng · N %"; bấm vòng của một
     vùng thì nó tải tiếp từ đó.
   - Trong app: tải ảnh (mục Ảnh › Tải), bấm vòng để dừng. **Đạt** khi dòng lần tải ghi "Đã dừng", không "Xong".
6. **Lần tải được theo tiếp sau khi tắt app.** Bấm Tải ở một vùng chưa có; khi đang tải, tắt hẳn app; mở lại.
   - **Đạt** khi vùng tải tiếp (không bắt đầu lại từ 0 %), dòng lần tải hiện tiến độ rồi "Xong".

Không kiểm được trên máy: chế độ khi build tile được ghim đã mất trên OpenFreeMap (máy chủ trả 404) — cần
OpenFreeMap thật sự bỏ build đó.

## Task 3.2 — Nhật ký vị trí: chỉ trong chuyến, công tắc riêng, xoá được

**Chuẩn bị.** Bản mới: build của task này (bước 5 cần bản Debug cho "Giả lỗi lưu"; các bước khác như Release). Vị trí
"Luôn luôn" đã cấp. Cài đặt › Chẩn đoán › "Lịch sử vị trí: chỗ ghé · điểm vết" là số hàng `Visit` · `Trace` trong sổ
app đang đọc (sổ chạy thử khi đang chạy thử), đếm khi mở trang Cài đặt và đếm lại sau mỗi lần xoá.
1. **Lịch sử cũ ngoài chuyến bị xoá ở lần mở đầu.** Máy thử dùng bản cũ (**a39a43d hoặc cũ hơn**) ít nhất 3 ngày,
   với "Luôn luôn", mang theo khi đi lại (vài km mỗi ngày) và mở app vài lần mỗi ngày: bản cũ ghi chỗ ghé và điểm vết
   ở mọi lần mở và mỗi lần iOS báo đổi vị trí, vô thời hạn (trang Nhật ký không hiện chúng, vì chỉ đọc trong ngày
   chuyến, nên không thấy được trên bản cũ). Cài bản mới đè lên (không xoá app), mở, vào Cài đặt.
   - **Đạt** khi dòng Chẩn đoán ghi "0 · 0". Tắt hẳn app, mở lại: vẫn "0 · 0" (xoá một lần, không báo lỗi gì).
   - Nếu bỏ qua 3 ngày dùng bản cũ thì bước này đạt mà không chứng minh gì: ghi lại là "không kiểm".
2. **Không theo dõi nền trước chuyến.** Giờ thật trước 16/10/2027 18:00 giờ Nhật (lúc nền bắt đầu theo dõi), không chạy
   thử, "Luôn luôn" đã cấp. Mở JP27 một lần (mỗi lần mở, app hỏi vị trí một lần để tính quãng đường: iOS ghi "đã dùng
   gần đây" 24 giờ), rời app, rồi **không mở lại trong ít nhất 25 giờ**, mang máy đi lại vài km trong thời gian đó.
   - **Đạt** khi sau 25 giờ, Cài đặt iOS › Quyền riêng tư & Bảo mật › Dịch vụ định vị › JP27 không có mũi tên tím
     (đang dùng), không có mũi tên xám (dùng trong 24 giờ qua), và cũng không có mũi tên rỗng (geofence): ngoài ngày
     của chuyến app không đăng ký vùng nào (lần mở trước đã gỡ vùng một bản cũ để lại). Mở app: Chẩn đoán vẫn "0 · 0".
3. **Công tắc mặc định tắt; chạy thử ghi vào sổ riêng.** Cài đặt › Nhật ký: "Ghi nhật ký vị trí" đang tắt, chú thích
   "Chỉ trong 18–29/10/2027, chỉ trên máy này". Chạy thử từ 20/10/2027 12:00. Ở màn Hôm nay, đi bộ vài trăm mét với
   app mở.
   - **Đạt** khi Chẩn đoán vẫn "0 · 0" (tắt thì không ghi). Mở Nhật ký của ngày đó: có thẻ "Ghi chỗ đã ghé và đường
     đã đi…" với nút "Bật ghi".
   - Bấm "Bật ghi", đi bộ thêm vài trăm mét với app mở. **Đạt** khi Chẩn đoán có số điểm vết > 0 và thẻ "Bật ghi"
     biến mất.
   - "Về giờ thật". **Đạt** khi Chẩn đoán về "0 · 0" (sổ chạy thử bị bỏ, sổ thật không có gì), dù công tắc vẫn bật:
     giờ thật ngoài chuyến thì không ghi.
4. **Hỏi một lần ở Hôm nay; câu trả lời lúc chạy thử chỉ cho lần chạy thử đó.** Xoá app, cài lại bản mới. Chạy thử từ
   18/10/2027 09:00, mở tab Hôm nay.
   - **Đạt** khi có thẻ "Ghi nhật ký vị trí?" với "Bật" / "Không". Bấm "Không": thẻ biến mất, có rung nhẹ. Tắt hẳn
     app, mở lại (vẫn đang chạy thử): thẻ không hiện nữa; công tắc trong Cài đặt vẫn tắt.
   - Cài đặt › Chạy thử › "Về giờ thật", rồi chạy thử lại từ 18/10/2027 09:00. **Đạt** khi thẻ "Ghi nhật ký vị trí?"
     hiện lại (câu trả lời lúc chạy thử không giữ cho chuyến thật).
5. **Xoá lịch sử vị trí.** Sau bước 4, công tắc đang tắt: chạy thử từ 20/10/2027 12:00 (nếu chưa), Cài đặt › Nhật ký ›
   bật "Ghi nhật ký vị trí", rồi đi bộ vài trăm mét với app mở ở màn Hôm nay để Chẩn đoán có số > 0. Cài đặt ›
   Nhật ký › "Xoá lịch sử vị trí" › xác nhận "Xoá".
   - **Đạt** khi dưới nút ghi "Đã xoá N mục" (N = tổng hai số trước đó) và, trên cùng trang, dòng Chẩn đoán thành
     "0 · 0".
   - (Debug) Đi bộ thêm cho có điểm vết, Chẩn đoán › Giả lỗi lưu: "Lần lưu tới", rồi "Xoá lịch sử vị trí" › "Xoá".
     **Đạt** khi alert "Chưa lưu được" nói về "Xoá lịch sử vị trí", dưới nút không có số, Chẩn đoán vẫn là số cũ; bấm
     "Thử lại" thì xoá được (Chẩn đoán "0 · 0").
6. **Lời xin quyền.** Máy chưa cấp "Luôn luôn" (xoá app, cài lại): khi iOS hỏi nâng lên "Luôn luôn", lời giải thích
   nói về báo món, theo dõi ga, tự đánh dấu điểm trong ngày của chuyến, và chỉ ghi nơi đã ghé khi bật nhật ký. Cài đặt
   › Quyền › Vị trí luôn bật ghi "Nhắc khi tới quán, tới ga".

Chỉ kiểm được trong chuyến (giờ thật 18–29/10/2027), công tắc nhật ký **tắt**:
- Ngày 1, tới Resol Akihabara gửi hành lý: **để app tự đánh dấu** "Gửi hành lý" (đừng bấm tay trước khi iOS báo đã
  tới, thường vài phút sau khi tới: bấm tay trước thì lần báo tới có thể đánh dấu nhầm "Nhận phòng" — lỗi đã biết,
  controller đã gác lại, không phải điều bước này kiểm). Rời khách sạn đi tiếp: "Nhận phòng" **không** được đánh dấu
  lúc rời đi; nó chỉ được đánh dấu khi quay lại buổi chiều. Ngày 8 cũng vậy với WARGO Gion (thuê rồi trả kimono).
- Tốc độ đi bộ vẫn học khi tắt nhật ký: Cài đặt › Đi bộ thay đổi sau vài quãng đi bộ từ một điểm đã tự đánh dấu.
- Sau chuyến: mở app lần cuối sau 30/10 06:00 giờ Nhật, rồi không mở lại ít nhất 25 giờ. **Đạt** khi JP27 không còn
  mũi tên nào (tím, xám, rỗng) trong Dịch vụ định vị.

## Task 3.3a — Tàu đang đi không bị báo lỡ, ngày không giờ, nhắc buổi sáng, widget

**Chuẩn bị.** Bản build của task này (Release hay Debug đều được). Chạy thử: Cài đặt › Chạy thử. Khi chạy thử, vị trí
vẫn là vị trí thật (ở nhà, xa mọi tuyến của chuyến). Dòng "Đặt lại nhắc giờ, geofence, báo thức" ở Cài đặt › Chẩn
đoán là số lần đặt lại từ khi mở app.
1. **Chuyến đang theo dõi không bị báo lỡ.** Ở nhà, vị trí thật cách đường tàu hơn 1,5 km, nên chuyến đang theo dõi
   không được tính (R-126). Vì vậy bước này chạy **không có vị trí**: Cài đặt iOS › Quyền riêng tư › Dịch vụ định vị ›
   JP27 › "Không bao giờ", rồi tắt hẳn app và mở lại. Chạy thử từ 21/10/2027 08:30 (ngày 4). Kế hoạch › Ngày 4 ›
   Romancecar › "Theo dõi chuyến". Về Hôm nay.
   - **Đạt** khi Hôm nay không có thẻ "Trễ … phút cho Odakyu Romancecar 7:37"; thẻ tiếp theo là Hakone Tozan Bus
     9:35; widget trên màn hình chính không có "Trễ".
   - Mở chuyến, kết thúc theo dõi. **Đạt** khi thẻ "Trễ … phút cho Odakyu Romancecar 7:37" quay lại (không vị trí,
     không theo dõi: không có gì cho biết đang ở trên tàu, R-119).
   - Chạy thử từ 21/10/2027 07:20, theo dõi Romancecar. **Đạt** khi thẻ tiếp theo vẫn là Romancecar 7:37 (chuyến
     chưa tới giờ thì ngày chưa qua nó).
   - Bật lại vị trí ("Luôn luôn"), tắt hẳn app, mở lại. Chạy thử từ 21/10/2027 08:30, theo dõi Romancecar. **Đạt**
     khi thẻ "Trễ … phút cho Odakyu Romancecar 7:37" vẫn hiện: vị trí ở nhà, xa đường tàu, nói là không ở trên tàu.
2. **Ngày không giờ.** Chạy thử từ 29/10/2027 08:00 (ngày 12).
   - **Đạt** khi Hôm nay › "Còn lại hôm nay" có đủ ba mục (đi bộ tới Nankai Namba, Nankai, Sân bay Kansai), không mục
     nào trong "Đã qua". Đánh dấu mục đầu: nó vào "Đã qua", còn hai mục.
   - **Đạt** khi thẻ ở trên ghi "Đi bộ → Nankai Namba" với dòng "Không có giờ cố định", không phải "Hết lịch hôm
     nay" (R-122). Đánh dấu cả ba mục: lúc đó mới là "Hết lịch hôm nay".
   - Đối chứng, ngày có giờ (R-128): chạy thử từ 19/10/2027 18:10 (ngày 2), bấm "Đã tới" ở thẻ Tamai. **Đạt** khi
     thẻ là "Hết lịch hôm nay", dù còn đoạn về khách sạn không giờ (chỉ ngày không có giờ nào mới nêu mục đó).
   - Còn lại, đã biết (R-120, ngoài phạm vi): widget trống, vì ngày 12 không có điểm nào để báo (Nankai không có
     giờ, Sân bay Kansai là ga).
3. **Không nhắc buổi sáng lúc 23:30 đêm trước ngày 12.** Chạy thử từ 28/10/2027 23:20, rời app, chờ qua 23:31 theo
   giờ chạy thử.
   - **Đạt** khi không có thông báo "Ngày 12 · Ra sân bay Kansai". Đối chứng: chạy thử từ 21/10/2027 05:50, chờ qua
     06:00: có "Ngày 4 · …" như trước.
4. **Widget: giờ rời đi của kế hoạch khi trễ.** Chạy thử từ 27/10/2027 12:20 (ngày 10). Ở xa AWA nên Hôm nay báo
   trễ bàn 12:30.
   - **Đạt** khi widget có "Trễ N′" và dòng "Rời đi" ghi giờ của kế hoạch, không phải giờ lúc mở app. Để app mở ở
     Hôm nay 25 phút rồi về màn hình chính: widget vẫn có "Trễ", số phút đã tăng.
   - Bước này chỉ kiểm các bước 5 phút: ở nhà, độ trễ tăng mỗi phút nên ảnh chụp được gửi lại theo từng bước. Việc
     gửi lại một ảnh chụp trễ đứng yên sau 20 phút (trước khi widget thôi tin nó sau 30 phút) cần một độ trễ không đổi,
     không dựng được khi chạy thử; nó chỉ có bài kiểm ở mã.
5. **Màn hình khoá: chuyến đang theo dõi không đặt lại mọi thứ mỗi lần đổi vị trí (R-43).** Vị trí "Luôn luôn". Chạy
   thử từ 21/10/2027 08:00, theo dõi Romancecar, ghi số ở dòng Chẩn đoán. Khoá máy, đi xe (bus, ô tô, tàu) ít nhất 30
   phút, quãng ≥ 10 km, không mở app.
   - **Đạt** khi mở lại, số đặt lại tăng nhiều nhất 2 (không phải khoảng một lần mỗi 5 phút như bản cũ).
   - Giữ theo dõi, chạy thử tiếp tới sau 10:22 (một giờ sau giờ tới 9:22 của kế hoạch), khoá máy, đi xe thêm ≥ 2 km.
     **Đạt** khi số đặt lại lại tăng: chuyến bỏ dở không giữ việc đặt lại mãi.
   - Chạy thử từ 20/10/2027 12:00 (hôm trước), theo dõi Romancecar, khoá máy, đi xe ≥ 2 km. **Đạt** khi số đặt lại
     tăng: một chuyến của ngày khác không giữ gì (chỉ giữ trong ngày của nó, từ 7:07).

Chỉ kiểm được trong chuyến:
- Ngày 4, lên Romancecar mà **không** bấm theo dõi. Khoảng 7:40, khi tàu đã cách Shinjuku hơn 1 km, mở app. **Đạt**
  khi Live Activity của Romancecar tự bật (máy đang đi xe), Hôm nay không có thẻ "Trễ … cho Odakyu Romancecar 7:37",
  thẻ tiếp theo là xe buýt 9:35. Xuống ở Hakone-Yumoto, mở app trước khi chuyến được đánh dấu: cũng không có thẻ đó.
  - Đã biết, chấp nhận: trong khoảng một phút đầu, khi tàu đã ra khỏi ga nhưng chưa cách Shinjuku 1 km, thẻ "Trễ …
    cho Odakyu Romancecar 7:37" có thể hiện thoáng qua (chưa đủ xa để coi là đang đi tàu), rồi tự mất.
  - Đang trên Romancecar khoảng 9:15–9:22 với app mở: Live Activity của xe buýt 9:35 **không** tự bật (chỉ bật khi
    đứng gần trạm xe buýt).
- Ngày Kawaguchiko (nếu chọn): còn ở phố Fujiyoshida (Chūreitō, Honchō-dōri) sau 16:48, mở app. **Đạt** khi Hôm nay
  có thẻ "Trễ … phút cho Fuji Excursion 16:48". Ở Fuji-Q Highland lúc 17:05 (cạnh đường tàu, xa mọi điểm của ngày):
  cũng có thẻ đó (chậm hơn giờ tàu chạy qua hơn 10 phút thì không còn coi là đang ở trên tàu).
- Đứng ở sân ga Odakyu Shinjuku lúc 7:36 và 7:38 (tàu trễ một chút): không có thẻ "Trễ … cho Odakyu Romancecar 7:37".
  Từ 7:39, nếu tàu đã đi: có thẻ đó (quá một phút ân hạn, đứng ở sân ga cũng là lỡ tàu).
- Xuống ở Hakone-Yumoto sau 9:36 khi xe buýt 9:35 đã đi: có thẻ "Trễ … cho Hakone Tozan Bus 9:35".

## Task 3.3b — Giờ tới theo quãng vừa đi, phà thẳng, báo thức GPS không muộn hơn lịch

**Chuẩn bị.** Bản Debug (dòng nhỏ dưới công tắc "Báo thức trước ga xuống" ở trang chuyến chỉ có trong bản Debug:
"Báo thức 9:18 · lịch", "Báo thức 9:14 · GPS" hay "Chưa đặt báo thức"). Chạy thử không đặt báo thức thật, và ở nhà vị
trí cách mọi tuyến của chuyến, nên mọi bước dưới đây chỉ kiểm được trong chuyến.

1. **Dòng Debug.** Tối ngày 3, sau 21:00: Kế hoạch › Ngày 4 › Romancecar. **Đạt** khi dưới công tắc có "Báo thức 9:18 ·
   lịch" (7:37 + 105 phút − 4). Tắt công tắc: "Chưa đặt báo thức". Bật lại.
2. **Romancecar, theo dõi chuyến (ngày 4, 7:37).** Theo dõi từ sân ga, công tắc báo thức bật. Mở trang chuyến vài lần
   trên đường, nhất là khi tàu chậm lại vào Machida (~8:05), Hon-Atsugi và Odawara (~9:10).
   - **Đạt** khi giờ ở dòng Debug không bao giờ muộn hơn 9:18. Tàu đúng giờ vẫn có thể hiện "· GPS" với giờ sớm, tới
     khoảng 8:44 khi tàu chạy nhanh qua Machida: giờ tới tính theo nhịp vài phút vừa qua, và không sớm hơn 0,6 lần giờ
     của lịch. Bản cũ dời nó tới khoảng 11:30 khi tàu chậm vào ga.
   - **Đạt** khi "tới Hakone-Yumoto" (trang chuyến, dòng chuyến ở Hôm nay, Live Activity) không nhảy hàng giờ. Khi tàu
     chạy qua Machida nó ghi khoảng 8:46, đứng ở ga một phút thì lùi về khoảng 9:05. Nó có thể sớm hơn 9:22 nhiều và đổi
     qua lại quanh các ga, nhưng ở Machida luôn nằm trong khoảng 8:46–9:47. Thẻ của Hôm nay vẫn tính theo lịch (xe buýt
     9:35, tới lúc 9:22): hai con số khác nhau là đúng.
   - Nếu tàu qua hầm dài (mất vị trí vài phút): **Đạt** khi "tới Hakone-Yumoto" không trôi dần về sau trong lúc đó.
   - **Đạt** khi báo thức reo nhiều nhất hai lần, lần sau không muộn hơn 9:18 (R-136). Lần đầu có thể theo GPS, sớm hơn
     9:18. Nó phải reo ở khoảng Odawara–Iriuda, không sớm hơn 9:18 từ 20 phút trở lên (trừ khi máy mất vị trí lâu ngay
     trước đó). Sau lần reo đầu, dòng Debug chỉ còn ghi 9:18 (hay giờ vừa reo, trong giây lát) hoặc "Chưa đặt báo
     thức", không có giờ GPS nào khác.
3. **Tàu trễ (nếu gặp).** Nếu tàu tới Iriuda muộn hơn 9:20: **Đạt** khi báo thức reo lúc 9:18 (sớm hơn ga trước ga
   xuống), một lần, và sau đó không có báo thức thứ hai (R-131).
   - Đã biết, chấp nhận (R-131): một chuyến chỉ bắt đầu theo dõi sau giờ báo thức của lịch (9:18 với Romancecar)
     không có báo thức GPS nào.
4. **Phà thẳng: du thuyền hồ Ashi (ngày 4, 12:30, Moto-Hakone → Tōgendai).** Theo dõi chuyến, bật công tắc báo thức
   (thuyền mặc định tắt).
   - **Đạt** khi lúc lên thuyền trang chuyến ghi "Ga tiếp theo", không phải "Chuẩn bị xuống", và Live Activity không
     có "Xuống".
   - **Đạt** khi dòng Debug có "Báo thức 13:04 · GPS" (12:30 + 34 phút, lệch theo giờ thuyền chạy thật) thay cho "Chưa
     đặt báo thức" như bản cũ.
   - **Đạt** khi "Chuẩn bị xuống" chỉ hiện ở khoảng 900 m cuối, và báo thức reo quanh lúc đó.
   - Phà Toba → Wagu (ngày 7, 9:15) như vậy: "Chuẩn bị xuống" và báo thức (nếu bật) từ khoảng 9:30.

## Task 3.4a — Chuyến tự kết thúc, một Live Activity, giờ của Live Activity, báo khi ga trước ga xuống đã gần, cờ cũ, fence của ngày mai

**Chuẩn bị.** Bản Debug (dòng "Tự kết thúc lúc …" dưới nút "Kết thúc" ở trang chuyến chỉ có trong bản Debug). Ở nhà vị
trí cách mọi tuyến của chuyến, nên bước nào cần đi tàu thật thì ghi rõ.

1. **Hết giờ (chạy thử, ở nhà).** Cài đặt › Chạy thử: ngày 10, 8:25. Kế hoạch › Ngày 10 › Keihan tới Fushimi-Inari
   (8:30, 5 phút) › "Theo dõi chuyến".
   - **Đạt** khi dưới "Kết thúc" có "Tự kết thúc lúc 9:05 · hay sau 10 phút xa tuyến" (8:30 + 5, rồi thêm 30 phút).
   - Chỉnh giờ chạy thử sang 9:06. **Đạt** khi trong vòng 20 giây trang chuyến trở lại "Theo dõi chuyến", Live Activity
     biến khỏi màn hình khoá ngay, và dòng Live Activity trên thanh tab không còn.
   - Romancecar (ngày 4) theo dõi lúc 7:30 giờ chạy thử: **Đạt** khi dòng Debug ghi "Tự kết thúc lúc 10:14" (9:22 +
     nửa của 105 phút). Theo dõi nó lúc 9:30: "12:07" (chuyến sau cho chuyến đã lỡ: 9:30 + 105 + 52,5 phút).
   - Ở nhà vị trí xa mọi tuyến, nên chuyến kết thúc đúng giờ ghi. Trên tàu thật đang chạy trễ thì khác (R-141): quá giờ
     ghi mà máy vẫn có vị trí trên tuyến (trong 1,5 km, vị trí mới nhất không quá 2 phút) thì chuyến **chưa** kết thúc,
     Live Activity và báo thức GPS vẫn còn. **Đạt** trên tàu trễ khi chuyến kết thúc lúc tới ga (90 giây sau), hoặc
     trong vòng 2–3 phút sau khi máy mất vị trí trên tuyến, và chậm nhất sau giờ ghi thêm thời gian của chuyến (ít nhất
     60 phút: Romancecar 10:14 + 105 phút = 11:59).
   - **Bắt đầu hay kết thúc chạy thử thì chuyến đang theo dõi kết thúc (R-142).** Đang chạy thử, theo dõi lại Keihan
     (bước trên), rồi Cài đặt › "Về giờ thật". **Đạt** khi ngay sau đó trang chuyến trở lại "Theo dõi chuyến" và Live
     Activity biến khỏi màn hình khoá. Cũng vậy theo chiều ngược lại: theo dõi một chuyến ở giờ thật rồi bật chạy thử.
   - "Về giờ thật" sau bước này.
2. **Một Live Activity sau khi app bị tắt (đi tàu thật, chuyến nào cũng được).** Theo dõi chuyến, bật báo thức nếu
   chuyến có. Giữa chuyến vuốt JP27 khỏi màn hình đa nhiệm. **Đạt** khi Live Activity cũ vẫn còn trên màn hình khoá
   (app đã tắt, nó đứng yên) và báo thức vẫn còn (dòng Debug sau khi mở lại, hay đồng hồ của iOS).
   - Mở lại JP27. **Đạt** khi Live Activity cũ biến mất trong vài giây và báo thức của chuyến vẫn còn y như trước
     (không bị huỷ). Một Live Activity mới chỉ xuất hiện khi chuyến tự bắt đầu được: trong cửa sổ từ 20 phút trước tới
     10 phút sau giờ đi của nó, và đang ở gần ga đi hay máy thấy đang đi tàu. **Đạt** khi trên màn hình khoá không bao
     giờ có hai Live Activity của JP27 cùng lúc.
3. **Xuống sớm, rời tuyến (đi tàu thật).** Theo dõi một chuyến, xuống ở một ga trước ga cuối, rồi đi taxi hay xe buýt
   ra xa tuyến đó hơn 3 km và **tiếp tục di chuyển**.
   - **Đạt** khi khoảng 10–11 phút sau lúc đã cách tuyến hơn 3 km, Live Activity biến mất, mũi tên định vị trên thanh
     trạng thái đổi (định vị dẫn đường của JP27 tắt), và mở app thì trang chuyến ghi "Theo dõi chuyến".
   - Một đoạn không có vị trí (hầm, máy trong túi) không được tính vào 10 phút: chỉ các vị trí cách tuyến hơn 3 km
     trải đủ 10 phút mới kết thúc chuyến. Một vị trí trong vòng 3 km (quay lại gần tuyến) đếm lại từ đầu.
   - Đã biết, chấp nhận: nếu xuống rồi **ngồi yên** (quán ăn, ghế chờ), iOS dừng gửi vị trí và app ngủ; chuyến chỉ kết
     thúc ở lần app chạy kế tiếp (đi tiếp, iOS báo một chỗ ghé, mở app, làm mới nền). **Đạt** khi đó: mở app thì trong
     vòng 20 giây chuyến kết thúc như trên; hoặc nó kết thúc chậm nhất ở giờ "Tự kết thúc lúc …" của dòng Debug, ở lần
     app chạy đầu tiên sau giờ đó.
   - **Đạt** khi sau đó chuyến không tự bắt đầu lại (kể cả khi đang ngồi taxi trong cửa sổ giờ đi của nó).
   - Báo thức của lịch (nếu chuyến có và giờ của nó chưa tới) được đặt lại: dòng Debug ghi "· lịch". Đó là lưới an
     toàn đã chọn (R-140); tắt công tắc nếu không muốn nó reo.
4. **"Kết thúc" trên sân ga không tự bắt đầu lại (đi tàu thật).** Ở ga đi, trong 20 phút trước giờ đi của một chuyến có
   giờ, chuyến tự bắt đầu (Live Activity hiện). Bấm "Kết thúc". **Đạt** khi đứng tiếp trên sân ga 2 phút mà chuyến
   không tự bắt đầu lại (bản cũ bắt đầu lại sau 20 giây). "Theo dõi chuyến" bằng tay vẫn bắt đầu được ngay.
5. **Giờ tới trên Live Activity (đi tàu thật).** Trong Cài đặt iOS › Cài đặt chung › Ngày & Giờ, tắt "Tự động đặt" và
   chọn múi giờ Hồ Chí Minh. Theo dõi một chuyến.
   - **Đạt** khi giờ trên Live Activity (màn hình khoá) bằng giờ "tới …" ở trang chuyến (giờ Nhật), lệch nhiều nhất một
     phút, dù đồng hồ máy đang chỉ giờ Việt Nam; và bộ đếm ngược về 0 đúng lúc tới đó.
   - Trả múi giờ về như cũ sau bước này.
6. **Ga trước ga xuống đã gần, không còn kịp đặt báo thức (đi tàu thật).** Chọn một chuyến, bật công tắc báo thức
   (chuyến ngắn mặc định tắt). Chỉ bấm "Theo dõi chuyến" sau khi tàu đã rời ga trước ga xuống (hay trong khoảng một phút
   trước đó).
   - **Đạt** khi (báo thức đang đặt cho chuyến, nếu có, không reo trong 2 phút tới) ngay lập tức có **một** thông báo
     "Sắp tới <ga xuống>" (khẩn, kêu cả trong Tập trung), không có báo thức GPS mới (dòng Debug không đổi sang "· GPS").
   - Mở lại app, hay tắt rồi mở lại, rồi theo dõi lại chuyến: **Đạt** khi không có thông báo thứ hai cho chuyến đó.
   - Thông báo của JP27 bị tắt trong Cài đặt iOS (báo thức vẫn cho phép): **Đạt** khi không có thông báo nào, và nếu
     ga còn cách 30–60 giây thì báo thức GPS được đặt và reo (dòng Debug "· GPS") (R-143).
   - Công tắc báo thức tắt: **Đạt** khi không có thông báo nào.
   - Chuyến đi bình thường, theo dõi từ đầu, dòng Debug đã ghi "· GPS" trước ga trước ga xuống: **Đạt** khi báo thức reo
     như ở Task 3.3b và **không** kèm thông báo "Sắp tới" (cái đã reo, hay sắp reo trong hai phút, đã báo rồi). Nếu báo
     thức đang đặt còn xa hơn hai phút khi tàu qua ga đó (ví dụ "9:18 · lịch" mà tàu tới sớm), có thêm một thông báo
     ngay rồi báo thức vẫn reo: tối đa hai lần, đúng như thiết kế.
7. **Cờ "đang đi xe" cũ không tự bắt đầu chuyến (chạy thử, có đi xe thật).** Cài đặt › Chạy thử: ngày 4, 7:08
   (cửa sổ tự bắt đầu của Romancecar mở lúc 7:17). Ở xa ga Shinjuku (ở nhà là được).
   - Ngồi ô tô hay xe buýt đang chạy với JP27 mở trên màn hình ít nhất một phút: chưa tới cửa sổ, không có gì bắt đầu.
   - Về màn hình chính (JP27 xuống nền), xuống xe, đi bộ hoặc đứng yên tới khi giờ chạy thử qua 7:18 (khoảng 10 phút).
   - Mở JP27, không ở trong xe. **Đạt** khi không có Live Activity nào bắt đầu, cả lúc vừa mở lẫn một phút sau (bản cũ
     bắt đầu Romancecar ngay khi mở, vì còn nhớ "đang đi xe" từ trước khi xuống nền).
   - "Về giờ thật" sau bước này.
8. **Quán của ngày mai không mời "Đã tới" (đi thật, cần quyền vị trí "Luôn luôn").** Tối ngày N, đi ngang (trong vòng
   khoảng 150 m) quán ăn có trong lịch ngày N+1.
   - **Đạt** khi thông báo về quán vẫn hiện (nên gọi gì, trả tiền thế nào) nhưng **không** có nút "Đã tới", và không
     mục nào của ngày N hay N+1 bị đánh dấu.
   - Ngày N+1, tới quán đó (có thể là vòng tròn đã đặt từ tối hôm trước). **Đạt** khi thông báo có "Đã tới", và bấm thì
     mục của ngày N+1 được đánh dấu.
   - Ga: sáng hôm sau, đi ngang ga đi của một chuyến có giờ của hôm qua trước khi mở JP27. **Đạt** khi không có thông
     báo "… Ở <ga>" mời theo dõi chuyến của hôm qua.

## Task 3.4b — Chạy thử không bắt đầu ở "bây giờ", huy hiệu "Đang chạy thử", Nghe nhả micro và trả lại âm thanh

**Chuẩn bị.** Trang Chạy thử chỉ chọn được từ 17/10/2027 tới 31/10/2027. Bước nào cần "bây giờ" nằm trong khoảng đó thì
đặt ngày của iPhone (Cài đặt › Cài đặt chung › Ngày & Giờ, tắt "Đặt tự động") sang **20/10/2027**, giờ nào cũng được;
trả lại "Đặt tự động" sau các bước đó.

1. **"Chạy thử" ở bây giờ không làm gì (ngày máy 20/10/2027).** Cài đặt › Chạy thử. Không chạm vào ô "Thời điểm".
   - **Đạt** khi nút "Chạy thử từ thời điểm này" mờ (không bấm được), kể cả sau khi để trang mở 3 phút; dòng "Chạy thử"
     ở trang Cài đặt vẫn ghi "Tắt"; không có huy hiệu tím trên thanh tab; tiêu đề Chi tiêu không có dòng phụ, và vùng
     tiêu đề Chi tiêu cao đúng như ở bản trước (không có một dòng trống dưới "Chi tiêu").
   - Mở bánh xe "Thời điểm", xoay đi rồi xoay về đúng phút đang chỉ trên đồng hồ máy (để trang mở hơn một phút trước
     đó). **Đạt** khi nút vẫn mờ: một thời điểm trong phút hiện tại là "bây giờ".
   - Chỉnh "Thời điểm" lùi **hai** phút. **Đạt** khi nút sáng, và bấm vào thì dòng "Đồng hồ chuyến đi" hiện và chỉ phút
     đã chọn (hay phút ngay trước nó: lệch tối đa nửa phút), huy hiệu tím hiện. "Về giờ thật" sau bước này.
   - Đang chạy thử, kéo "Thời điểm" về đúng giờ thật của máy. **Đạt** khi nút "Chạy thử từ thời điểm này" mờ: chỉ "Về
     giờ thật" kết thúc buổi chạy thử.
2. **Huy hiệu (ngày máy bình thường).** Cài đặt › Chạy thử: ngày 4, 7:08 › "Chạy thử từ thời điểm này".
   - **Đạt** khi trên thanh tab, ở cả năm tab, dòng phía trên có biểu tượng đồng hồ tím và chữ "Chạy thử ·" trước nội dung
     thường; cuộn xuống cho thanh tab thu nhỏ thì còn biểu tượng tím. VoiceOver đọc "Đang chạy thử".
   - Tab Chi tiêu: **Đạt** khi dưới tiêu đề "Chi tiêu" có "Đang chạy thử · sổ riêng".
   - Mở lại trang Chạy thử: **Đạt** khi nút "Chạy thử từ thời điểm này" mờ (ô "Thời điểm" đã đặt theo đồng hồ chuyến
     đang chạy).
   - "Về giờ thật". **Đạt** khi huy hiệu và dòng phụ của Chi tiêu biến mất (trên iOS 26.1 trở lên, cả dòng phía trên
     thanh tab biến mất nếu trước chuyến).
3. **Máy đang giữ một "chạy thử" ở khoảng bây giờ từ bản cũ (bản trước 3.4b, ngày máy 20/10/2027).**
   - Với bản cũ: Cài đặt › Chạy thử, đợi phút trên đồng hồ vừa đổi, mở trang và bấm ngay "Chạy thử từ thời điểm này".
     Dòng "Đồng hồ chuyến đi" phải chỉ cùng phút với đồng hồ máy (nếu lệch, "Về giờ thật" rồi làm lại). Ghi một khoản
     chi 123 ¥ "Thử 3.4b".
   - Cài bản này đè lên (không xoá app), mở JP27.
   - **Đạt** khi: dòng "Chạy thử" trong Cài đặt ghi "Tắt"; không có huy hiệu; Chi tiêu là sổ thật, **không** có khoản
     123 ¥; đồng bộ với máy kia chạy lại (không còn "Đồng bộ tạm dừng trong lúc chạy thử"); báo thức của các chuyến được
     đặt lại (Chẩn đoán).
   - **Đạt** khi khoản 123 ¥ không mất hẳn: trong container của app (Xcode › Devices › Download Container) có
     `Library/Application Support/Trip-rehearsal-kept-<số>.store`, và Console (subsystem `tech.delphyra.jp27`, category
     `records`) có đúng một dòng "a rehearsal at about now was ended…". Mở lại app lần nữa: không có dòng thứ hai.
   - *Ghi chú (không phải bước kiểm, máy khó tạo ra):* nếu iOS không cho đổi tên sổ đó, Console có dòng lỗi "…was not
     set aside…", app vẫn chạy với sổ thật, sổ cũ nằm yên tại chỗ (không bị xoá) và lần mở app sau thử cất lại. Trong
     lúc đó bấm "Chạy thử từ thời điểm này" thì buổi chạy thử **không** bắt đầu; hộp "Chưa lưu được" hiện "Không cất
     được sổ chạy thử cũ: …" với "Thử lại".
4. **Cuộc gọi hay Siri trong lúc Nghe.** Sổ tay › Nghe và dịch › bấm nghe (nút đổi sang "đang nghe").
   - Gọi tới máy từ máy khác (hay gọi FaceTime âm thanh). **Đạt** khi ngay lúc chuông reo, màn Nghe không còn "đang
     nghe" (nút trở về như trước khi bấm); tắt cuộc gọi, mở lại JP27: vẫn đứng yên, bấm thì nghe lại được.
   - Làm lại với "Hey Siri" / giữ nút sườn. **Đạt** như trên.
   - Đang nghe, kết nối hay tháo AirPods. **Đạt** khi Nghe dừng (không treo ở "đang nghe" mà không chép gì).
   - Đang nghe, về màn hình chính rồi mở lại JP27. **Đạt** khi Nghe đã dừng.
5. **Nhạc trở lại sau Nghe và sau giọng đọc.** Mở Apple Music (hay Spotify), phát một bài, quay lại JP27.
   - Bấm nghe: nhạc nhỏ lại. Bấm dừng. **Đạt** khi nhạc to lại trong vòng một giây.
   - Sau đó, ở Sổ tay, bấm đọc một câu (nút loa). **Đạt** khi nhạc nhỏ lại trong lúc đọc và **to lại** khi đọc xong (bản cũ:
     nhạc nhỏ mãi tới khi tắt app).
   - Bấm đọc một câu khi chưa từng mở Nghe. **Đạt** khi nhạc to lại khi đọc xong.
   - Làm lại cả bước này với một app podcast hay video (Podcasts, YouTube) thay cho Music. **Đạt** khi tiếng của app đó
     nhỏ lại rồi to lại như nhạc, không bị dừng hẳn (không phải bấm phát lại).
6. **Nghe không chép giọng của app.** Đang nghe, bấm đọc một câu trả lời gợi ý (loa ngoài, không tai nghe). **Đạt** khi
   câu app vừa đọc **không** xuất hiện trong bản chép; nói một câu tiếng Nhật sau đó (hay mở một video tiếng Nhật) thì
   câu đó được chép (Nghe không bị điếc sau khi app đọc).
7. **Dừng Nghe khi app đang đọc (Q5).** Phát nhạc như bước 5. Đang nghe, bấm đọc một câu dài (đọc chậm) và bấm dừng Nghe
   khi câu mới đọc được nửa.
   - **Đạt** khi câu đọc tiếp tới hết (không bị cắt), nhạc to lại sau khi câu đọc xong, và bấm nghe lần nữa thì Nghe chép
     được câu nói tiếp theo.
   - Làm lại với công tắc Chuông/Im lặng ở **im lặng**. **Đạt** khi nửa sau của câu vẫn nghe rõ tới hết (không im bặt).
   - **Không đạt** nếu câu bị cắt hay nhạc không to lại: ghi lại, bản sửa đã định sẵn ở report Task 3.4b.

## Task 3.4c — Widget tải lại khi đổi đồng hồ hay ngày thay thế, giờ của widget, nút quyền, dự báo theo giờ thật, nhãn VoiceOver

**Chuẩn bị.** Thêm widget JP27 cỡ vừa và cỡ nhỏ lên màn hình chính, một widget chữ nhật trên màn hình khoá. Ngày máy
bình thường (trước chuyến).

1. **Widget theo chạy thử khi app chưa có snapshot.** Trước chuyến, widget ghi "Còn N ngày" (N lớn hơn 1). Cả hai
   trạng thái dưới đây đều trước chuyến (app không có mục kế, không có snapshot), nên chỉ bản này tải lại widget; bản
   trước 3.4c để widget đứng yên tới nửa đêm.
   - Cài đặt › Chạy thử: **17/10/2027, 22:00** (tối trước ngày 1) › "Chạy thử từ thời điểm này". Về màn hình chính,
     không chạm vào widget. **Đạt** khi trong vòng 10 giây widget đổi từ "Còn N ngày" sang "Còn 1 ngày".
   - "Về giờ thật", về màn hình chính. **Đạt** khi trong vòng 10 giây widget lại ghi "Còn N ngày" như lúc đầu.
2. **Ngày thay thế (kiểm hồi quy, không phân biệt được bản cũ).** Chạy thử ngày 3, 7:00. Bật "Một ngày ở Kawaguchiko"
   ở Lịch, về màn hình chính. **Đạt** khi trong vòng 10 giây widget ghi ngày Kawaguchiko (mục kế của ngày đó). Tắt lại:
   **Đạt** khi widget về "Sushi, Harajuku, Shibuya". "Về giờ thật". (Lúc này app có mục kế nên bản cũ cũng tải lại;
   dữ liệu chuyến chỉ có một ngày thay thế, cùng khách sạn với ngày 3, nên không có lúc nào không có snapshot mà widget
   lại hiện khác nhau.)
3. **Giờ của widget theo giờ app.** Chạy thử ở một ngày, trước một quán **không có giờ cố định** chừng 30 phút, rồi
   không đi (để trễ khoảng 15 phút). Mở app (Hôm nay ghi trễ), về màn hình chính.
   - **Đạt** khi widget cỡ vừa ghi "Đang đi · tới hh:mm" (hay giờ ở dòng "Sau đó"/danh sách cỡ lớn) **bằng** giờ tới mà
     app dự tính, không phải giờ trong lịch.
   - Một mục có giờ cố định (tàu, bàn đặt): **Đạt** khi widget vẫn ghi giờ của lịch ("Tàu chạy 16:15").
4. **Nút vị trí "Khi dùng app".** Vị trí ở "Khi dùng app", chưa từng hỏi "Luôn luôn" (cài mới).
   - Cài đặt › Quyền › Vị trí luôn bật › "Khi dùng app". **Đạt** khi iOS hỏi nâng lên "Luôn luôn". Chọn "Chỉ khi dùng".
   - Bấm "Khi dùng app" lần nữa. **Đạt** khi app Cài đặt của iOS mở ra (không phải bấm mà không có gì).
   - Cài mới lại, lần này chạm "Bật" ở thẻ "Bật vị trí Luôn luôn" của Hôm nay trước. **Đạt** khi sau đó nút ở Cài đặt mở
     thẳng app Cài đặt ngay lần bấm đầu.
5. **Dòng Thông báo trước khi hỏi.** Cài mới, chưa trả lời câu hỏi thông báo (huỷ nếu app hỏi khi mở; hay xoá app và
   cài lại rồi mở thẳng Cài đặt › Quyền). **Đạt** khi dòng "Thông báo" có nút "Cho phép" (nền đậm), bấm thì iOS hỏi.
   Chọn "Không cho phép": **Đạt** khi nút thành "Mở Cài đặt".
6. **Dự báo Fuji theo giờ thật khi chạy thử.** Chạy thử ngày 5 (năm 2027).
   - Hôm nay › thẻ "Fuji hôm nay" (hay Lịch › Fuji › "Đỉnh Fuji"). **Đạt** khi thẻ có các cột giờ bắt đầu từ giờ thật
     hiện tại (không trống, không phải giờ của hôm qua), "Rõ nhất lúc …" là một giờ sắp tới thật.
   - Mở "Tìm Fuji" (camera). **Đạt** khi phần mây ghi một con số (không trống) giống cột giờ hiện tại ở thẻ trên.
   - Không chạy thử: **Đạt** khi cả hai giống hệt bản trước.
7. **Dự báo vẫn từ WeatherKit** (bản có WeatherKit, có mạng). Lịch › Fuji (hai thẻ dự báo tải cùng lúc). **Đạt** khi
   chân cả hai thẻ có logo Apple Weather và "Nguồn". Quy tắc đếm lỗi trùng nhau có test TripKit (`FailureStreakTests`).
8. **VoiceOver: "Trễ".** Bật VoiceOver. Đang trễ (bước 3). **Đạt** khi widget cỡ nhỏ/vừa đọc "Trễ 15 phút" và widget
   chữ nhật trên màn hình khoá đọc "trễ 15 phút" (không đọc "dấu phẩy trên" hay ký hiệu).
9. **VoiceOver: Dynamic Island thu gọn.** Theo dõi một chuyến tàu, về màn hình chính, VoiceOver bật.
   - Chạm phần trái: **Đạt** khi đọc tên tuyến. Phần phải: **Đạt** khi đọc "Tới <ga> lúc hh:mm" (giờ Nhật, cùng giờ trên
     màn hình khoá); lúc "Xuống": "Chuẩn bị xuống ở <ga>".
   - Mở thêm một Live Activity của app khác (hẹn giờ ở Đồng hồ) để JP27 thành vòng tròn nhỏ. **Đạt** khi đọc "<tuyến>
     tới <ga>" và "Đã đi N phần trăm".
