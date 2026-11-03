# Review app iOS JP27 — 3/11/2026

Nguồn: review nhận được sau các đợt phát triển trên `main` tới `4b2e419` (merge PR #7). Đây là spec mà
kế hoạch `docs/superpowers/plans/2026-11-03-ios-hardening-and-smoothness.md` thực hiện. Giữ nguyên ý
của người review; số dòng là của commit `4b2e419`.

## A. Lỗi đúng/sai

1. **Báo thức bị huỷ khi mở app 45 giây trước giờ reo.** `AlarmService.planWake` dùng chung một danh
   sách cho hai quyết định: loại giờ báo còn dưới 60 giây, rồi huỷ mọi báo thức theo lịch vắng mặt
   trong danh sách vừa lọc. Ca báo thức còn hợp lệ và còn 45 giây bị huỷ. Đường GPS có biến thể:
   `place` xoá báo thức cũ trước khi kiểm giờ mới còn trên 30 giây, kiểm quyền, hoặc biết AlarmKit đặt
   thành công. Yêu cầu: tách điều kiện giữ báo thức đang có khỏi điều kiện đặt báo thức mới; chỉ bỏ cái
   cũ khi cái thay thế đã được xác nhận.
2. **Sổ chi báo "đã đồng bộ" trước khi dữ liệu được lưu bền.** Sửa khoản chi gọi `try? context.save()`,
   bật tín hiệu thành công rồi đóng editor. `Ledger.apply` nuốt lỗi save và trả về danh sách thay đổi như
   đã ghi xong; bên nhận dùng kết quả đó để đóng dấu đồng bộ. Bên gửi cập nhật `sent[k]` dù
   `MCSession.send` có thể throw (lỗi bị bỏ qua), nên heartbeat bỏ qua lần gửi lại nếu dữ liệu giữ nguyên.
   Yêu cầu: lỗi ghi phải tới UI; có xác nhận từ bên nhận sau khi lưu thành công.
3. **CSV hợp lệ cú pháp làm tab Chi tiêu crash lặp lại.** Bàn phím giới hạn ¥9.999.999, import chỉ kiểm
   `Int` dương. Hai khoản cùng nhóm, `9_223_372_036_854_775_807` và `1`, qua cửa import; tổng vượt Int64
   và `SpendDial` dùng `+=` trên `Int` mỗi lần dựng tab. Yêu cầu: một validation chung cho nhập tay, CSV
   và dữ liệu từ máy kia; kiểm overflow ở chỗ cộng tổng.
4. **"Tải offline xong" có thể nghĩa là vùng cuối vừa tải lỗi.** Tạo pack lỗi thì vùng bị bỏ khỏi
   `wanted`; hết việc chờ thì `finish()` đẩy tiến độ lên 100 % và xét thành công chỉ bằng
   `photos.failed`. Thêm: bản đồ đọc style đóng trong app, pack tải style từ web, app tự gắn nhãn phiên
   bản tile theo bản local; web và app lệch đợt phát hành thì nhãn mô tả sai tile đã tải. Yêu cầu: kiểm
   từng vùng đã hoàn tất và phiên bản nguồn thực tế của pack. (Endpoint production lỗi kết nối qua proxy
   lúc review, nên phần lệch phiên bản là rủi ro từ code, chưa xác minh trên bản deploy.)
5. **Background refresh trả quyền chạy về iOS khi việc chính còn dang dở.** Closure SwiftUI có
   `await model.refreshInBackground()`, nhưng hàm đó gọi `refresh`, rồi `rescheduleAll` tách việc cập nhật
   thông báo và báo thức ra các `Task` riêng. Yêu cầu: đường chạy nền await trực tiếp các tác vụ hệ thống
   mà nó được đánh thức để làm.
6. **ID điểm dừng đổi theo thứ tự ghé.** Ngày 8: thuê kimono 09:30 là `stop:wargo-gion`, trả 14:30 là
   `stop:wargo-gion#1`. Xoá mục thuê thì mục trả thừa kế ID của mục thuê; dấu "đã thuê" thành "đã trả".
   Notification "Đã tới" giữ riêng day + index, nên notification cũ đánh dấu nhầm một mục còn trong
   bounds. Yêu cầu: ID cố định cho từng lần ghé, dùng chung cho record, geofence và notification action.
7. **Nhật ký 12 ngày có thể thu vị trí nhiều tháng trước chuyến.** Cấp Always là app bật visit và
   significant changes; `visited` ghi tọa độ vào SwiftData kể cả khi `today == nil`; màn Nhật ký chỉ truy
   vấn theo cửa sổ ngày trong itinerary. Yêu cầu: giới hạn ghi theo thời gian thực của chuyến; tách lựa
   chọn ghi nhật ký khỏi quyền vị trí dùng cho nhắc ga.
8. **Bộ kiểm lịch phát hiện lịch bất khả thi rồi exit 0.** Đổi Nezu Jinja 11:00 → 06:00 trong bộ nhớ:
   script báo thiếu 302 phút rồi thoát thành công. Swift test chỉ kiểm hai implementation in cùng kết
   quả; fixture cập nhật cho lịch hỏng thì test đối chiếu vẫn xanh. Fixture hiện tại ghi
   `Nezu Jinja -2 min to spare` rồi kết luận `every timed stop can be reached`, do ngưỡng dung sai. Yêu
   cầu: giữ test parity và thêm một gate riêng cho tính khả thi.

## B. Chokepoints

1. `StaticTripMap` (trên luồng "chạm thẻ ngày → trang ngày"): cache chỉ tra trong `.task`
   (`Design/TripMap.swift:862`), khung đầu là ô xám dù ảnh đã trong bộ nhớ; ảnh đĩa là PNG 1–2 MB
   (`:971`), giải mã xong mới hiện; lần đầu snapshotter chạy style + tile đúng lúc transition chạy; chạm
   mở bản đồ thật (`:856`) crossfade sang `MLNMapView` trống rồi tile bật lên; badge `.thinMaterial`
   (`:847`) là blur thật trên mỗi bản đồ tĩnh.
2. `Speaker.ended` gọi `setActive(false)` đồng bộ trên main (`Services/Media.swift:560`), `setCategory`
   chạy lúc chạm (`:539`). Kích hoạt/huỷ audio session là thao tác chặn → chuyển sang serial queue riêng.
3. Chạm dấu tích chạy `rescheduleAll()` ngay trong tap (`AppModel.swift:457`): geofence CoreLocation và
   ghi UserDefaults trên đúng frame có animation dấu tích → dồn lại, chạy trễ ~0,3 s.
4. Trước chuyến, mỗi lần mở app gọi `requestLocation()` (`LocationService.swift:116`); kết quả kích hoạt
   `onMoved` → `rescheduleAll` lần hai ngay sau lần của `activate()`.
5. `isLowPowerModeEnabled` đọc trong body nên không cập nhật khi bật/tắt; key snapshot chứa trạng thái
   ghim đã ghé, mỗi lần đánh dấu sinh thêm một PNG trong Caches.

## C. Độ mượt khi mở/thu (theo mức cảm nhận)

1. Trang album (ngày từ thẻ trang chủ, địa điểm, khách sạn, điểm ngắm Fuji) làm quá nhiều việc lúc
   zoom: mỗi ảnh giải mã 3 lần (96 px màu `Media.swift:134`, 160 px lớp mờ `:175`, 1800 px ảnh); WebP
   800 px phải giải mã cả ảnh để ra ảnh nhỏ. Lớp mờ và ảnh fade (0,25 s, 0,2 s) trong `.drawingGroup()`
   (`Components.swift:606`, `:614`). `tones`, `heroHeight` ghi giữa transition (`PlaceView.swift:199`,
   `:240`). Vuốt ảnh đổi màu cả trang 0,45 s (`PlaceView.swift:238`, `Components.swift:701`). Sửa: giải mã
   một lần rồi suy ra 160/96 px bằng CGContext; ghép sẵn ảnh nét + mờ + gradient thành một `UIImage` ở nền
   và cache; không animate trong drawingGroup; giữ màu theo ảnh đầu hoặc đổi khi cú vuốt đã dừng.
2. Blur thật ở chân mọi `DetailHero` (`Components.swift:444`, `.ultraThinMaterial` + mask), ở trang Fuji
   còn nằm trên bản đồ 3D đang render → dùng lớp mờ dựng sẵn, gradient trộn sẵn vào ảnh.
3. MapKit 3D vệ tinh (`.hybrid(elevation: .realistic)`) dùng như ảnh tĩnh ở hero trang Fuji và thẻ điểm
   ngắm (`FujiView.swift:96`, `:545`), tạo ngay khung đầu của transition, đổi qua lại với hình offline
   theo `network.online` (chập chờn trên tàu) → `MKMapSnapshotter` + cache, hoặc gắn map thật sau khi zoom
   xong trên ảnh đã cache.
4. Tab Bản đồ: mỗi mục qua đường đọc kích hoạt highlight 0,25 s (`MapTab.swift:186`), dải điểm tự cuộn
   (`:843`), bản đồ bay camera (`:190`) → highlight không animation khi vuốt; chỉ bay camera một lần khi
   đường đọc đứng yên ~150 ms.
5. Khung đầu chưa phải khung cuối: `ExpenseEditor` đặt 5 state trong `onAppear` (`ExpenseEditor.swift:79`)
   → tính trong `init`. Trang địa điểm, trang tàu, thẻ Fuji dùng `VStack` cho cả trang → `LazyVStack`
   cho phần dưới hero.
6. Thẻ câu toàn màn hình xoay ngang: khung animate kích thước trong khi chữ cỡ 160 có
   `minimumScaleFactor(0.08)` (`TalkShared.swift:70`, `:95`) → tính cỡ chữ cho từng hướng, chỉ animate phép
   xoay.
7. Nạp trước: khi thẻ ngày nằm giữa carousel hoặc ngón tay vừa chạm, giải mã sẵn hero, lớp mờ, màu,
   snapshot của trang đích.
8. Ngôn ngữ chuyển động: ~20 curve (snappy, smooth với 8 thời lượng, easeOut, easeInOut, 3 spring,
   bouncy) → 4–5 token; spring cho mọi thứ người dùng tương tác trực tiếp.
9. Việc nhỏ: `withAnimation(.bouncy) { model.live.start(...) }` (`TodayTab.swift:452`) gói XPC của
   ActivityKit; mỗi dòng dịch trên ảnh menu là một `thinMaterial` (`MenuScanView.swift:278`); bàn phím
   số trong app và bàn phím hệ thống chạy hai curve khác nhau; haptic tạo generator mới mỗi lần mà không
   `prepare()`.

## D. Đo

- Instruments: Animation Hitches + SwiftUI (đếm body), mở app từ màn hình chính, bản Release.
- Mục tiêu: chạm → khung đầu < 50 ms; 0 hitch khi zoom mở trang ngày, trang địa điểm, thẻ Fuji; không
  rớt khung khi cú vuốt ảnh dừng.
- Máy thật: MetricKit (`MXAnimationMetric`) theo dõi tỉ lệ hitch.
