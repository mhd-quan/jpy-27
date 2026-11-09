# Báo cáo: dùng khi mất sóng và Cài đặt theo trang, app iOS JP27 (9/11/2026)

**Phạm vi:**
- Nhánh: `local/loving-feynman-6wu9ru`. Bắt đầu từ `82f8406` (main, merge PR #10), tới `c1408fc` (code), cộng commit báo cáo này.
- Spec: `docs/superpowers/specs/2026-11-08-offline-and-settings-design.md`.
- Kế hoạch: `docs/superpowers/plans/2026-11-09-offline-and-settings.md`, gồm 7 task.
- Hợp đồng thực thi: `docs/superpowers/plans/2026-11-04-execution-contract-phase4-5.md`. Các phán quyết của lượt này đánh số từ R-600.
- Việc kiểm trên máy: `docs/superpowers/checklists/2026-11-device-offline-settings.md`.

## Tóm tắt

Hai phạm vi bạn yêu cầu đã xong về code. Mỗi task đều qua review riêng, rồi các vòng sửa. CI "App builds" xanh, 0 warning, ở cuối mỗi task. Từ Task 7, CI dựng thêm bản Release. Sau đó là một review toàn nhánh ở mức `max`, một đợt sửa cuối, và một lần review lại có giới hạn phạm vi.

**Chưa có gì được kiểm trên máy.** Agent không có iPhone, simulator hay Chế độ máy bay để thử. Mọi bước "trên máy" nằm trong checklist: 60 hàng, ô kết quả còn trống. Vì vậy chưa thể nói "app chạy đủ khi mất sóng". Code đã được viết để làm vậy, nhưng chỉ chạy thử trên máy mới trả lời được. Hai điều chỉ máy mới trả lời được và đáng thử trước tiên:
- MapLibre 7.0.0 có đọc style đã nạp sẵn khi tạo và tiếp tục gói hay không (R-607; checklist § 1 hàng 1–3 và 6).
- Chữ Nhật trên bản đồ có hiện khi offline hay không (§ 1 hàng 2).

**Phạm vi 1: dùng khi mất sóng.**
- **Bản đồ offline tải được.** Style của gói nằm trong app, nên không còn phụ thuộc vào trang web. Có thêm gói "Toàn tuyến" (zoom 5–10) phủ cả chặng đường.
- **Trang "Dùng khi mất sóng".** Bảy mục, mỗi mục ghi trạng thái của nó: bản đồ, ảnh bản đồ các ngày, ảnh quán và khách sạn, địa hình Fuji, dự báo, gói dịch, gói nghe. Gói dịch và gói nghe tải được ngay từ Cài đặt.
- **"Tải tất cả".** Một việc duy nhất tải cả bảy mục, ghi tiến độ lên Live Activity. Việc này tiếp tục được sau khi app bị tắt hay bấm dừng, và hỏi trước khi dùng dữ liệu di động.

**Phạm vi 2: Cài đặt.**
- **Chia theo trang.** Ô biểu tượng mới sửa lỗi glyph trong ảnh 2. Mỗi trang có nhiều nhất một câu chú thích ngắn.
- **Trải nghiệm.**
  - Tốc độ đọc tiếng Nhật.
  - Giữ sáng màn hình khi đi tàu.
  - Giao diện.
  - Kính và bóng bản đồ, giờ đã có tác dụng thật.
- **Riêng tư.** Quyền và Nhật ký vị trí.
- **Hỗ trợ.**
  - Kiểm tra: 8 mục, mỗi mục ✓, ! hoặc ✕ kèm một dòng.
  - Log, với nút xuất.
  - Số đo.
  - Nguồn và ghi công.
  - Nhà phát triển, có cả trong Release. Hai công tắc giả lỗi phải xác nhận trước khi bật, và tự tắt khi mở lại app.
- **Log lưu trên máy.**
  - Giữ 14 ngày, tối đa 10 MB, kèm báo cáo crash.
  - Mọi việc chính đều ghi một dòng: lưu, tải, báo thức, đi tàu, vùng, đồng bộ, dự báo, gói ngôn ngữ.
  - Không ghi chữ bạn tự gõ, không ghi tên máy. Toạ độ làm tròn tới 0,01°.
  - Xuất ra một tệp `.zip` lúc nào cũng được. Tệp có `info.json` mô tả máy và kết quả kiểm tra gần nhất.

## Kết quả

**Các task đã hoàn tất**, theo thứ tự đã làm.

| Task | Nội dung | Commit | Kiểm |
|---|---|---|---|
| 1 | Style của gói nằm trong app (`PackStyle`); gói Toàn tuyến (`OfflineArea.overview`) | `d37b5b6`, `99d4797`, `83fbf6d` | pre-mortem 13/13 bẫy; review Approved (3 Minor); probe 27/29 (lỗ đã vá); 1 vòng sửa; CI 0/0 |
| 2 | Log trên máy: 14 ngày, 10 MB, báo cáo crash (MetricKit), xuất `.zip` | `0e50eea`, `274ff6c` | pre-mortem 7/7 bẫy chặn; review Approved (6 Minor); probe 40/47 (4 lỗ thật đã vá, còn lại tương đương); 1 vòng sửa; CI 0/0 |
| 3 | Dòng log của từng việc (khoảng 80 chỗ ghi), có cổng chặn để không ghi theo từng nhịp | `8c9da11`, `91fdb62` | pre-mortem 5/5; review: 1 Important, 3 Minor; 1 vòng sửa; review lại 4/4; CI 0/0 (không probe: không có kiểu TripKit mới) |
| 4 | Cài đặt theo trang: ô biểu tượng, Trải nghiệm, Riêng tư, tuỳ chọn bản đồ có tác dụng, tốc độ đọc, giữ sáng khi đi tàu (`KeepAwake`, nơi duy nhất ghi `isIdleTimerDisabled`) | `d385ef4`, `dd954db` | pre-mortem 5/5; review Approved (9 Minor); 1 vòng sửa; review lại 5/5; CI 0/0 |
| 5 | Sẵn sàng khi mất sóng: 7 mục và trạng thái (`Readiness`), gói dịch và gói nghe tải từ Cài đặt, trang "Bản đồ offline" | `79d343d`, `de88aa5` | pre-mortem đủ bẫy; review Approved (4 Minor); probe 14/14; 1 vòng sửa; review lại 3/3; CI 0/0 (sau sự cố GitHub, xem dưới) |
| 6 | Tải tất cả: một việc cho cả 7 mục, Live Activity, dừng và tiếp tục qua lần mở app, hỏi trước khi dùng dữ liệu di động | `cb9e1c7`, `b6e6e3f` | pre-mortem đủ bẫy; review: 1 Important, 9 Minor; probe 21/22 (1 tương đương); 1 vòng sửa; review lại 10/10; CI 0/0 |
| 7 | Kiểm tra (8 mục), trang Log có xuất, Nhà phát triển trong Release, dải đỏ "Đang giả lỗi lưu" | `58a1c8a`, `55f55f8` | pre-mortem đủ bẫy; review: 1 Critical (lỗi biên dịch, CI xác nhận), 2 Important, 7 Minor; probe 16/17 (lỗ đã vá); 1 vòng sửa; review lại sạch; CI 0/0 cả Debug và Release |
| Đợt sửa cuối | 4 mục nhỏ từ review toàn nhánh và 6 ghi chú cho checklist (xem dưới) | `c1408fc` | review lại có giới hạn phạm vi: 6/6, 0 lỗi, 2 góp ý nhỏ để lại (R-644); CI 0/0 cả Debug và Release |

**Quy trình.** Mỗi task đi qua các bước sau.
1. Pre-mortem, được chấm theo danh sách bẫy riêng mà người viết code không thấy (ST-2).
2. Triển khai, viết test trước để thấy test đỏ rồi mới sửa.
3. Review riêng cho task.
4. Mutation probe cho các kiểu TripKit mới.
5. Các vòng sửa và review lại.
6. CI "App builds" 0/0.

Code app chỉ được biên dịch ở CI. Logic thuần được đưa vào TripKit để có test chạy trên Linux.

**Review toàn nhánh** (`82f8406..55f55f8`, 17 commit, 64 file):
- Kết luận: "Ready to merge? Yes". Critical 0, Important 0, Minor 4.
- Các mục đã gác lại ở từng task đều được xếp loại "để lại được" (bảng dưới). R-638 được xác nhận và lấy vào đợt sửa cuối.
- Mọi lời trong checklist (dòng log, tên trường, chữ trên hàng, alert, tên công cụ) đều có trong code. Các con số khớp dữ liệu:
  - 11 vùng;
  - 13 ngày;
  - 32 chỗ dự báo;
  - 69 ảnh Fuji.

**Đợt sửa cuối** (R-640):
1. "Tải tất cả" gọi lại mọi phần còn bị giữ sau một lần dừng (R-638). Trước đây phần dự báo đã mới mà bị giữ làm việc kết thúc với dòng "Đã dừng".
2. Ảnh địa hình Fuji và tệp dự báo chuyển từ Caches sang Application Support, ngoài bản sao lưu iCloud, giống ảnh quán. iOS dọn Caches khi máy đầy. Ảnh Fuji là ảnh chụp MapKit, không vẽ lại được khi mất sóng, và dự báo thì không tải lại được.
3. Ngày không có ảnh (ngày 12, chỉ có ga KIX) theo màu sáng/tối của hệ thống. Ngày này giờ tính là sẵn sàng khi có ảnh của một trong hai màu. Trước đây mỗi lần hoàng hôn hay bình minh, trang chính lại báo "Thiếu 1 mục".
4. Hai báo cáo chẩn đoán cùng giây kết thúc không còn ghi đè lên nhau.
5. Checklist: 6 chỗ sửa lời cho đúng code, và thêm một hàng cho mục 2.

Chi tiết của đợt sửa:
- Thư mục cũ `Caches/Fuji` và `Caches/Forecast` bị xoá ngoài main thread ở mỗi lần mở app, nếu vẫn còn (R-643). Không chuyển tệp nào từ đó sang, vì lần "Tải tất cả" sau khi cập nhật sẽ vẽ và tải lại. Nếu xoá hỏng thì ghi log, và thử lại ở lần mở sau.
- Có 5 test TripKit mới, trong ba nhóm:
  - `Readiness.dayMapReady`: sẵn sàng khi có ảnh của màu kia, thiếu khi không có ảnh nào;
  - `LogRetention.diagnosticName(_:after:)`;
  - phần còn bị giữ, gộp với `forEverything`.
- Việc quyết ngày nào theo màu hệ thống vẫn nằm trong app, vì nó cần `DayPage.mapScheme` và `Appearance`.
- Sáu chỗ biên dịch chưa kiểm được ở máy agent đều đã biên dịch được ở CI.

## Đã kiểm, và kiểm bằng gì

- **TripKit:** 722 test trong 54 suite trên Linux (Swift 6.2.3) và trên macOS trong CI. Mỗi kiểu mới có test:
  - `PackStyle`, `OfflineArea.overview`;
  - các kiểu Log;
  - `Readiness`;
  - `OfflineJob` với extras, `ExtrasRun`, `JobBar`;
  - `CheckReport`;
  - `AwakeReasons`.
- **Mutation probe:**
  - Task 1: 27/29.
  - Task 2: 40/47.
  - Task 5: 14/14.
  - Task 6: 21/22.
  - Task 7: 16/17.

  Mutant sống sót nào là lỗ thật thì đã được vá bằng test trong vòng sửa của task. Những mutant còn lại là tương đương, hoặc được ghi trong "Hành vi còn lại".
- **Node:** `node --test 'scripts/*.test.mjs'` 71/71; `lint-saves` (không lỗi lưu im lặng), `lint-motion`, `check-plan` sạch.
- **CI "App builds"** (Xcode 26.2, macOS 26):
  - Bản Debug dựng ở mọi task; bản Release dựng từ Task 7 trở đi.
  - Dòng "0 warnings in the build, 0 in ios/JP27, ios/JP27Widgets, ios/Shared" là 0/0 ở cuối mỗi task.
  - Mỗi chỗ ghi `UNVERIFIED-COMPILE` trong report của task đều đã biên dịch được ở CI.
- **Bản Release:** mỗi `#if DEBUG` bị bỏ đã được kiểm bằng cách cắt mọi vùng DEBUG rồi tìm tên. Không tên nào chỉ có trong DEBUG mà bản Release dùng tới. Chỉ còn `TripMap.swift:750`, là phần chỉ dành cho bản Debug.
- **Riêng tư của log:** reviewer và controller kiểm theo dòng.
  - Mọi `msg` là chữ cố định.
  - Không có `"\(error)"`, không có tên máy, không có chữ người dùng gõ.
  - Toạ độ đi qua `LogRedact.round` (0,01°).
  - `info.json` của tệp xuất không có ghi chú, tên chỗ hay toạ độ.
- **Giả lỗi trong Release:** `failSaves` và `failReads` chỉ nằm trong bộ nhớ, nên mở lại app thì đã tắt. Đổi khỏi "Tắt" phải qua alert "Bật giả lỗi?". Nút "Tắt" trên dải đỏ tắt cả hai.
- **Không đụng `src/data`.** Không có tên model trong file hay comment nào của repo.

## Chưa kiểm trên máy

Tất cả các mục sau nằm trong checklist, ô còn trống:
- § 1 (6 hàng): tải gói khi style nằm trong app, chữ Nhật offline, gói Toàn tuyến, đổi build.
- § 2 (5 hàng): log ghi và xoay vòng, báo cáo crash, xuất `.zip` rồi mở trên máy tính.
- § 3 (5 hàng): thứ tự các dòng log của từng việc thật.
- § 4 (8 hàng): duyệt thiết kế ô biểu tượng (glyph), tốc độ đọc, giữ sáng khi đi tàu.
- § 5 (11 hàng): bảy mục và trạng thái, gói dịch và gói nghe. Cửa sổ "Cần xem" chỉ thử được từ 4/10/2027.
- § 6 (16 hàng, gồm hàng mới cho ảnh Fuji sau khi máy thiếu chỗ): "Tải tất cả" từ đầu tới "Xong", dữ liệu di động, dừng từ Live Activity rồi mở lại, Chế độ máy bay sau khi xong.
- § 7 (9 hàng): bản Release có đủ công cụ, giả lỗi hỏi trước rồi tự tắt khi mở lại, "Chạy kiểm tra" có mạng và mất mạng, `info.json`.

Chưa có số đo nào:
- thời gian và dung lượng của "Tải tất cả";
- thời gian bộ lọc "Lỗi" đọc 10 MB log;
- tốc độ vẽ 69 ảnh Fuji;
- pin.

## Việc của người dùng

1. **Chạy checklist** `docs/superpowers/checklists/2026-11-device-offline-settings.md`, § 1–7, trên bản Release. Ghi kết quả vào các ô.
2. **Cập nhật app trước khi "Tải tất cả".**
   - Khoá ảnh bản đồ các ngày có số build, nên sau mỗi lần cập nhật, ảnh cũ đọc là thiếu.
   - Sau đợt sửa cuối, ảnh Fuji và dự báo nằm ở thư mục mới, nên cũng phải tải lại.
   - Lần "Tải tất cả" cuối cùng nên làm trên bản sẽ mang đi.
3. **Làm "Tải tất cả" qua Wi‑Fi trước ngày đi, và để app mở.** Ảnh bản đồ các ngày và ảnh Fuji chỉ vẽ khi app đang mở. Khi app ở nền, phần đó dừng lại, và mở lại app thì nó đi tiếp.
4. **Mở trang Fuji một lần, rồi mở hai loại thẻ chỗ ngắm:**
   - thẻ không có ảnh chụp: hiện chỉ có Fujisan Yume no Ōhashi, ngày 5;
   - thẻ có ảnh chụp: ví dụ Tháp Chūreitō.

   App cần biết cỡ ảnh của từng loại thẻ thì mới vẽ được 69 ảnh Fuji. Trước khi mở đủ, mục Fuji ghi việc cần làm.
5. **Cửa sổ "Cần xem"** (dòng "Chưa sẵn sàng khi mất sóng" trên trang chính) chỉ hiện từ 14 ngày trước chuyến đi, tức 4/10/2027. Hàng này của checklist chỉ thử được từ hôm đó.
6. **Ảnh bản đồ các ngày vẫn nằm trong Caches.** Nếu iOS dọn Caches, mục này đọc là thiếu. Ngày đó vẫn mở được khi mất sóng, vì trang ngày vẽ trực tiếp từ gói bản đồ, chỉ chậm hơn một chút.
7. **Khi merge PR này:** chọn squash, rồi dùng tiêu đề và lời commit trong mô tả PR (R-641). Lời mặc định của GitHub ghép lời của mọi commit, kể cả các dòng ghi tên model.

## Ghi chú CI

- **GitHub tải tệp chậm hoặc lỗi.** Bước "Resolve packages" hỏng hai lần, trên `de88aa5` và `cb9e1c7`, trước khi biên dịch:
  - tệp `MapLibre.dynamic.xcframework.zip` trên GitHub trả 504;
  - SwiftPM báo "already exists in file system".

  Cả hai lần đều chạy lại sau khi tệp trả 200, và xanh. Đây là lỗi hạ tầng, không phải lỗi code.
- **Test chập chờn.** `DebouncerTests.restAfterEachCrossingFliesEachTime` (test của Phase 5) hỏng một lần trên macOS ở `274ff6c`, và chạy lại thì xanh. Nó không hỏng lại trong cả nhánh, nên chưa phải gia cố `ManualSleep.settle` (R-624). Nếu nó hỏng lại, cách gia cố đã ghi trong R-624.
- **Lần đầu dựng bản Release.** `58a1c8a` hỏng ở bản Debug với một lỗi biên dịch: một hằng `static` thuộc main actor được đọc từ chỗ không thuộc actor nào. Review của Task 7 đã thấy lỗi này trước CI. `55f55f8` sửa nó, và đó là lần đầu bản Release được dựng: xanh, 0 warning.

## Hành vi còn lại (đã chấp nhận)

- **R-642:** nếu không đọc được thư mục `diagnostics/` ngay sau khi tạo hoặc thấy nó, lần giao báo cáo đó không được ghi. Trước đây báo cáo vẫn được ghi, chỉ bỏ bước dọn. Cả hai trường hợp đều ghi một dòng lỗi trong log.
- **R-644:**
  - Test của mục 1 chỉ giữ phần TripKit. Dòng sửa trong app (`downloadEverything`) được kiểm bằng review và checklist § 6, hàng 4 và 7.
  - Hai chú thích code về thư mục Fuji và dự báo dài hai dòng.
- **R-623:** phần đếm dòng log bị mất chưa có test được commit. Review toàn nhánh đọc lại và thấy đúng. Nếu sai, một dòng "lines lost" bị thiếu hoặc lặp; không có dữ liệu người dùng nào bị ảnh hưởng.
- **Task 2:**
  - Nếu một tệp biến mất đúng lúc đang liệt kê thư mục, trang Log chỉ hiện phần trong bộ nhớ, kèm "không đọc được 1 tệp". Rất hiếm: actor đã xếp hàng các lần xoá của chính app.
  - Ba mutant tương đương: hai mutant ở chỗ `init` kẹp giới hạn, và một mutant ở bộ đọc giờ trên Linux, vì CI macOS chạy bộ đọc thật.
- **Task 3:**
  - Đồng bộ ở trạng thái `.sent` im lặng cho tới khi kết nối lại.
  - Máy đời cũ dùng chung nhãn "none".
  - `authFailure` không được xoá ở vài chỗ thoát sớm.

  Tệ nhất là một dòng log bị bỏ.
- **Task 4 (R-627, mục 3, 4, 7, 8):**
  - mất gợi ý vuốt, vì vuốt và menu là chuẩn iOS;
  - một số cài đặt được ghi log từ view, vì mỗi cài đặt chỉ có một chỗ ghi;
  - tỉ lệ 50% của `GlyphTile` so với 60% của `SettingsIcon`, để buổi duyệt thiết kế quyết định;
  - `PermissionStates` dựng lại mỗi lần vẽ, nhưng chỉ ở trang gốc.
- **Task 5 (R-631 Minor 1):** mỗi lần làm mới chạm đĩa khoảng 115 lần. Việc này chạy ngoài main thread, được gộp lại, chỉ chạy khi có sự kiện, và tốn vài ms.
- **Task 6:**
  - Mutant M05: thứ tự dòng kết thúc lấy từ một `Set`, nên test chỉ diệt được mutant này theo xác suất (khoảng 5/6 mỗi lần chạy). Test so chuỗi đủ ba phần vẫn đứng.
  - Mutant `JobBar` bỏ `isFinite` là tương đương.
  - Một thẻ vào cùng lần vẽ của việc tải không được giữ trong bộ nhớ.
  - Giới hạn 30 giây cho một lần vẽ MapLibre tính cả thời gian app ở nền (R-637).
- **Những điều review toàn nhánh để ngoài phạm vi:**
  - Việc bắt đầu qua Wi‑Fi đi tiếp qua dữ liệu di động khi mất Wi‑Fi, không hỏi lại. Spec chỉ hỏi lúc bấm, và cách tải từng vùng trước đây cũng vậy.
  - Dự báo đọc "Chưa mới" trong phần lớn chuyến đi, vì spec đặt độ mới là 12 giờ.
  - "Tải tất cả" đã tiếp tục vẫn chạy trong Low Power Mode, vì người dùng đã bấm (R-632 Q12).
  - Build ô bản đồ đang ghim chuyển sang build hiện tại của OpenFreeMap trong lúc ở nước ngoài thì mọi gói thành cũ. Điều này có từ trước nhánh này.
  - Chân trang Nhật ký vị trí ghi cứng "18–29/10/2027". Điều này cũng có từ trước.

## Các phán quyết đã đưa ra (nguyên văn từ sổ theo dõi, theo thứ tự)

Mỗi phán quyết ghi điều đã quyết, lý do, và cái giá nếu sai. Phần lớn viết bằng tiếng Anh, như trong sổ.

- **R-600:** Fuji terrain pictures are drawn ahead in both light and dark for every viewpoint card and area hero, not only the appearance in use (spec 1.3 says both only under Automatic) — a card's scheme follows its photo's colour, not the Appearance setting, so one scheme would leave cards blank offline — cost if wrong: about twice the MapKit snapshots in "Tải tất cả" (≈70 instead of ≈35), a minute or two more of download.
- **R-601:** Log test instants are exact to the millisecond (e.g. 1_800_000_000.5) so the encode/decode round trip compares equal — ISO 8601 keeps milliseconds only — cost if wrong: none.
- **R-602:** plan typo fixed before dispatch (`.missing(done: nil, total: nil)`), and Task 6's extras rule stated (only `job.extras` members are judged; a member without a state is not done) — the brief is the implementer's only source — cost if wrong: none.
- **R-603:** the map options move from `debug.mapGlass`/`debug.mapRelief` to `map.glass`/`map.relief` without reading the old keys — the old ones only applied while frame readings were on, a measuring aid, so carrying them over would turn the relief on for an owner who once measured with it — cost if wrong: an owner who wanted relief turns it on again once.
- **R-604:** "mở một branch mới" is served by restarting the session's branch `local/loving-feynman-6wu9ru` from the new main — the session may push only to that name; its content is a fresh line from main — cost if wrong: the owner wanted another branch name; a rename on GitHub is one step.
- **R-605:** "tiến hành" is taken as approval of the spec and of the plan, executed with subagent-driven development as in Phase 4–5 — the owner asked to proceed and chose this method last time — cost if wrong: the owner meant to read the plan first; they can stop the run and every task is a separate commit.
- **R-606:** R-347 is closed by the owner's own merge of PR #10 with a merge commit (adc3ea0's message stays in main's history) — the owner's call on their repository — cost if wrong: none for this run.
- **R-607:** put the style back (fire-and-forget, no completion) under the pack's own `tag.styleURL` right before every `pack.resume()` in `record`, and renew the preload on every later `configure` (each foreground) — MapLibre links the style row to a region only at 200 resources or at completion, so an unfinished pack's style is evictable ambient cache and "Tiếp tục" would ask the dead host — cost if wrong: one 8 KB database write per resume/foreground, nothing else.
- **R-608:** private `preloadStyle(currentTemplate:)` instead of `preloadStyle()`; `make` preloads the build it asked on (`askedOn`) — avoids a spurious `otherBuild` fail in the window `tilesMoved` now opens — cost if wrong: none (private signature).
- **R-609:** also correct the same stale fact at ios/README.md lines ~109 and ~290; add a one-line "toggle removed by Task 1 of 2026-11-09 plan" note at Task 3.1b step 3 of docs/superpowers/checklists/2026-11-device-phase1-3.md and name it in the report as outside the file list — stale instructions otherwise send the owner after a toggle that is gone — cost if wrong: two doc lines to revert.
- **R-610:** the other stale Phase 1–3 checklist steps (3.1a "deploy site trước", 3.1b step 1 expecting "Không kết nối được máy chủ bản đồ") get the same one-line retired note in Task 1's fix round — same reason as R-609 — cost if wrong: two doc lines.
- **R-611:** `StyleInfo.pointing` writes with `.sortedKeys` so the rewritten style's bytes are deterministic; the test keeps its byte comparison — a flaky green suite hides real failures, and stable bytes keep the stored style identical across preloads — cost if wrong: none (key order means nothing to MapLibre).
- **R-612:** take review Minor 1 — `make` reads the build the map reads now (the static that `move(to:)` sets synchronously) for both `askedOn` and the after-wait value passed to `step`, so a make overlapping a build move takes the existing `.again` path instead of making a throwaway pack of the old build — cost if wrong: none beyond the edit; if no such static exists the implementer says so and the window is accepted as self-healing.
- **R-613:** lines that fail to write stay in the writer's own backlog (cap 2000) and go first at the next drain; once a write works after any loss (backlog or shared-queue cap), the writer itself writes one warning "Không ghi được một số dòng log" with `dropped` and `error`; while the app is not in the foreground, and for every `error` line, the drain runs at once — background lines (geofence, alarms) otherwise die with a suspended app — cost if wrong: a few more small writes in the background.
- **R-614:** retention runs after every drain (not only at a day change), and today's file stops growing at `maxBytes` (lines counted as dropped, `lastWriteError` "Log hôm nay đã quá 10 MB") — the spec's "tối đa 10 MB" otherwise holds only at midnight — cost if wrong: one directory listing (≤ 15 entries) per drain; a runaway day loses its tail.
- **R-615:** diagnostics and export names (`diagnosticName`, `diagnosticsToDelete`, `exportName`) are pure helpers in TripKit with tests; names carry no ":" — testable, and ":" breaks zip extraction — cost if wrong: none.
- **R-616:** the MetricKit line is `error` "Báo cáo crash, treo máy" only when crashes + hangs > 0 (fields crashes, hangs, cpu, disk, launch); a delivery with neither logs `warning` "Báo cáo chẩn đoán" with the same fields; the JSON is kept either way — a "crash" line with 0/0 misleads the reader — cost if wrong: the brief's exact line appears less often.
- **R-617:** Task 3's pre-mortem is dispatched while Task 2 is under review — it writes only its pre-mortem file, no repo change, and is resumed only after Task 2 is complete — saves ~15 min of wall clock — cost if wrong: a Task 2 fix that renames an AppLog symbol makes part of the pre-mortem stale; the resume message corrects it.
- **R-618:** no "Ra vùng" line — fences are registered with notifyOnExit = false, so no exit event exists; adding one changes behaviour — cost if wrong: an exit line the owner wanted needs a fence change later.
- **R-619:** the † wordings of the pre-mortem stand (short, Vietnamese, listed in the report); `packError` lines at most one per area per 60 s, the next one carrying `suppressed`; "Đặt nhắc" after every completed reschedule (do/catch around `center.add` only to count failures); alarm `at` ISO 8601 UTC; booleans "true"/"false" — consistent, bounded volume — cost if wrong: wording edits only.
- **R-620:** also log the two save failures that skip `report` (LedgerSyncView.restore, SpendWallet CSV merge) and the low-frequency extras (geofence failure callback; geofence set only when it changes; Downloads background task stopped / submit failed / job resumed at launch; sync paused for a rehearsal; ride arrival; side-store fold) — spec 3.2 says every save error and "lưu log tất cả" — cost if wrong: a few more lines a day, two files outside the brief's list.
- **R-621:** the `.nack` reason is logged (cut to 200 characters) only if the sending side builds it from `localizedDescription` alone (checked at its send site); otherwise it is left out. `problem` logs the whole `Records.problem` sentence (fixed app text + system error). Translation errors log NSError domain and code only. Records.swift drops its unused `import os` — the privacy rule wins over debugging text — cost if wrong: less detail on a peer's failure.
- **R-622:** each export gets its own `tmp/<UUID>/JP27-log-<stamp>.zip` and the sweep of earlier zips goes (review Minor 2) — two exports then cannot break each other; the OS clears tmp — cost if wrong: old zips linger in tmp until iOS purges it. Task 7 still disables "Xuất log" while one runs.
- **R-623:** review Minor 4 (writer accounting has no committed test) is parked, not fixed now — the accounting was exercised by the implementer's 44-check harness on the committed file (byte-identical, per the reviewer), and extracting it is a refactor of a reviewed design; the final whole-branch review re-reads it — cost if wrong: a later change to the loss accounting regresses unseen. Minor 6 (crash JSON verbatim, plan-mandated by spec 3.2) is accepted and goes to the report for the owner.
- **R-624:** re-run the failed job once; if the same test fails again, the controller hardens ManualSleep.settle (wait until the sleeper set is stable, bounded) in its own commit — a flaky gate blocks every later task — cost if wrong: one re-run of the macOS job (~6 min).
- **R-625:** Task 4 answers — select hook in RideLiveService (outside list); "đã bật" = on + partial, "đang tắt" = off + ask; no walking-pace line (no control); one-sentence captions as proposed, except Chạy thử keeps the clock fact inside its one sentence; only leading row icons become SettingsIcon; stale "Chẩn đoán" paths fixed in ios/README.md and checklist § 2 (outside list), Records.swift:408 left to Task 7; keep-awake is an AppModel property over UserDefaults.standard `ride.keepAwake`; it stays on under Low Power Mode (the owner chose it); Nhà phát triển row visible in Release with its Release tools, DEBUG tools still behind #if DEBUG until Task 7; settings lines logged from AppModel on value change, whichever screen changed it — cost if wrong: copy edits or a moved row.
- **R-626:** GlyphTile (Theme.swift:447) gets the same fit fix (resizable, scaledToFit, clipped) — the owner reported this exact defect class; a device row covers the screens that use it — cost if wrong: a glyph elsewhere renders slightly smaller than before.
- **R-627:** Task 4 fix round 1 takes Minor 1 (Số đo explanations into ios/README.md), 2 ("không sang máy kia" back in the Chạy thử sentence), 5 (import TripKit in ExperiencePages), 6 (filter { $0.isOn }), 9 (drop headers repeating the page title on Chạy thử/Đi bộ/Nguồn); parks 3, 7 (accepted as judged), 4 (view-side logging equivalent while each setting has one writer; noted for the report), 8 (PermissionStates per render: cheap object, re-render only during downloads) — cost if wrong: a later second writer of a setting goes unlogged; a few allocations per progress tick.
- **R-628:** the stale ios/README.md paragraph describing the one-page Settings layout (§ "Sáng, tối và Cài đặt", the "Cài đặt xếp như Settings của iOS" paragraph) is rewritten in Task 7, once the Log and developer pages settle the final layout — one rewrite instead of two — cost if wrong: the README describes the old layout for three more commits.
- **R-629:** Task 5 answers — Q1 yes MapSnapshots.has (if the file name does not encode the fingerprint, compare it from the .json as in B3); Q2 yes three slots + FujiView passes the slot; Q3 per-slot reasons, first missing in order: area "Mở trang Fuji một lần", spot "Mở một chỗ ngắm chưa có ảnh chụp", sight "Mở một chỗ ngắm có ảnh chụp", a slot no spot uses is not required; Q4 yes async; Q5 yes shared TalkListener.transcriber(locale:); Q6 yes trip.days ∪ trip.altDays by key; Q7 yes; Q8 yes; Q9 yes; Q10 yes computed get-only (interfaces updated for Task 6); Q11 yes SettingsRoute.offlineMaps, title "Bản đồ offline" (row name stays "Bản đồ"); Q12 no override — the window is a pure TripKit function with edge tests, checklist row dated from 4/10/2027; Q13 only the stale row; Q14 yes (spec 1.3 "dòng ghi giờ cập nhật": oldest fetched time, Tokyo HH:mm, with the day when not today); also spec 1.3 "dung lượng khi biết": size only where a model already knows it, no new disk walk — cost if wrong: Fuji rows stay "needs setup" until two card kinds are opened; a device check of Cần xem waits for October 2027.
- **R-630:** update time stays "H:mm" — the cloud forecast footer already uses Tokyo H:mm, and one format across the app beats the ruling's literal HH:mm — cost if wrong: one-word change.
- **R-631:** Task 5 fix round 1 takes Minor 2 (installing flag set before the first await), Minor 3 (JobRow also on "Bản đồ offline", where per-area downloads start; footer stays on the readiness page, one caption per page), judgement 1 (a card with no photos counts only the scheme it always shows — R-600's "follows its card" read literally); parks Minor 1 (≈115 off-main hops per refresh, refresh is trigger-only, results correct) and carries Minor 4 to Task 6 (refresh after each extra part and on `ended`) — cost if wrong: a few ms per refresh; one extra refresh trigger missing until Task 6.
- **R-632:** Task 6 answers — Q1 yes (draw path awaits the disk write, disk-only check, no memory keep, a MapLibre picture drawn across a departure is not stored); Q2 yes (day maps and Fuji draw only while the app is open, forecasts may run away; copy "chờ mở app"); Q3+Q9 one rule: spec 1.4 binds — after one readiness refresh at the end, the job is "Xong" only when all seven items are ready or unsupported; any other item (packs asked for, needsSetup items the job could not do) makes it not a success and adds its word: "Ảnh bản đồ chưa tải", "Fuji chưa tải", "Dự báo chưa mới", "Gói dịch chưa tải", "Gói nghe chưa tải" (or the x/y forms when counted); this rule lives in TripKit with tests, and old saved jobs decode; Q4 (a) keep list spared by both launch trims, pure in TripKit with tests; Q5 yes (the words above); Q6 yes (optional state); Q7 yes (finished parts left out of the progress line, the % always shown); Q8 every key through hours (refetch > 1 h); Q10 yes (pure extras state machine in TripKit, the probe target with OfflineJob.result); Q11 footer "Vẫn tải khi rời trang hay rời app; ảnh bản đồ và Fuji chỉ vẽ khi app mở. Dừng được từ màn hình khoá."; Q12 yes (goes on in Low Power Mode); packs asked one turn after the alert closes + device row; the bar maps new progress onto what is left — cost if wrong: a first-time owner sees the job end without "Xong" until Hôm nay and two Fuji cards are opened; the keep list grows the task by two TripKit files and JP27App.
- **R-633:** Task 6 starts now (BASE de88aa5) rather than waiting on the outage — de88aa5 is a 36-line diff, TripKit-green, re-reviewed; the Task 5 completion line waits for a green App builds on any commit containing de88aa5; a compile fix, if needed, lands as its own commit before Task 6's review — cost if wrong: a compile fix interleaves with Task 6 work.
- **R-634:** accept the words "Bản đồ chưa tải" and "Ảnh quán, khách sạn chưa tải" (uncountable maps/photos, same pattern as R-632); the job does not wait for the speech pack (a stale "downloading" could keep it open for ever) — cost if wrong: the end line names a pack the system is still installing.
- **R-635:** Task 7 answers — Q1 yes: a Release build step in tripkit.yml (build only, no tests), its own-file warnings counted by the same gate; Q2 yes (ordered, network, offline pure + tested); Q3 yes (offline warning "Không có mạng" no requests; no answer error; 404/410/5xx/other-host redirect warning); Q4 ShareLink (repo pattern, no new UIKit isolation risk; the row turns into "Chia sẻ log" after the export) — cost: two taps; Q5 yes (confirm Fuji "Xoá", disabled while a download runs, readiness refresh after); Q6 yes; Q7 yes; Q8 "Bật"/"Huỷ"; reads alert "Đọc sổ chi sẽ báo lỗi tới khi tắt hoặc mở lại app." (the brief's sentence is the saves one); other drafted copy accepted if one sentence each; Q9 yes; Q10 full red row, white text, white "Tắt" trailing (spec "dải đỏ, có nút tắt"); Q11 yes (comment-only edits + SettingsKit route cases, listed) — cost if wrong: CI time +~3 min per app run; export shares in two taps.
- **R-636:** Task 6 fix round 1 takes all: Important 1 (persist "stopped and not asked for since" for every part the run knows; request removes what it asks for; TripKit test); Minor 1 (Tải tất cả always takes dayMaps and fuji when they can be counted, a ready part's pass only checks disk, recounts, rewrites the keep list); Minor 2 (readiness counts disk only, never memory); Minor 3 (Fuji recounts against a fresh wanted at the end of its pass); Minor 4 (the job's Fuji draw registers in `makings`, no parallel snapshot); Minor 5 (Live Activity words: "chờ mạng" beside "chờ mở app"; a waiting part keeps its count when known); Minor 6 (part start logs total; a restarted pass does not log a second start without an end); Minor 7 (doc comment matches code); Minor 8 (a MapLibre render is capped like the Fuji draw, the pass counts it interrupted/failed and moves on); Minor 9 (the three test gaps) — cost if wrong: a few more disk checks per Tải tất cả; a slow MapLibre render on an old phone cut at the cap and retried next pass.
- **R-637:** accept the 30 s MapLibre cap for page maps too (a page map slower than 30 s shows its placeholder until asked again, instead of waiting for ever) and "Đã dừng" for a relaunched job whose finished parts were stopped — cost if wrong: on a very slow link a day map on a page needs a second visit.
- **R-638:** the held-forecasts Minor goes into the final fix wave (one line in downloadEverything: also request any held job extra) instead of a fix round 2 — narrow case, honest-but-odd end line, batching saves a CI cycle; nits accepted — cost if wrong: until the final wave, that narrow case shows "Đã dừng" with every row ready.
- **R-639:** Task 7 fix round 1 takes Critical 1, Important 1–2, Minors 1–7 (1: the reminders line carries a short error description, never a raw `\(error)` dump; 2: the map part is clamped to "app dùng" and reads "gói bản đồ"; 3: tie-break test + all 8 IDs in the order test; 4: the tool says "Không có chỗ ăn nào chưa tới" and logs it; 5: README path; 6: re-check busy on confirm; 7: names from PermissionStates.all), plus the probe's `resultJSONKeysAreStable` — cost if wrong: none beyond one round.
- **R-640:** the one final fix wave takes all four Minors and the six checklist notes — (1) R-638 as refined: `forEverything(readiness.states).union(extras.run.held)`; (2) Fuji terrain pictures and the forecast files move from Caches to Application Support, out of the iCloud backup, like Photos (Media.swift:70), with the trims and keep list on the new folders and the old Caches folders removed once; day-map pictures stay in Caches because the day page draws live from the packs; (3) the cheap fix: a day whose map scheme follows the system counts ready when a picture of either scheme is on disk; (4) a diagnostic file index starts after the names already in `diagnostics/` — why: the user asked for an app that works fully with no signal, and a Fuji picture purged by iOS mid-trip cannot be redrawn offline (it is a MapKit snapshot), nor can a forecast be fetched again; (3) stops "Thiếu 1 mục" flipping at every sunset — cost if wrong: about 15–20 MB counted as app data instead of cache, and pictures drawn before the update are drawn once more (the update already needs a "Tải tất cả" for the build-keyed day maps).
- **R-641:** the spec's "Kết thúc nhánh" (update PR #10, squash-merge) was written for PR #10, which the owner has already merged. For this branch the PR into main carries a suggested squash title and message without the model trailers, and the merge stays the owner's — cost if wrong: none (nothing merges without the owner).
- **R-642:** a `diagnostics/` folder that cannot be listed (just after it was created or found) now skips writing that delivery, where before it wrote and skipped the trim; kept as is — both report through `fail()`, and a listing failure right after a successful create is near impossible — cost if wrong: one MetricKit delivery not kept, with a "Không đọc được thư mục báo cáo chẩn đoán" line in the log.
- **R-643:** the old Caches/Fuji and Caches/Forecast are deleted "while they are there" at each launch, not with a stored once-flag — a failed delete is logged and retried next launch; contract § 4.4's owned-folder list gains Caches/Forecast by R-640 — cost if wrong: one fileExists check per launch for two paths.
- **R-644:** both re-review nits are left — the two-line doc comments on the Fuji and forecast folders say why the folder is where it is (a code comment, not page copy, so the one-line copy rule does not bind it); the item 1 test pins the TripKit side (held ⊆ extras after restore, union with forEverything) while the one app line in `downloadEverything` is covered by review and checklist § 6 rows 4 and 7 (stop, relaunch, Tải tất cả again) — cost if wrong: a later edit could drop the app line with no unit test failing (the device rows would catch it).
