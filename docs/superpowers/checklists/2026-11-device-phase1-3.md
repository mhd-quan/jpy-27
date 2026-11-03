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
