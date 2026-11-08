# Báo cáo Phase 4–5: chỗ nghẽn và mở/đóng mượt, app iOS JP27 (8/11/2026)

**Phạm vi:**
- Nhánh: `local/loving-feynman-6wu9ru`, từ `0d7abf7` (main, merge PR #9, Bước 0) tới `b7c47d0` (code), cộng commit báo cáo này.
- Kế hoạch: `docs/superpowers/plans/2026-11-03-ios-hardening-and-smoothness.md`, Task 0.2 và Phase 4–5.
- Hợp đồng thực thi: `docs/superpowers/plans/2026-11-04-execution-contract-phase4-5.md`.
- Bàn giao: `docs/superpowers/handoffs/2026-11-04-phase-4-5/README.md`.
- Việc đo trên máy: `docs/perf/2026-11-device-perf-phase4-5.md`. Mốc đo: `docs/perf/2026-11-baseline.md`, baseline commit `a996140`.

## Tóm tắt

Phase 4–5 đã xong về code. Mỗi task qua review riêng, rồi các vòng sửa. CI "App builds" xanh với 0 warning ở mọi đầu task. Sau đó là một review toàn nhánh ở mức `max`, một đợt sửa cuối và một lần review lại có giới hạn phạm vi.

**Chưa có gì được đo trên máy.** Agent không có máy, simulator hay Instruments. Mọi bước "đo", "chụp màn", "duyệt thiết kế" và "spike trên máy" nằm trong tài liệu đo trên máy: 145 bước, ô kết quả còn trống. Vì vậy chưa thể nói các mục tiêu đo của spec D đã đạt:
- chạm → khung đầu < 50 ms;
- 0 hitch khi zoom mở trang ngày, trang địa điểm, thẻ Fuji;
- 0 khung rớt khi cú vuốt ảnh dừng.

Code đã được viết để đạt các mục tiêu đó, nhưng chỉ đo trên máy mới trả lời được.

Phần đã đổi, theo nhóm:
- **Đo:** signpost `perf`, mục Chẩn đoán › Số đo, MetricKit.
- **Chỗ nghẽn (Phase 4):**
  - bản đồ tĩnh có khoá và cache, ảnh phủ trên bản đồ sống;
  - audio session rời main thread;
  - Low Power Mode được theo dõi trực tiếp.
- **Mở/đóng mượt (Phase 5):**
  - mỗi ảnh chỉ giải mã một lần;
  - hero được ghép sẵn;
  - khung đầu chính là khung cuối;
  - bản đồ chỉ bay một lần;
  - Fuji dùng ảnh địa hình đã cache;
  - thẻ câu nói xoay bằng phép xoay;
  - trang ngày được chuẩn bị trước khi chạm;
  - Live Activity chạy ngoài animation;
  - năm token chuyển động, có lint trong CI.

## Kết quả

**Các task đã hoàn tất**, theo thứ tự đã làm. Phạm vi commit ghi trong sổ theo dõi.

| Task | Nội dung | Commit | Kiểm |
|---|---|---|---|
| 0.2 | Đo: signpost `tech.delphyra.jp27`/`perf`, Cài đặt › Chẩn đoán › Số đo, MetricKit. Baseline commit `a996140` | `dc51d38..a996140` | review sạch, CI 0/0 |
| 4.1 | Bản đồ tĩnh: khoá ảnh, cache trên đĩa (LRU theo cặp), ảnh phủ lên bản đồ sống | `a7f4a56..deb87a0` | review → 1 vòng sửa → review lại sạch, CI 0/0 |
| 4.2 | Audio session rời main: một hàng đợi riêng; `AudioSessionPlan` (TripKit) quyết định | `deb87a0..79e0e7c` | review, probe 15/16 (lỗ đã vá), 1 vòng sửa, ST-3 3/3, CI 0/0 |
| 4.3 | Low Power Mode theo dõi trực tiếp | `79e0e7c..cd20769` | review → 1 vòng sửa, CI 0/0 |
| 5.8a | Năm token `Motion` (press, pick, arrive, settle, travel) và `reduced` | `cd20769..adc3ea0` | review sạch (R-347 còn mở) |
| 5.1a | Mỗi ảnh giải mã một lần (`DecodePlan`); veil và tông màu rời actor | `adc3ea0..866f093` | probe 15/15, 1 vòng sửa, CI 0/0 |
| 5.1b | Hero ghép sẵn một lần (`AmbientFrame`, `HeldChoice`); không ghi state khi trang đang mở | `866f093..7691ad2` | probe 20/20 + 9/9, 1 vòng sửa, CI 0/0 |
| 5.2 | Chân hero trang chi tiết lấy từ ảnh đã làm mờ sẵn (`HeroFoot`) | `7691ad2..c7916e1` | probe 11/16 (lỗ đã vá), 1 vòng sửa, CI 0/0 |
| 5.5 | Khung đầu là khung cuối; trang dài dựng lười (`LazyVStack`) | `c7916e1..1707028` | 1 vòng sửa, CI 0/0 |
| 5.4 | Bản đồ bay một lần, tới chỗ dòng đọc dừng (`Debouncer`) | `1707028..c1490bc` | probe 7/10 (lỗ đã vá), 1 vòng sửa, CI 0/0 |
| 5.3 | Địa hình Fuji: ảnh chụp đã cache, bản đồ sống chỉ lên sau khi zoom xong (`SteadyValue`, `TerrainPicture`) | `c1490bc..0526d36` | probe 23/23, 1 vòng sửa, CI 0/0 |
| 5.6 | Thẻ câu nói xoay ngang chỉ bằng phép xoay; cỡ chữ đo một lần (`LargestFit`) | `0526d36..54c2b11` | review sạch, CI 0/0 |
| 5.7 | Trang ngày sẵn trước khi chạm: prefetch lúc thẻ dừng giữa màn hoặc khi ngón tay chạm (`NewestFew`) | `54c2b11..3231ef8` | probe 12/12, 1 vòng sửa (CI đỏ một lần), CI 0/0 |
| 5.9 | Live Activity ngoài animation (`RideStartGate`), nhãn thực đơn nền đặc, bàn phím số theo đường cong bàn phím (`KeypadMove`), haptic chuẩn bị sẵn | `3231ef8..4ce21cb` | probe 8/9 (lỗ đã vá), 1 vòng sửa, CI 0/0 |
| 5.8b | Mọi animation là token, Reduce Motion ở mọi chỗ có lò xo hay bay; `scripts/lint-motion.mjs` trong job `data` | `4ce21cb..20c8948` | 1 vòng sửa, CI 0/0 |
| Đợt sửa cuối | 10 mục nhỏ từ review toàn nhánh (xem dưới) | `20c8948..b7c47d0` | review lại có giới hạn phạm vi sạch (13/13), CI 0/0 |

**Quy trình**, giống Phase 0–3. Mỗi task đi qua các bước sau.
1. Pre-mortem, được chấm theo danh sách bẫy riêng (ST-2).
2. Triển khai, viết test trước để thấy test đỏ rồi mới sửa.
3. Review riêng cho task.
4. Mutation probe cho các kiểu TripKit mới.
5. Các vòng sửa và review lại.
6. CI "App builds" 0/0.

Code app chỉ được biên dịch ở CI. Không có target test cho app, nên logic thuần được đưa vào TripKit để có test chạy trên Linux.

**Review toàn nhánh** (`0d7abf7..20c8948`, 34 commit, 82 file):
- Kết luận: "Ready after the fix wave". Critical 0, Important 0, Minor 6. Danh sách sửa ngay có 10 mục, đều nhỏ.
- Mọi luật cứng đều giữ, trừ R-347.
- 8 điểm nối giữa các task đều qua:
  - đường ảnh;
  - camera bản đồ;
  - `raw`/`online` của mạng;
  - kiểu nút bấm;
  - bắt đầu chuyến;
  - token chuyển động;
  - cache trên đĩa;
  - signpost.

**Đợt sửa cuối** (R-507..R-517):
1. Panel bản đồ không bay hai lần nữa (R-439, R-508).
2. Tiêu đề và mặt trời trang bìa chỉ mờ vào khi bật Giảm chuyển động (R-509).
3. Báo thức GPS đang xếp hàng không còn rơi vào chuyến đã bỏ theo dõi (R-510).
4. Đếm dòng của `TalkShowFit` (R-511).
5. "ms/s" và lời chú thích ở Số đo (R-512).
6. Ba test TripKit (R-507).
7. Thêm hàng R-476 và hai hàng tiếng Việt trong tài liệu đo (R-513).
8. Hai chú thích trong code (R-514, R-515).
9. `interactiveSpring` trong lint (R-516).
10. Bước "Resolve packages" có thử lại trong CI (R-517).

Sau đợt sửa có một lần review lại, giới hạn trong phạm vi đợt sửa:
- 13/13 mục đã được xử lý.
- Mỗi test TripKit mới đều đỏ khi chạy với đột biến mà nó được viết để bắt.
- Không có lỗi Critical hay Important mới.

Còn hai điểm nhỏ, đã có phán quyết (R-519, R-520); xem mục "Hành vi còn lại".

**Kiểm ở đầu nhánh** (`b7c47d0`):
- TripKit: 590 test trong 47 suite (đầu Phase 4–5 là 367/28).
- Node: 71 test.
- `lint-saves`, `lint-motion` (0 chỗ) và `check-plan` sạch.
- `src/data` không đổi (R-86).
- CI: "0 warnings in the build, 0 in ios/JP27, ios/JP27Widgets, ios/Shared".

## Đã kiểm, và kiểm bằng gì

- **Bằng test (TripKit, Linux và macOS):** mọi quy tắc thuần mới.
  - `SnapshotKey` (khoá, LRU theo cặp);
  - `AudioSessionPlan`;
  - `DecodePlan`, `AmbientFrame`, `HeldChoice`, `HeroFoot`;
  - `Debouncer`, `SteadyValue`, `TerrainPicture`, `LargestFit`, `NewestFew`;
  - `RideStartGate`, `KeypadMove`;
  - số đo.
  Các kiểu có rủi ro được mutation probe. Mỗi lỗ probe tìm ra đã có test vá.
- **Bằng lint trong CI:**
  - `lint-saves` (không lưu im lặng);
  - `lint-motion` (mọi animation là token, lò xo và bay đi qua `Motion.reduced`, có 71 test node);
  - `check-plan`.
- **Bằng biên dịch ở CI:** mọi thay đổi phía app. Xcode 26.2, SDK iOS 26.2, bản Debug.
  - Có một dòng chỉ có trong Release (`FujiTerrainSnapshot.swift`, nhánh `#else` của `pictureOnly`). Lần biên dịch đầu tiên của nó là bản Release của người dùng.
- **Bằng đọc code (review):** những gì không có target test.
  - thứ tự `select`/`begin`;
  - chốt `leaving` của bàn phím số;
  - camera bản đồ;
  - đường ảnh;
  - cách đọc `raw`/`online`.

## Chưa đo

Toàn bộ tài liệu đo trên máy là việc của người dùng. Không ô nào đã được điền.

| Task | Số bước | Trong đó duyệt thiết kế |
|---|---|---|
| 0.2 | 7 | 0 |
| 4.1 | 9 | 1 |
| 4.2 | 8 | 0 |
| 4.3 | 3 | 0 |
| 5.1a | 6 | 1 |
| 5.1b | 14 | 3 |
| 5.2 | 10 | 4 |
| 5.3 | 23 | 6 |
| 5.4 | 11 | 0 |
| 5.5 | 9 | 1 |
| 5.6 | 9 | 1 |
| 5.7 | 13 | 1 |
| 5.8b | 14 | 1 |
| 5.9 | 9 | 4 |
| **Tổng** | **145** | **23** |

Ngoài ra, những việc sau cũng chưa ai làm:
- **Spike Fuji (R-308, § 5.3 bước 1).** Code đã viết theo phương án dự phòng, đúng bất kể spike cho kết quả gì.
- **Ảnh chụp màn trước/sau** của 5.1b, 5.2 và 5.3.
- **Chưa ai thấy điều kiện mọi lần đợi của 4.1/5.3 dựa vào.** Đó là việc `TransitionSettle` của 0.2 báo `settled` khi zoom dừng, chứ không phải `cap` (§ 0.2 bước 4).

## Việc của người dùng

1. Chạy `docs/perf/2026-11-device-perf-phase4-5.md` trên máy thật, bản Release, mở từ màn hình chính. Làm theo thứ tự tiêu đề, bắt đầu từ § 0.2 bước 4: nếu lời kết là toàn `cap`, các số đo sau không đáng tin. Bước nào không làm được thì ghi "không kiểm".
2. Duyệt thiết kế: 5.1 và 5.2 (PR ghi "Cần duyệt thiết kế"), cùng các hàng "duyệt thiết kế" khác trong bảng trên.
3. **R-347:** chọn một trong hai cách (xem dưới).
4. Không thêm hay bớt item ở ngày 1 và ngày 8, và không đổi leg (quy tắc R-86), cho tới khi cả hai máy đã chạy bản có bước chuyển record (2.1c).

## R-347: một commit message có tên model

Commit `adc3ea0` (Task 5.8a) kết thúc bằng một dòng đồng tác giả ghi tên một model khác với hai dòng ghi công của phiên. Luật của dự án cấm điều này. Review toàn nhánh xác nhận đây là trường hợp duy nhất trong mọi file và commit message.

Một lần force-push để sửa lời commit bị từ chối, nên commit vẫn để nguyên. Từ đó mọi lần push đi qua `push-gate`, và `push-gate` từ chối mọi dải commit có tên model.

Người dùng chọn một trong hai:
- **(a)** cho phép một lần force-push để sửa lời của `adc3ea0`. Mọi commit sau nó đổi SHA. Baseline `a996140` ở trước nên không đổi.
- **(b)** squash-merge PR Phase 4–5, khi đó lời commit này không vào `main`.

## Ghi chú CI

- **MapLibre trên runner:** 4 trong 12 lần chạy đầu, job "App builds" hỏng ở bước resolve package, trước khi biên dịch. Lỗi là "…MapLibre.dynamic.xcframework.zip already exists in file system", nằm trong cache artifact của SwiftPM trên runner.
  - R-341: một lần như vậy là lỗi runner, chạy lại job một lần.
  - Đợt sửa cuối thêm bước "Resolve packages": nếu hỏng thì xoá cache artifact rồi resolve lại một lần (R-517).
- **5.7:** CI đỏ một lần vì lỗi biên dịch thật. `PlainButtonStyle` là `PrimitiveButtonStyle`, nên không bọc được trong `ButtonStyle`. Đã sửa (R-479), và có thêm một hàng duyệt thiết kế cho ảnh bìa khi bị giữ.

## Hành vi còn lại (đã chấp nhận)

- **0.2:**
  - Tên push theo từng tab (A1) làm các route của một tab nằm chung một trung vị trong MetricKit. Trong Instruments thì S1 và S3 vẫn tách vì mỗi lần chỉ chạy một kịch bản.
  - Một đích không có mark riêng có thể nhận mark còn mở của một chuyển cảnh không có trang. Việc này chỉ xảy ra với push trong stack của sheet, và bị chặn bởi timeout 3 giây.
  - `firstFrame` bắn ở `onAppear` đầu tiên của đích, không phải ở khung hình đầu tiên được vẽ (A11). Muốn biết khung thật thì đọc track Hitches.
  - Hai sheet phóng to tại chỗ (`SpendTab.swift:182`, `ShoppingView.swift:51`) không có probe báo zoom xong. Không sao chừng nào không có việc của 4.1/5.3 chạy bên trong chúng (R-518).
- **4.1:**
  - Thứ tự hoà (tie-break) khi bỏ đi vẫn có thể sống sót theo thứ tự dictionary. Hai test hoà hiện có, nhưng cả hai chạy chung một vòng, nên một đột biến của hàm so sánh sống sót khoảng 1 trên 420 lần chạy (R-518).
  - "Vẽ xong hẳn" có đợi cả lớp GeoJSON của chuyến hay không thì chưa chứng minh. Nếu không đợi, ảnh có thể nâng lên trước khi tuyến vẽ xong một khung hình. Bước 6 của checklist kiểm.
- **4.2:**
  - Khi media services bị reset, chỉ "category đặt gần nhất" bị quên. Ba thứ khác không xử lý: người đang giữ session, prior lấy trước lúc reset, và synthesizer mà iOS có thể cần dựng lại (R-339).
  - Nếu synthesizer không bao giờ gọi lại, `speaking` vẫn bật, Nghe bị "điếc" và session không được trả. Đây là tồn đọng cũ của 3.4b.
  - Nghe dừng bằng deactivate bị busy, rồi bật lại trong vòng 150 ms: `capturePrior` của lần nghe mới chụp phải setup của chính Nghe, nên setup trước khi nghe bị mất. Hậu quả giống mục trên.
  - Một câu kết thúc chưa đầy 500 ms trước khi app bị treo thì chỉ nhả session ở lần mở lại kế tiếp, vì app không có chế độ nền `audio`. Nhạc của app khác lên lại lúc nào ở trường hợp này thì dòng thiết bị 8 quyết định.
  - Lần retry sau `isBusy` có thể deactivate một session đã tắt. Có báo cho app khác "mở nhạc lại" ngay ở lần lỗi đầu hay không thì Apple không ghi rõ. Bước 2 ("nhạc lên lại trong 1 giây") quyết định.
- **4.3:**
  - Hai yêu cầu lên lịch lại không trễ khi chạm: `alternatives` (`didSet`, từ Toggles) và `setClock` (nút diễn tập). Cả hai là thao tác cài đặt hiếm, người dùng muốn thấy kết quả ngay. Review cuối nói lý do của ruling chưa đúng hẳn, vì trễ 300 ms chỉ hoãn nhắc, hàng rào và báo thức, chứ không hoãn việc lập lại kế hoạch trên màn hình. Nếu một dòng thiết bị thấy giật thì sửa bằng `after: .milliseconds(300)` ở cả hai chỗ (R-345).
- **5.1a:**
  - Một ảnh xa đầu tiên không có trên đĩa mà `tone()` trả về nil thì sau đó được `veil()` tải. Một lần vẽ lại cùng trang có thể đổi từ màu giấy sang màu ảnh, trừ khi quy tắc màu trang của 5.1b chặn (R-357).
  - Hai yêu cầu cỡ khác nhau cho cùng một ảnh chạy cùng lúc (ví dụ 1200 và 1800) vẫn giải mã hai lần. Các yêu cầu nối tiếp thì dùng chung.
  - `albumPixel` (1800) và `maxPixel: 1800` ghi cứng trong `AmbientPhoto` phải khớp nhau thì ảnh xa lớn mới dùng chung được.
  - Yêu cầu nhỏ (`Rows`/`PlanTab` 200, Stays 240) có thể được phục vụ bằng một bản giải mã nguyên cỡ đang nằm trong bộ nhớ, tới 1290×1560 cho một bìa. Texture lớn vẽ vào ô nhỏ, nhưng không bao giờ là một lần thu nhỏ lớn (R-351). Dòng thiết bị 6 (cuộn nhanh, 0 hitch) kiểm.
  - `DecodePlan.isFull` không có chốt cho nguồn ≤ 0. Không tới được trong thực tế, vì header báo kích thước 0 thì không giải mã ra gì (R-518).
- **5.1b:**
  - Một cú vuốt nhanh huỷ ảnh đang ghép, và quay lại thì ghép lại (R-381). `TabView(.page)` có huỷ `.task` của trang ngoài màn hình hay không thì dòng thiết bị quyết định.
  - Ở chế độ Tiết kiệm pin, hero không có lớp mờ dưới phần tan dần. Nó hiện bản giải mã nét. Các trang đã mở trước đó giữ ảnh của chúng (R-381).
  - Lần mở đầu tiên ghép ngay trong lúc zoom, cho tới khi 5.7 nạp trước. Việc nền không nằm trên main nhưng CPU và bộ nhớ trùng với chuyển cảnh.
  - Ảnh ghép dùng chung 128 MB `NSCache` với các bản giải mã, mỗi ảnh bìa ngày khoảng 7 MB. Bộ nhớ căng thì bị đuổi sớm hơn (R-457).
  - Màu trang không còn theo ảnh khi vuốt: ảnh đầu quyết định cả trang (dòng thiết bị 14).
  - Lần mở đầu khi chưa có gì trong bộ nhớ, ô giữ chỗ là màu xám không mặt nạ dưới phần tan dần của hero, chừng một khung hình.
  - Hero có thể được dựng ở các cỡ trung gian trong lúc zoom, mỗi cỡ là một khoá và một lần ghép riêng. Màn hình giữ ảnh cũ cho tới khi ảnh mới xong.
  - Logic đếm waiter thuần nhưng chưa có test ghim. Nâng lên một kiểu TripKit có test, dùng chung với các lần ghép của `FujiTerrainPictures`, là việc của một M sau này (R-518).
  - Đoạn chuyển sắc alpha 4 dòng nằm hai nơi (`Components.swift:627-638` và `Media.swift:555-560`). Chia sẻ sẽ phải đụng vào bộ ghép (R-411).
- **5.2:**
  - Lớp mờ không còn tông tối riêng. Trong lúc kéo, chân hero giữ lớp mờ của trang trước cho tới khi `page` đổi rồi đổi ngay một lần. Tên Fuji nằm trên bản đồ nét cho tới 5.3. Cần duyệt thiết kế (dòng 5, 6, 9, 10).
  - Một lớp mờ được tạo ở nơi khác trong lúc hero đang chỉ có bóng tối (Tiết kiệm pin, không có waiter) chỉ xuất hiện ở lần vẽ lại kế tiếp của hero. Cái giá là phần chân tối hơn (0,55) (R-390, R-392).
  - Một lớp mờ chỉ nằm trong `NSCache` thì có thể bị đuổi khi bộ nhớ căng, và chân hero hiện bóng tối cho tới lần có lớp mờ kế tiếp (R-390).
  - Lần tạo lớp mờ không huỷ được khi đã bắt đầu; cái giá là một lần tạo 160 px kết thúc sau khi trang đã rời đi (R-518).
  - Việc nướng lớp mờ chạy trên main, tối đa 160 px một cạnh (R-388). Khi bật Giảm trong suốt thì không có lớp mờ, bóng tối 0,55 (R-391).
- **5.3:**
  - Lần ghé trực tuyến đầu tiên, ảnh chụp được vẽ trong lúc bản đồ sống tải ô của nó (A2 (B)). Dòng 3 và 5 cho biết có tốn khung hình không.
  - Khi bản đồ sống đã gắn, một ảnh hoàn tất ở nền không thành bìa nữa mà giữ ô giữ chỗ tới lúc nâng. Ảnh đó giữ cho lần ghé sau (R-470).
  - Offline trong nhịp 0,8 giây rồi đổi vùng thì bản đồ sống đã chốt vẫn bay, và ô có thể thiếu dù đã có ảnh đã lưu của vùng đó (R-470, R-476). Có dòng thiết bị cần duyệt thiết kế.
  - `FujiTerrainSnapshot.swift` hiện 737 dòng, và phép ánh xạ lặp ở `:289-292` và `StaticTripMap.swift:173-176`. Tách sau (R-475).
- **5.5:**
  - `SheetHost` chạy lại thân mỗi lần có fix GPS khi trình soạn thảo đang mở, mỗi lần một `make` (R-400).
  - Cách lazy stack xử lý view cuộn ra ngoài (bản đồ MapKit bị gỡ, chiều cao ước lượng ở cỡ chữ Dynamic Type lớn) chỉ thiết bị mới xác nhận.
  - `.task` của `CloudForecast` khởi động lại trong lazy stack không tốn mạng. Sau một giờ, mỗi lần quay lại vào khung nhìn tốn một lần tải dự báo (R-404).
- **5.6:**
  - Mạng an toàn `.minimumScaleFactor(0.5)` giữ lại, bỏ 0,08. Nó không hoạt động giữa lúc lật. Nếu lệch, một dòng tiếng Nhật nhỏ hơn một chút, không bao giờ co lại giữa chừng (R-445).
  - Hiệu ứng cross-fade hai bố cục là phần của duyệt thiết kế (dòng 3, R-448). Chỗ ngắt dòng nhảy là một dòng đo.
- **5.7:**
  - Bản đồ lúc nghỉ vẫn tải ô như trang sẽ làm. Một ảnh vẽ khi offline không được lưu (`raw`).
  - Một lần nạp trước lúc nghỉ chỉ vẽ bản đồ khi đã biết bề rộng probe và bảng màu của ngày (R-456). Chiều dài probe có bằng chiều dài trang hay không thì thiết bị quyết định. Nếu không, quy tắc cửa sổ của R-378 cũng đã không chạy.
  - Bìa không còn mờ đi dưới ngón tay. Đây là chủ đề của dòng 13 (duyệt thiết kế).
  - `HomeDays.body` đọc Tiết kiệm pin qua `onChange`: mỗi lần bật hoặc tắt chế độ này thì `HomeDays` vẽ lại một lần (R-482).
- **5.8b:**
  - Một số đường cong đổi cảm giác: nhiều `.smooth` thành `pick`/`arrive`, chuyến bay của explorer 1,4 giây còn 1,0 giây, độ nảy `interpolatingSpring` từ 0,1 lên 0,14, và nhả `SpendKeyStyle` giờ là lò xo (R-486, R-492).
  - Tiêu đề bìa và mặt trời giờ ra theo 0,2 giây thay vì 0,7 giây (R-501, dòng 13).
  - Vòng chi tiêu dùng `travel`, không nảy (R-503). Kim la bàn dùng `pick`, không vượt quá (A).
  - `UIView.transition` 0,35 giây nằm ngoài lint (R-492).
- **5.9:**
  - `UIImpactFeedbackGenerator.init(style:)` và `UIFeedbackGenerator.init()` có `deprecatedAt 27.0` trong JSON của Apple. SDK 26.2 không cảnh báo. Đến ngày CI chuyển sang SDK iOS 27 thì thành lỗi Critical theo luật 0/0, khi đó đổi sang `init(style:view:)` (iOS 17.5+) gắn với key window (R-466).
  - Chọn lại một chuyến khi lần kết thúc trước của nó đang nhả thì chuyến đó bị chặn bắt đầu cho tới khi lần nhả cũ hạ cánh. Hành vi cũ, giữ nguyên.
  - Bàn phím rời: bàn số vẫn hiện trong lúc gõ. Cần duyệt thiết kế, dòng 6 (R-496).
- **Đợt sửa cuối:**
  - **R-519 (M-1).** Kéo panel bản đồ từ cỡ lớn xuống cỡ vừa rồi xuống cỡ thấp trong vòng 0,38 giây thì bản đồ không bay tới mục đang đọc. Nó đứng yên cho tới lần cuộn hay chạm kế tiếp. Cách sửa là một dòng: chỉ huỷ `settling` khi panel lên lại cỡ lớn, và khi đổi ngày.
  - **R-520 (N-1).** Chú thích của `NetworkStatus` ghi "Chờ mạng", còn nhãn trên màn hình là "Chờ có mạng".
  - **`TalkShowFit` đo hai lần cho mỗi cỡ thử**, nên tối đa 16 lần cho mỗi chiều xoay, mỗi câu một lần. Một dòng trộn chữ Latin với kana có thể bị đếm thiếu dòng. Sai lệch nghiêng về phía cho qua, và § 5.6 bước 4–5 kiểm điều này.
  - **Một dòng chỉ có trong bản Release** (`FujiTerrainSnapshot.swift:365-366`, nhánh `#else` của `pictureOnly`) chưa được CI biên dịch, vì CI build bản Debug.
  - **Những gì `lint-motion` không thấy:**
    - animation tự dựng bằng `Animation(_:)`, cây code hiện không có;
    - `.phaseAnimator(`, cây code hiện không có;
    - `systemOverlay…`, chỉ có trên visionOS;
    - `UIView.transition` (UIKit, `Theme.swift:66`, đã chặn theo Giảm chuyển động).

## Các phán quyết đã đưa ra (nguyên văn từ sổ theo dõi, theo thứ tự)

Mỗi dòng ghi quyết định, lý do và cái giá nếu sai ("cost if wrong"). R-301..R-319 là phán quyết trước khi chạy, lúc quét kế hoạch. Phán quyết của Bước 0 (R-200..R-210) nằm trong PR #9.

- **R-301:** split 5.8 — 5.8a (`ios/JP27/Design/Motion.swift` with the five tokens + `reduced`, and the "Chuyển động" section of ios/README.md beside "Rung") goes before 5.1; 5.8b (map every call site, `.blurReplace` → `.opacity`, `scripts/lint-motion.mjs` with a node test written RED first, the step in the `data` job, Reduce Motion device step) is the last Phase 5 task — 5.1, 5.3, 5.4, 5.9 consume `Motion.arrive/pick` and 5.8 sits after them — cost if wrong: a few call sites touched twice (a token placed by 5.1–5.9, then checked by 5.8b's lint).
- **R-302:** 5.5 before 5.3 — 5.3 Step 4 puts the second map in 5.5's `LazyVStack` — cost if wrong: none (5.5 depends on nothing in 5.3).
- **R-303:** Bước 1 (0.2 code) before every Phase 4 task; the baseline commit is 0.2's last reviewed commit (after its fix rounds, before 4.1's first commit), its SHA written into docs/perf/2026-11-baseline.md by a docs-only commit right after — a commit cannot name its own SHA — cost if wrong: the owner measures a build with a 0.2 fix round in it; it still has no Phase 4–5 code.
- **R-304:** 4.2 moves the session calls of both `Speaker` and `TalkListener` (startAudio, giveSessionBack, deinit) in one task; who holds the session (none/speaker/listener), a release pending or not, the prior setup, the last category set, are a pure state machine in TripKit (`Audio/AudioSessionPlan.swift`: events in, ordered commands out) with tests and a mutation probe; R-146/R-150 semantics unchanged (Speaker idle: deactivate with notifyOthers, then the prior category; mid-line: the Speaker's category, the one place, and the Speaker's release ends it); T1 xhigh — cost if wrong: one TripKit type more than needed.
- **R-305:** the plan's `@concurrent static func activate/deactivate` would run on the global pool with no order between two calls, against spec B2 ("serial queue riêng"): one private serial `DispatchQueue(label:)` owned by a `nonisolated final class AudioSessionQueue: Sendable` in the app runs each command batch in one `queue.async` block, awaited through a checked continuation; the isBusy retry is `queue.asyncAfter(150 ms)` on the same queue; never `DispatchQueue.global()`, never `Task.detached`; `TalkListener.startAudio` awaits activation before `engine.start()`; `isolated deinit` enqueues its give-back without awaiting — cost if wrong: a session call waits ≤ 150 ms behind another on the audio queue, never on main.
- **R-306:** 5.9 splits `RideLiveService.start(_:model:)` into `select(_:model:)` (synchronous: the same-ride guard, ending the previous activity, the R-153 alarm rule, clock, tracker, timetable alarm, `ride`) and `begin(_ rideID: String, model:)` (`Activity.request` with `isAvailable`, `location.startLive`, `lastState`, `update`), a no-op unless `ride?.id == rideID` and the ride is not closing; `start` stays select + begin for `autoStartRide` and the deep-link start; only the two animated call sites (TodayTab, RideView) use `withAnimation(Motion.pick) { select }` then `Task { @MainActor in await Task.yield(); begin }`. One Live Activity (3.4a) and R-153 unchanged; the reviewer traces both clocks and "select A, select B, begin A" — cost if wrong: a ride selected and replaced within one yield gets no Live Activity (the newer one gets its own).
- **R-307:** `ExpenseDraft` gains `longNote: Bool`; `make` keeps the edit seed rule (`Yen.isValidEntry` else 0) and `longNote` (> `LedgerValidation.maxText`); `save()`, the save-failure path (`persist`/`logExpense`, `saveIssueAlert`) and every ledger read stay as they are; `lint-saves` stays clean — cost if wrong: none.
- **R-308:** 5.3 is written as the fallback, right whatever the spike shows — hero = cached `MKMapSnapshotter` picture; the live `Map` mounted only after `transitionSettled` and while stable-online, under the picture; the picture removed afterwards (R-311); the spike goes to the device doc as the owner's step; a later task trims the live map if snapshots turn out 3D — cost if wrong: one live map mounted after the zoom for nothing.
- **R-309:** 5.1/5.2 before/after screenshots and the design reviews go to docs/perf/2026-11-device-perf-phase4-5.md; the Phase 4–5 PR carries "Cần duyệt thiết kế"; the owner decides the merge — cost if wrong: none (nothing merges without the owner).
- **R-310:** 4.1 Step 3's "`SnapshotStyler.apply` off main" is not possible on MapLibre 7.0.0 — the header says the style can be changed only in `mapSnapshotter:didFinishLoadingStyle:`, delivered on the thread that started the snapshotter, which must be main (the code's documented rule); apply stays on main, and the step is met by not rendering until the transition settled (so apply never runs inside a zoom) and by moving everything that does not touch the `MLNStyle` (fingerprint, key, file read/write, JPEG encode/decode) off main — cost if wrong: one apply on main after the zoom (about a frame).
- **R-311:** `FujiTerrainMap` is a SwiftUI `Map`, which reports no "finished drawing"; after the live map is mounted (R-308) the picture stays a fixed beat (0.8 s) and then goes with `Motion.arrive`; never removed while offline (no live map then) — cost if wrong: a short partial-terrain flash under a fading picture.
- **R-312:** 5.4 before 5.3; `NetworkStatus.online` becomes the stable value built on 5.4's `Debouncer` (2 s trailing, published only when different), `raw` the instant one; the 5.3 brief rules every reader (network work and disk-write gates → `raw`: TripMap:969, AppModel:345, FujiFinderView:84, CloudForecast:99, Settings:786/:804/:806; what is drawn → `online`: FujiView:96/:144/:545, FujiMap:406/:434/:448/:456, CloudForecast:43) — cost if wrong: a reader on the wrong one flickers or waits 2 s for the network.
- **R-313:** `enum Haptic` already exists (Components.swift: `press`/`snap`/`page`); 5.9 extends it (stored generators, `prepare(_:)`) keeping the three funcs and their feel (style, intensity), and LedgerSync's success haptic goes through it — cost if wrong: none.
- **R-314:** 4.1 writes snapshots as JPEG 0.85 only (`<frameID>-<hash>.jpg`, the plan's Interfaces), not HEIC (Step 2) — one extension keeps read, prune and trim simple — cost if wrong: files about 1.5× a HEIC's.
- **R-315:** 4.1 keeps the real folder `Caches/MapSnapshots` (contract § 4.4's `Caches/Snapshots` means it); the old `.png` files there are deleted by the launch trim (a cache, re-drawable); `prune(keeping:)` deletes only files whose frameID (split at the LAST "-", hash has none) equals the key's, never when the frameID is empty; frameIDs made safe for a file name — cost if wrong: every static map drawn once again after the update.
- **R-316:** 5.7's "at most 3 running, a new one cancels the oldest" is a pure TripKit type with tests and a mutation probe — cost if wrong: one small type.
- **R-317:** SwiftUI gives no completion for the zoom (sheets, zoomed pushes, the phrase-card cover); 0.2 uses one UIKit probe — a zero-size `UIViewControllerRepresentable` in the destination that reports the end of its hosting controller's appearance transition (`transitionCoordinator`'s completion when there is one, else `viewDidAppear`), capped at 1 s so it never stays false — for sheets (`SheetLayer`), pushes (`RouteHost`, `FujiPageHost`) and the phrase card; it drives both `transitionSettled` and `TransitionMark.settled()`; the plan's "onAppear + 350 ms" and "two yields" are dropped — cost if wrong: settled early or late, bounded by the cap; the owner's signposts show it.
- **R-318:** `NavigationLink(value:)` has no tap hook: 0.2 begins a push's mark where the path grows (`didSet` of `todayPath/planPath/talkPath/spendPath` when the count rises) and a sheet's in `present`/`show`; names are a fixed set of `StaticString`s (one per Route case / sheet kind), so S1–S10 are told apart — cost if wrong: the tap → first-frame interval starts a few ms late (after the link's action, before the push).
- **R-319:** 5.1 is split — 5.1a: `DecodePlan` (TripKit, tests, mutation probe), the decode-size cache entry, `derive` (veil from the full decode via `CGContext` 160 px + blur; tone via `AmbientTone.sample`), `tones-2.json` written once per round (1 s debounce), veil off the actor (`@concurrent`), tone without network, the Debug deviation row; 5.1b: `ambient` composite (+ `Caches/Ambient`), `AmbientPhoto` as one image, no state written in the transition, `detailPage(heroFraction:)`, the page colour held to the first photo, no canvas animation — cost if wrong: one more review cycle.
- **R-320:** a Phase 4–5 task is done on its code when its review is clean and CI is green with 0/0 warnings; every "Đo", "chụp màn", "duyệt thiết kế", "spike trên máy" step is copied, per task with empty cells, into docs/perf/2026-11-device-perf-phase4-5.md (skeleton created by 0.2) and never reported as done; the final report says "chưa đo" — cost if wrong: a smoothness regression ships until the owner measures.
- **R-321:** `SnapshotKey.make` takes a content fingerprint computed once per `MapContent` (`SnapshotKey.fingerprint(...)`: route ids/points/colour/width/dash/opacity/dims, pin ids/coordinates/labels/numbers/titled and kind with `.done` read as `.stop`, heat, focus) plus frameID, size, scale, dark, insets, tile template, app build — the plan's raw `route:`/`pins:` coordinates would drop the style from the key and hash per body — cost if wrong: a wider TripKit API than the plan's.
- **R-322:** push marks are named per tab (`push.today`, `push.plan`, `push.talk`, `push.spend`) and sheet marks per sheet kind (`sheet.place`, …) — the four paths are type-erased `NavigationPath`s, a `didSet` cannot see the route — cost if wrong: MetricKit's per-name median mixes the routes of one tab (Instruments still tells S1–S10 apart by tab/sheet and time).
- **R-323:** 0.2 may edit `ios/JP27/Features/Plan/FujiView.swift` (one line, the settle modifier in `FujiPageHost`) — `FujiPageHost` lives there, not in JP27App.swift — cost if wrong: none.
- **R-324:** the histogram median is the grouped-data median (merge identical buckets, drop empty, sort, interpolate inside the bucket holding N/2; a middle exactly on an edge before a gap → the gap's midpoint); `scrollHitchTimeRatio` (one value per daily payload) is shown per day, not as a median; a small Codable digest is stored beside each raw payload (`MXMetricPayload` cannot be rebuilt from JSON); "keep 14" counts payloads (stamps) — cost if wrong: a median off by part of a bucket width.
- **R-325:** a mark nobody claims ends 3 s after its begin (`timeout`); end messages `settled`/`cap`/`replaced`/`timeout`; the one-pending-mark logic is a pure `TransitionSlot` in TripKit with tests; transitions open the MetricKit interval with `mxSignpostAnimationIntervalBegin` (iOS 15) so each name also gets its hitch ratio; `MXAnimationMetric.hitchTimeRatio` (iOS 26.0) shown beside `scrollHitchTimeRatio`, nil-safe; the phrase card gets the probe only (no mark); a hand-written nonisolated `EnvironmentKey` replaces `@Entry` (same `\.transitionSettled` API, default true); the baseline doc may add the App Launch template for S10 — cost if wrong: small (a few names or rows to change).
- **R-326:** the content fingerprint is computed once per `StaticTripMap` value (its init, from the view's immutable `content`, stored in a `let`) on main, and `MapContent.fingerprint` is a nonisolated computed property 5.7 can call off main — amends R-321 (where) and R-310 (fingerprint/key may run on main; file I/O, JPEG/JSON and the old PNG write still go off main) — measured 22 µs per 1 000 coordinates, the largest map ~800 points — cost if wrong: ~20 µs of main time per parent body that rebuilds the view (half of today's two hashes per body).
- **R-327:** the key's scheme is the page's scheme captured when the view is first built (`State(initialValue:)`) while `transitionSettled` is false, the current one once settled; a disk hit is read off main and shown at once even mid-zoom; only the snapshotter waits (settled or the plan's 400 ms cap, kept); `cached(_:) -> MapSnapshot?` (image + points + dark) and `cached(key) ?? image`; key byte rules gain a count before each group and each route's points; no frameID namespacing; the LRU trim reads the jpg's modification date, touched on read — cost if wrong: one extra snapshot after a zoom whose colour arrived late, or one image update inside a zoom on a disk hit.
- **R-328:** 4.1 may edit DayView.swift and StaysView.swift (pass the scheme), JP27App.swift (launch trim), SettingsView.swift (Debug frame-check link) and the device doc; the visited overlay's look (3 pt ring, SF number over the stop pin) is accepted for now and goes to the device doc as a design check beside the old picture — cost if wrong: a visible difference on visited pins the owner may ask to adjust.
- **R-329:** the picture over the live map also lifts on the user's first move of it (`onUserMove`), not only on `onReady`/3 s — Step 5's purpose is a map you can drag from the first touch, and a frozen picture over a moving map defeats it — cost if wrong: a drag may show half-drawn tiles for a moment.
- **R-330:** `MapFraming` moves to TripKit (`Geo/MapFraming.swift`, public, tests pinning point / near-point / area / minimum span / empty) — it is the one framing rule both the live map and its picture use, and pure — no mutation probe (moved, not new logic; the reviewer checks the tests pin each branch) — cost if wrong: one more public type.
- **R-331:** `MapSnapshots.Request` takes the content and its fingerprint as one value built by one init (content → fingerprint), so a request can no longer pair a content with another's fingerprint (R-321's staleness) — cost if wrong: one tiny type 5.7 must use.
- **R-332:** two concurrent stores for one frame are left as they are — the newer store or the launch trim heals either outcome (an older scheme's picture, or a jpg without its json, which reads as a miss) — cost if wrong: one redraw or one wrong-scheme picture until the next store.
- **R-333:** `StaticTripMap`, `SnapshotPins`/`SnapshotPin`, `MapSnapshots`, `SnapshotStyler` and `MapFrameCheck` move out of TripMap.swift into `ios/JP27/Design/StaticTripMap.swift` (project.yml takes every file under JP27) — the file grew to 1,398 lines and later tasks (5.4 TripMap, 5.7 MapSnapshots) touch both halves — cost if wrong: move churn in one fix round.
- **R-334:** `say` hands its line to the synthesizer only in its session batch's completion (the line asked for last), and an empty batch still passes through the queue — the synthesizer activates the session itself, outside our queue, so speaking at once could start in the old category or be cut by a release decided just before — cost if wrong: a line starts one queue turn and one main hop later (ms; longer only behind a slow deactivate).
- **R-335:** the isBusy retry's 150 ms is the queue's `asyncAfter`, but the retry itself is decided on main by the plan with the generation and enqueued on the same queue; a batch stops at its first failing step — a retry run blind from the queue could cut a line or listen started in those 150 ms, and a restore after a failed deactivate would set the prior on a live session — cost if wrong: one more main hop per retry.
- **R-336:** the prior's value lives on the audio queue (`Mutex` in `AudioSessionQueue`), the plan tracks only whether one is captured; setups are `Setup { speaker, listener }` in TripKit, their AV values written once in the app — the prior must be read on the queue in order, not on main before an await — cost if wrong: none (the serial order makes the symbolic steps exact).
- **R-337:** `@MainActor enum AudioSessionController` (plan, queue, release Task, Logger `audio`) + `nonisolated final class AudioSessionQueue: Sendable` in Media.swift; the brief's `Speaker.release` is superseded (a listen must cancel the release too); `ownsSession`/`takeSession`/`adoptSession` go — cost if wrong: a rename.
- **R-338:** Nghe's ticket is the generation its listen took (a stop from an older listener gives back nothing); a failed step reaches the plan before the waiter resumes — cost if wrong: none.
- **R-339:** `mediaServicesWereResetNotification` → `.mediaServicesReset` → `lastSet = nil` only; other reset effects are a residual in the report — under "set only when it differs" the Speaker would otherwise read in the default category for the rest of the run — cost if wrong: one event and one observer.
- **R-340:** all 4.2 device steps (Step 2 + correctness rows) go under § 4.2 of docs/perf/2026-11-device-perf-phase4-5.md; the Phase 1–3 checklist gets one pointer line under 3.4b (steps 4–7 on a 4.2 build) — cost if wrong: none.
- **R-341:** an "App builds" failure at package resolution with no compile step run is a runner fault, not the task's Critical — re-run the failed job once (no empty commit); a second such failure is reported in the final report and the task waits on a green compile — cost if wrong: one re-run of ~5 min.
- **R-342:** the deleted assertion comes back as the probe-#4 pin (a second busy failure while the retry waits → `[]`, then `retryDue` pinned as the plan does), even though the sequence is unreachable in the app — contract § 4.1 forbids deleting a test to get green, and the plan is a pure type that takes events in any order — cost if wrong: one test pinning an unreachable path.
- **R-343:** Minor 4 (`take()` keeps a stale `.waiting` deactivation) is left as is — every reader is gated by the generation, so nothing observable depends on it — cost if wrong: an equivalent mutant in later probes.
- **R-344:** ST-3 counts as passed (3/3), recorded with the leak; no tier raise; ST-3 is once-only so no further plant goes in the ledger — the findings' depth shows independent detection and a rerun costs one more xhigh review for a one-off check — cost if wrong: the task-reviewer tier stays at xhigh when max was warranted; the final whole-branch review at max is the net.
- **R-345:** the two zero-delay reschedule requests on a tap (`alternatives` didSet from its Toggles, `setClock` from the rehearsal buttons) stay as they are — B3 as the plan defines it covers toggleDone/toggleSkip/apply only, both are rare settings actions whose re-plan the user expects at once, and a 300 ms delay there changes what the screen shows right after the tap — cost if wrong: one possible hitch during a settings toggle's animation, listed for the final review.
- **R-346:** the controller re-reviews this round itself — a 6-line diff (one guard term, one comment, two doc rows) checked item by item against fix-4.3-r1.md: all four addressed, nothing else touched — a dispatched re-review would read the same 6 lines — cost if wrong: none beyond the final review.
- **R-347:** do not work around it; leave adc3ea0 as is, keep working, and ask the user in the next message to allow one force-push that rewords adc3ea0 (all later commits get new SHAs; the baseline a996140 is earlier and unaffected) or to squash-merge the Phase 4–5 PR — cost if wrong: a model name stays in one commit message until the user decides. Prevention: implementer-common.md now says to copy the two lines byte for byte whatever the model; every push from now goes through bin/push-gate, which refuses a range naming a model.
- **R-348:** a runner fault on one push is not re-run when the next push's run (adc3ea0, child of cd20769) compiles a descendant — its "App builds" result and warnings line stand for cd20769's code too; if it also hits the fault, re-run that one — cost if wrong: none (the descendant holds every line of cd20769).
- **R-349:** 5.8a's Minors go to 5.8b instead of a fix round — 5.8b rewrites the same README section and maps every call site, so it applies them where they bite (reduced on the bare token, modifiers after; a "Là" column; settle(velocity:) named; "Animation mới…" until the map lands; the 0.2 written once; a Reduce Motion device row) — cost if wrong: the README overstates for the length of Phase 5.
- **R-350:** no tier raise, no missed trap carried — cost if wrong: none.
- **R-351:** DecodePlan.serves = sourceIsFull || (longest ≥ ask && longest ≤ 2·ask) (P2); the brief's test 2 had decoded/asked swapped (it allowed a 2× enlargement) and test 3 runs with sourceIsFull — "như hiện nay" and the Vì sao both say a decode is only ever shrunk — cost if wrong: one more decode where an enlarged reuse would have looked acceptable.
- **R-352:** `DecodePlan.isFull(decoded:asked:)` (longest < ask; equal = downsample) in TripKit with tests, so the probe covers the off-by-one — cost if wrong: one more public func.
- **R-353:** nested `DecodePlan.Size` (Int pixels, `longest`) — SnapshotKey.Size is Double points — cost if wrong: none.
- **R-354:** tones-1.json ignored and left on disk (Photos/ is not an owned cache folder, § 4.4; a rebuildable cache, said in the report); no seed (it would mix 96 px tones into the new file and hide what the ≤ 0,02 check measures) — cost if wrong: each page opened before its tone is re-learned starts on paper once after the update.
- **R-355:** the Debug row prints both deviations (sample(full) and sample(160 px base) vs the old 96 px path) — cost if wrong: a few Debug-only lines.
- **R-356:** `Perf.mark("photo.decode")` per ImageIO decode and `Perf.mark("photo.tones")` per tones write, signposter only, through the existing Perf.mark — cost if wrong: two signpost events per decode/write in Release (negligible).
- **R-357:** T14 (a tone learned by veil()'s derive after tone() returned nil recolours a later body) accepted for 5.1a and carried into the 5.1b brief, whose colour-held rule closes it — cost if wrong: a page can turn from paper to colour on a later swipe until 5.1b lands.
- **R-358:** tone() keeps its album-size decode (inside 128 MB) — cost if wrong: ~1.9 MB per bundled photo, up to ~9.7 MB per large remote photo, of NSCache held until evicted.
- **R-359:** tones writes are serial (each awaits the previous write task) — cost if wrong: none.
- **R-360:** SettingsView.swift (Debug row) and the device doc are in 5.1a's files; commit subject per A6 (5.1a's scope, not the pre-composed hero) — cost if wrong: none.
- **R-361:** the photo.decode/photo.tones events use `Perf.signposter.emitEvent` instead of `Perf.mark` — `Perf.mark` also emits an mxSignpost, which R-356's "no MetricKit" excludes; R-356 is amended — cost if wrong: none.
- **R-362:** fix — every queued write awaits the previous one before its first cancellation check — cost if wrong: none (one line).
- **R-363:** `photo.decode` carries its src (public: bundle path or Commons URL); device rows (2)/(3) rescoped by src — the cover-day day page decodes once on first open (accepted R-351 cost; 5.7's prefetch at rest warms it) — cost if wrong: one decode on a cover day's first open, before 5.7 lands.
- **R-364:** `sourceIsFull` made exact from the CGImageSource's pixel size (longest sides), via `DecodePlan.isFull(decoded:source:asked:)` in TripKit with tests; the two-argument rule stays as the fallback when the size cannot be read — cost if wrong: one header-properties read per decode.
- **R-365:** report wording "computed from headers", Minor 1 (small asks draw whole decodes) listed as a residual with a scroll-hitch device row — cost if wrong: a hitch in the Plan tab's rows after the home has decoded its covers, found on the device.
- **R-366:** Important 3 (wiring not pinned) stays plan-shaped — no app test target, the brief's TripKit scope is DecodePlan; the re-review traces the ordering fix and the final review re-reads the wiring — cost if wrong: a later regression in the cache wiring passes CI.
- **R-367:** a controller commit adds one step before Build in tripkit.yml that removes the stale SwiftPM artifact entry (~/Library/Caches/org.swift.swiftpm/artifacts) — not a lint, the same build; cost if wrong: the MapLibre zip is downloaded on every App builds run (~20 s).
- **R-368:** `ambient(_:size:)` has no scheme in its signature or key — no layer depends on it, and the page's own scheme flips on a late colour (a second fade) — cost if wrong: none.
- **R-369:** the composite canvas is the photo's own pixels in the frame, never upsampled (a Commons landscape 460×598, not 800×1040) — "at the source's width" read as "no larger than the source" — cost if wrong: none visible (the screen samples the same pixels).
- **R-370:** `detailPage(title:heroHeight:)` stays for the three constant heroes (AtPlaceView 360, Fuji root 480, plain place 440) without state; album pages get `detailPage(title:heroFraction:)` — cost if wrong: two spellings of one modifier.
- **R-371:** threshold = ((containerSize.height − contentInsets.top − contentInsets.bottom) × f).rounded(), the hero's own rule; the inset equality is UNVERIFIED, device row 9 — cost if wrong: the title comes a few points early or late.
- **R-372:** no tone asked for the other photos (nothing reads them once the colour is held; `onScrollPhaseChange` sees the page, not the pager); the one late colour decision after settle animates with Motion.arrive; T14 closed by no body reading knownTone + held @State + a decided flag keyed by src — cost if wrong: one page-wide colour fade after the zoom on a first open.
- **R-373:** Reduce Transparency keeps today's layers and look without `drawingGroup` — cost if wrong: none.
- **R-374:** on a composite miss with the album decode in memory, the first frame shows that decode as a stand-in and the composite fades in over it (removed in the animation's completion) — the literal placeholder-then-fade would be a lasting regression of the day page's first frame (a tap opens ~100 ms after press-down, too soon for 5.7's touch prefetch to compose) — cost if wrong: ~15 lines and a few frames where the sharp part has no veil under it.
- **R-375:** a pure TripKit `AmbientFrame` (canvas size, fill rect, stop table, stable file name with recipe version, trim choice, hero height rule) with tests and a mutation probe — cost if wrong: one more TripKit file.
- **R-376:** launch trim of `Caches/Ambient` to 40 MB by LRU, next to MapSnapshots.trim, in that folder only — cost if wrong: an older composite recomposed (~tens of ms off main).
- **R-377:** 5.1b updates the README paragraphs it makes wrong (not "Chuyển động", not "Chưa đổi…") — cost if wrong: none.
- **R-378:** one hero height rule `AmbientFrame.heroHeight(length:fraction:)` used by containerRelativeFrame, the threshold and later 5.7; per-page fraction constants named beside their views — cost if wrong: none.
- **R-379:** `photo.ambient` signpost per composite (made|disk), signposter only — cost if wrong: negligible.
- **R-380:** 5.1b's own commit subject (not "one decode per photo", 5.1a's) — cost if wrong: none.
- **R-381:** compositing is "việc nền mới … ghép ảnh" of contract § 4.2, so it is cancelled when its last waiter goes and makes no new composite in Low Power Mode (a held one is still shown; otherwise the album decode as the stand-in shows); amends go-5.1b's "runs to its end", which contradicted the contract — cost if wrong: a composite cancelled by a quick swipe is made again on return; in LPM the hero has no veil under the fade.
- **R-382:** PageTone's decision rule is lifted into a pure TripKit generic (decided at init iff known, once per key, nil closes it, the T2 key-change rule) with tests and a probe; AmbientPicture's display rule stays in the app (fixed by R-383) — the R-357 closure is the one behaviour carried across tasks, worth pinning; the display rule is a view's lifecycle — cost if wrong: the stand-in lifecycle is pinned only by review and device rows.
- **R-383:** fix Minor 1 (clear `shown` on a photo change; a completion removes only its own src's stand-in) — cost if wrong: none.
- **R-384:** fix Minor 2 (restore .normal before endTransparencyLayer) — cost if wrong: none.
- **R-385:** fix Minors 3–5 (FujiSpotAlbum, screenshots folder docs/perf/screens-5.1b/, two small tests) — cost if wrong: none.
- **R-386:** 5.2 ST-2 4/4 blocking, no raise — cost if wrong: none.
- **R-387:** the soft rise is baked into a small image of the backdrop behind the foot (spec C2 "gradient trộn sẵn vào ảnh"); no mask/material/Canvas/drawingGroup in HeroBlur — the brief's Step 1 contradicts Step 2 otherwise — cost if wrong: ~60 lines of bake code a Canvas might have avoided; the look differs from the material (design review).
- **R-388:** the bake runs synchronously on main in the foot's GeometryReader, bounded by the backdrop's own pixels (≤ 160 px a side for a veil), memoised in a non-observed @State box keyed by instance and rounded sizes — not the contract's "chặn hay nặng" (no decode, no I/O, a few thousand pixels); off main would show a veil-less foot on every cache hit — cost if wrong: a fraction of a ms on main per bake on an open's first frame (device row 4); the fix is @concurrent at the price of a first-frame foot without veil.
- **R-389:** HeroFoot geometry in TripKit with tests, reusing AmbientFrame.fill/Stop, plus a bound test; mutation probe on layout — cost if wrong: none beyond one small file.
- **R-390:** the paged plain hero shows the current page's veil, resolved in body by a sync cachedVeil read (no frame without it on a hit, no state write on a page change); the swap is instant; Motion.arrive only on an arrival after a miss; per-page veils are the design-review fallback — cost if wrong: the foot's blur pops at the page change (row 5).
- **R-391:** Reduce Transparency → no veil, shade 0.55 — cost if wrong: the foot is less legible than the old near-opaque material (row 6).
- **R-392:** Low Power Mode → only a veil in memory, none derived, `making` in the task id; the in-frame bake still runs — contract § 4.2, the R-381 analogue — cost if wrong: an LPM page's foot has no veil.
- **R-393:** README — trim :288 to the menu clause (5.9's), correct :182, one "Mượt ở 120 Hz" bullet saying the pixels change — cost if wrong: none.
- **R-394:** API DetailHero(veil: Photo?, backdrop: UIImage?) + HeroBlur(backdrop:heroHeight:); backdrop wins; Fuji passes nil written out until 5.3 — cost if wrong: 5.3 changes one call site.
- **R-395:** 0.55 is the shade's bottom stop with no backdrop; 0.42 with one — the brief's wording, trap B4 — cost if wrong: one constant.
- **R-396:** a `hero.foot` signpost per bake, signposter only — cost if wrong: none.
- **R-397:** B6/B9 row wording, T8 note, T14 fallback, rows 1–10 (5, 6, 9, 10 design review, screens-5.2/) accepted as proposed — cost if wrong: none.
- **R-398:** 5.5 ST-2 3/4 blocking — one missed (< 2), so no tier raise; the missed trap is carried into the go — cost if wrong: an identity bug that keeps an old draft gets through if the implementer's trace is wrong (review checks it).
- **R-399:** the implementer must trace `.shared` = the environment's model and that every expense presentation gets a fresh State (AppSheet.id includes place and yen), and stop if a path keeps the old draft — cost if wrong: a second expense sheet opens with the first one's draft.
- **R-400:** accept SheetHost re-running per GPS fix while the editor is open (cheap), on condition ExpenseEditor stores nothing that differs between inits; device row — avoiding it needs JP27App changes outside the task — cost if wrong: a switch + init + make per fix; if the editor's body re-ran, a redraw per fix (row catches it).
- **R-401:** PlanStationRow takes only what it draws (two Bools, or progress for the one row that draws it), pixels unchanged — the task's point is no page-wide redraw per fix — cost if wrong: six lines; a row that loses an input it drew (review checks inputs vs drawing).
- **R-402:** A1 (a) guard editing == nil only; A2 seed the note prefix with longNote from the full count; A3 category tap on Motion.pick; A4 (a) FujiView :26 lazy; A5 RideView page stack lazy — matches today's behaviour (A2) and the trap list (A1) — cost if wrong: none beyond one line each.
- **R-403:** Nearby.plannedStop(near:day:store:) + plannedStopKm 0.15 in TripKit with NearbyTests on the bundled store; device doc § 5.5 — the brief ruling asked for the TripKit move — cost if wrong: none.
- **R-404:** CloudForecast's .task restart in a lazy stack costs no network (ForecastService.hours serves memory < 1 h or offline) — note in the report — cost if wrong: one forecast fetch per return into view after an hour.
- **R-405:** grep the lazy parts for ScrollViewReader/scrollTo/.id(/scrollPosition/onGeometryChange and say whether a target can be unmade — N1 — cost if wrong: a scroll-to that misses its target.
- **R-406:** the rest of the plan accepted as proposed — cost if wrong: none.
- **R-407:** lift the display rule (RT → none; backdrop wins; held for src; cached; NEW last-shown for src, kept in a non-observed @State box) and the derive rule into TripKit HeroFoot as pure generics, RED first — the rules are pure over plain values, later tasks (5.3 backdrop, 5.7 prefetch) touch them, and the eviction residual is closed in the same lift — cost if wrong: ~40 lines of TripKit for rules a device row would also show.
- **R-408:** add the probe's gap tests A (foot wider than hero: aspect + max side), B (fractional height rounding), C (non-integer hero width), D (≥ 100 000 → nil) — cost if wrong: none.
- **R-409:** device rows — row 4 names the caller if draw is inlined; an alignment-continuity check on a strong horizontal — cost if wrong: none.
- **R-410:** the .task attached to every hero, returning at once without a veil, is accepted as read of R-394 — conditional attachment would change the hero's identity — cost if wrong: one no-op task per Fuji/plain hero open.
- **R-411:** the duplicated alpha gradient (4 lines vs PhotoCache.fadeGradient) stays; parked for the final review — sharing it would touch 5.1b's compositor — cost if wrong: four duplicated lines.
- **R-412:** 5.4 ST-2 5/5 blocking, no raise — cost if wrong: none.
- **R-413:** Step 3 adds no comparison — the existing `guard content != applied` (TripMap :390) already skips apply on equal inputs; the fingerprint would hide a just-visited stop (SnapshotKey counts done as stop); amends my brief addendum "use the fingerprint" — cost if wrong: MapTab still builds MapContent.day and runs == per active change (equal-buffer fast path), not measured here.
- **R-414:** the map's content (focus, halo, side pins) follows the camera via @State shown, set in the debounced fire and at once by every hand choice; the timeline, strip and side card keep active — during a swipe the map's inputs do not change, which is what Step 3 expects — cost if wrong: the map's emphasis lags the timeline by 150 ms after a rest (device row).
- **R-415:** Motion.travel only gates Reduce Motion for the MapLibre camera (animated: false); MapLibre keeps its own duration — matching 1.0 s would change every flight — cost if wrong: the travel token does not time map flights (5.8b notes it).
- **R-416:** keep Value: Sendable & Equatable verbatim; no de-duplication inside; callers de-duplicate in fire — cost if wrong: none.
- **R-417:** three extra Debouncer tests (late wake, Bool, let go) accepted; mutation probe after review — cost if wrong: none.
- **R-418:** A2–A5, MapFlight nonisolated, cancels on move/day change, fire-time reads, T7 comment, device rows accepted as proposed — cost if wrong: none.
- **R-419:** lift the draft's pure seed rules (edit amount, opener amount clamp, note prefix + long) into TripKit Money with tests, RED first; the place onChange guard stays in the app (view lifecycle, as R-382) — they decide saved money data (R-307) — cost if wrong: ~30 lines of TripKit.
- **R-420:** device row 2 adds a walk into another planned stop's range — cost if wrong: none.
- **R-421:** correct the report's second-map claim and two citations — cost if wrong: none.
- **R-422:** PlanRideLive's model.live reads accepted as read of the brief (the live card) — cost if wrong: none.
- **R-423:** 5.3 ST-2 6/6 blocking, no raise — cost if wrong: none.
- **R-424:** FujiTerrainSnapshot(camera: FujiCamera.Shot, spots:, selection:, plotInset:, scheme:) reading its own size; FujiCamera.area/.spot wrap Shot; mkCamera in one place — the brief's init cannot be called — cost if wrong: an interface 5.7 must learn (it prefetches nothing Fuji today).
- **R-425:** brief's file name with area-/spot- prefix + <stem>.json sidecar (points + fingerprint, recipe 1), mismatch overwritten in place, picture then JSON, atomic; new folder, no old format — the snapshot draws no pins and the name holds no content — cost if wrong: one extra small file per picture.
- **R-426:** TripKit SteadyValue (on Debouncer, first report at once, only-when-different vs last published) and TerrainPicture (stem, fingerprint, mount/cover/beat rules) with tests + probe — cost if wrong: two small files.
- **R-427:** offline + saved picture → the picture is the cover; offline + none → plot; online miss → live map at settle under placeholder, picture drawn in the background; draw gates settled/!LPM/stable online in the task id, store gate raw; A4 one rule — literal R-308/R-311 — cost if wrong: a first visit shows the placeholder for the 0.8 s beat.
- **R-428:** both spot uses share the component and mount rule — the spike may show a flat picture — cost if wrong: a live map mounted on a card where a picture would do (trimmed later in one place).
- **R-429:** latch the explorer's live map too (Step 3) — cost if wrong: in a long outage the explorer keeps a live map with only loaded tiles instead of the compass plot.
- **R-430:** the hero's area flight takes Motion.travel (1.0 s) instead of .smooth(1.2); the explorer's 1.4 s fly untouched — 5.8a: touched call sites use tokens — cost if wrong: the hero flight is 0.2 s shorter (design).
- **R-431:** Debug rows (picture-only switch, usage + Xoá of Caches/Fuji only) — cost if wrong: none (Debug only).
- **R-432:** trim Caches/Fuji at launch to 40 MB LRU, pairs together, own listing only, folder kept; memory 32 MB — overrides the pre-mortem's "no trim": orphans after a future stem/recipe change, and consistency with the other two caches — cost if wrong: ~15 lines.
- **R-433:** the backdrop reuses PhotoCache.derive's 160 px veil, Media.swift untouched, the tone discarded — cost if wrong: one wasted tone sample per picture.
- **R-434:** 15 s draw cap; the raw reader list, T1–T20, traitCollection, POI filter, HEIC-else-JPEG, A8, A9, device rows accepted — cost if wrong: none.
- **R-435:** locate() sets shown = active; every move(/cancel caller accounted for; device row — R-414 — cost if wrong: none (one line).
- **R-436:** fix the panel-down Task — cancel the flight when leaving .large, re-check the day after its sleep — a real stale camera path the diff touches (R-418) — cost if wrong: none.
- **R-437:** row 7 reworded; day-change frame/setContentInset/choose's .smooth listed for 5.8b, no code change — R-415 scoped the gate to camera — cost if wrong: under Reduce Motion a day change still animates its framing until 5.8b.
- **R-438:** pin the Debouncer fully — no de-dup ([7,7]; [7] within the delay), a stale task never clears the newer handle (LateSleep wake-by-index), a failing sleep drops the value — closes probe gaps M9/M5/M12 and Minor 4 — cost if wrong: none.
- **R-439:** the panel Task's missing stage re-check is parked for 5.8b (call-site sweep) and the final review, no 5.4 fix round 2 — pre-existing, outside 5.4's diff, the second fly targets the same item so the visible cost is one redundant camera move — cost if wrong: a panel flick or a tap within 380 ms of the panel dropping animates the camera twice to the same place until 5.8b.
- **R-440:** ST-2 3/3 blocking, no effort raise; no mutation probe on LargestFit — contract table lists none for 5.6 and the exhaustive-threshold + call-count tests kill the search's mutants — cost if wrong: an off-by-one in the search reaches the final review.
- **R-441:** memo key = three texts, sideways, typeSize, rounded box (+ legibility weight, R-442); static on a private main-actor TalkShowFit, 64, cleared when full — the brief's key misses the box and the texts — cost if wrong: a few extra measurements.
- **R-442:** Bold Text enters the measurement (legibilityWeight in the key, trait collection for romaji/vi, .heavy for the Japanese when bold; one-step-heavier mapping UNVERIFIED) — plain .bold measures narrower than SwiftUI draws under Bold Text — cost if wrong: under Bold Text the 0.5 net shrinks the Japanese a little (device row 5).
- **R-443:** Reduce Motion explicit — TalkTurn degrees 0 (fade only), base rotation kept, Motion.reduced(settle) — don't rest on hasMotion's runtime replacement alone — cost if wrong: none (both paths give a fade).
- **R-444:** keep kCTLanguageAttributeName "ja", effect UNVERIFIED in comment/report — matches the display's ja_JP locale — cost if wrong: the attribute is ignored; the 0.5 net covers a fallback mismatch.
- **R-445:** .minimumScaleFactor(0.5) safety net kept, 0.08 gone — inert mid-turn (fixed box per copy, laid out once) — cost if wrong: a mismatch shows as a slightly small Japanese line, never a re-fit mid-turn.
- **R-446:** one README bullet (ios/README.md "Mượt ở 120 Hz") stating the cross-fade look change — README documents each smoothness change (5.1/5.2 precedent) — cost if wrong: one bullet to drop.
- **R-447:** a phrase.fit event per memo miss (as hero.foot, R-396), no tap mark; device row 7 counts it (2 at open, 0 on drag-dismiss) — whether the zoom transition resizes the root per frame is UNVERIFIED and the event exposes it — cost if wrong: one signpost event in the trace.
- **R-448:** device row 2 split — line-break jump stays a measure row; the two-layout cross-fade look becomes a duyệt thiết kế row; rows 4/5 also check the Japanese isn't shrunk by the net — N2 is a look change — cost if wrong: none.
- **R-449:** ST-2 4/4 blocking, no effort raise — cost if wrong: none.
- **R-450:** the cover's .plain press hook = a ButtonStyle whose body is PlainButtonStyle().makeBody(configuration:) + onChange(isPressed) (public, apple-decl iOS 13.0); fallback to the agent's (a) + duyệt thiết kế row only if CI refuses it — keeps the system's pressed look exactly — cost if wrong: one CI round to fall back.
- **R-451:** feelsPages(_:rested:) in Components.swift (outside the list), one phase handler — two onScrollPhaseChange on one scroll view could silence the haptic or the prefetch — cost if wrong: one more file in the diff.
- **R-452:** home probe + page: parameter, value in a non-observed box; R-378's window rule dropped for 5.7 — the pushed page's container excludes the tab bar/accessory, the window doesn't — cost if wrong: the prefetch warms a composite key nobody reads (device row catches it).
- **R-453:** a prefetch never downloads a photo; on touch the map is stored() only, drawn only from a rest — roaming data, and MLNMapSnapshotter's main-thread styling stays out of the push zoom — cost if wrong: a touched day never drawn opens without its map in the first frame (as today).
- **R-454:** the cover's .place prefetch = tone + albumPixel decode + veil, no composite — the sheet's length is unknowable beforehand — cost if wrong: the place page's composite fades in after open (as today).
- **R-455:** a running key asked again becomes newest and is escalated — it is the one wanted most — cost if wrong: an older wanted key cancelled one admission early.
- **R-456:** a rest prefetch draws a map only with the probe width and day scheme known; device row "no map.snapshot / photo.ambient made after opening a rested day" — a wrong key prunes the page's own picture (T1) — cost if wrong: none beyond a skipped map warm.
- **R-457:** T6 memory (≈6–7 MB per composite in the 128 MB NSCache) is a device row, no code — out of scope, PhotoCache policy — cost if wrong: home covers re-decode after resting on many days.
- **R-458:** ST-2 3 + 1 partial of 4 blocking, no effort raise (fewer than 2 missed); the B2 gap ruled in go-5.9 (R-460) — cost if wrong: none.
- **R-459:** no rigid generator — nothing fires one through UIKit; the keypad's key stays sensoryFeedback — cost if wrong: none.
- **R-460:** a non-observed `leaving` latch on Save/close so WillHide doesn't insert the pad into a leaving sheet; swipe-down may bring it back (a cancelled drag needs it); device row 6 extended — cost if wrong: a pad flash as the sheet leaves by swipe.
- **R-461:** select also sets status from the side-effect-free projection (offTrack filter), so the morph's first frame has it — the split otherwise shows one "waiting" frame — cost if wrong: three lines; the report proves no alarm/push/record on that path.
- **R-462:** README — remove the paragraph, add the Rung sentence and one 120 Hz bullet — README documents each change — cost if wrong: two lines to drop.
- **R-463:** ride.select event + ride.begin interval on Perf.signposter — the owner's Time Profiler rows need them — cost if wrong: two signposts in traces.
- **R-464:** the begin gate (select re-arms, closing/released, begin true once for the selected non-closing ride) lifted into TripKit with RED-first tests incl. the R-306 interleavings; the app asks it — twice an untested inline rule came back Important (R-407, R-419) — cost if wrong: a small type that partly tests a copy of app state.
- **R-465:** SettleStyle's spring left to 5.8b — 5.8b's mapping — cost if wrong: none.
- **R-466:** UIImpactFeedbackGenerator.init(style:) deprecatedAt 27.0 parked (SDK 26.2 warning-free) — cost if wrong: a warning when CI moves to the iOS 27 SDK (then a Critical by the 0/0 rule).
- **R-467:** one internal TripKit pair-eviction helper (stem rule as a parameter) behind both SnapshotKey.evicted and TerrainPicture.evicted; existing trim tests unchanged — two copies of one eviction rule drift — cost if wrong: a small refactor of 4.1's trim (its tests pin it).
- **R-468:** stored checks Task.isCancelled after the disk read before any observed write — the doc comments promise it — cost if wrong: none.
- **R-469:** the terrain backdrop is not derived in Low Power Mode or under Reduce Transparency (HeroFoot.derivesVeil's rule) — contract § 4.2; HeroFoot.under drops it under RT anyway — cost if wrong: an LPM visit shows the 0.55 shade with no blurred terrain.
- **R-470:** once the live map has mounted, a picture finished in the background doesn't become the cover (placeholder until the lift), as a TripKit cover rule with a test — two fades within a second on a smoothness task — cost if wrong: a first online visit never shows the picture during the beat (it's kept for the next visit).
- **R-471:** device duyệt thiết kế row for offline-after-lift + area change, no code — A5 latch is ruled; the look is the owner's call — cost if wrong: none.
- **R-472:** .accessibilityHidden(cover != nil) on the live map — one label at a time — cost if wrong: none.
- **R-473:** makings keyed by stem + fingerprint — free — cost if wrong: none.
- **R-474:** report row 9 → FujiView.swift:149 — cost if wrong: none.
- **R-475:** the 698-line view+cache file and the 4-line scaledToFill repeat parked for the final review — StaticTripMap precedent, the brief's one-file list — cost if wrong: a split later.
- **R-476:** the offline-during-beat + area-change case gets a device duyệt thiết kế row in the final fix wave (doc only), stale report line refs left (workspace file) — R-470's trade-off as ruled; no code — cost if wrong: the owner meets the case without a row until the final wave.
- **R-477:** UITraitCollection(mutations:) in place of R-442's (traitsFrom:) — the implementer reports (traitsFrom:) deprecated since iOS 17, which would break 0 warnings; same two traits; the reviewer verifies — cost if wrong: none (CI's warnings line decides).
- **R-478:** the four 5.6 Minors parked for the final fix wave (line count by one measured line of the same string; the "no room" comment + device row 4 note; LargestFit other-ranges cost pins; drop @testable) — none changes behaviour beyond how close the size gets to the largest fit; the 0.5 net covers a 7-line acceptance — cost if wrong: a Japanese line slightly smaller than it could be on some phrases until the final wave.
- **R-479:** my R-450 primary form was wrong — PlainButtonStyle is a PrimitiveButtonStyle (its Configuration has no isPressed), so it can't be wrapped by a ButtonStyle; R-450's fallback applies: a ButtonStyle that draws the label unchanged and reports isPressed, plus a duyệt thiết kế row (the system plain style's pressed dimming is lost) — cost if wrong: the cover photo doesn't dim on press (owner's design row decides).
- **R-480:** one fix round carries CI's Critical (R-479 fallback) and the review's Minors 1 and 3 — one round instead of two — cost if wrong: none.
- **R-481:** a touch on a running rest prefetch marks it touched; a touched run that hasn't started its map draw reads stored() only; a draw in flight is left (shared) — R-453's intent: no snapshotter styling in the push — cost if wrong: a touched day whose rest run hadn't reached the map opens without a fresh map picture (as on a plain touch).
- **R-482:** lowPower read in HomeDays.body through onChange(of:) parked — one re-render per LPM toggle, rare, disclosed, it's how SwiftUI observes — cost if wrong: one HomeDays re-render when Low Power Mode flips.
- **R-483:** device rows 4/5 reworded "at most one per rest / per touch; a second when the position lands after the rest or on a metro-line tap" — so a true result can't fail — cost if wrong: none.
- **R-484:** Prefetch.day/place take at: Moment {rest, touch} (carrying the two priorities) + page:, recorded in interfaces § 5.7 — the moment drives more than priority (draw vs stored, LPM) — cost if wrong: none.
- **R-485:** ST-2 3 + 1 partial of 4 blocking, no effort raise — cost if wrong: none.
- **R-486:** mapping — fade→arrive, choice/count/highlight→pick, moving panel/row/section→settle, eye-following ≥ 0.7 s→travel; explorer fly 1.4→travel 1.0 — the brief had no line for default .smooth — cost if wrong: some curves feel different (device rows).
- **R-487:** wider lint (.linear, .easeIn, .timingCurve, bare withAnimation {, *Keyframe() with an "allowed" test per homonym; .default flagged only if matchable as an Animation argument — cost if wrong: a false positive to one-off.
- **R-488:** one-off marker on the same line or the comment line above, reason required (tested) — long calls wrap — cost if wrong: none.
- **R-489:** TripMap :162/:176/:181 gated on reduceMotion like :185 — 5.4's owed list — cost if wrong: a day change under Reduce Motion stops animating its framing (intended).
- **R-490:** every press/pick/settle/settle(velocity:)/travel use goes through Motion.reduced (arrive may be bare), enforced by the lint, escape = one-off with reason — the brief's Step 4 (no bouncing spring, no camera flight under Reduce Motion) needs it at every site — cost if wrong: many mechanical @Environment edits, compile-unverified until CI (a fix round if a site is mistyped).
- **R-491:** R-439 parked again for the final fix wave — 5.8b stays a naming task — cost if wrong: the panel double-fly stays until the final wave.
- **R-492:** SpendKeyStyle/SettleStyle → press (reduced); UIView.transition 0.35 s stays (UIKit, outside the lint), named in README — brief — cost if wrong: none.
- **R-493:** probe gap #6 (select of a new ride not resetting begun) is Important — pin select A/begin A/select B/begin B true + the claim variant; show the mutant fails — it is the bug the gate exists for — cost if wrong: one test.
- **R-494:** the keypad show/hide decision (local, asked vs shown, leaving, duration→curve) goes into TripKit with RED-first tests, as R-464 did; the R-461 projection stays inline (composes tested tracker.status + update's filter; device row 4) — R-460 corrected this very rule once, and inline rules have come back untested twice — cost if wrong: one small TripKit type and one more mechanical app edit (compile risk, CI).
- **R-495:** Minor 2 (onReceive UNVERIFIED-COMPILE) resolved by CI 0/0 on 1962536 — no change — cost if wrong: none.
- **R-496:** Minor 3 → device row 6 clause (hardware keyboard: pad stays up while typing the note, duyệt thiết kế) — no code — cost if wrong: none; the owner judges it on the device.
- **R-497:** I1+M3 — flag a modifier chained on press/pick/settle/travel even inside reduced(; .linear caught whatever follows; allowed tests for LinearGradient/gradient/Charts .interpolationMethod/.chartXScale homonyms by argument context — the lint is the task's lasting gate and Motion.swift names that misuse — cost if wrong: a false positive to one-off later.
- **R-498:** I2 — .blurReplace flagged with a test (pins the brief's removal) — cost if wrong: none.
- **R-499:** M1 — flag withAnimation() / withAnimation({ / withAnimation(completionCriteria: / withAnimation(.default / .animation(.default / .animation(); phaseAnimator left out (trailing-closure animation, not line-local), stated — cost if wrong: a phaseAnimator default slips past until someone adds one.
- **R-500:** M2 — the one-off marker counts only as a comment (strings blanked before the marker test); reduced(token, false) stays allowed — cost if wrong: none.
- **R-501:** M4 — cover title rise (risen) → bare arrive per the class table "tiêu đề → arrive", design row "0.2 s vs 0.7 s"; station highlight → reduced(pick) — under Reduce Motion it fades instead of popping — cost if wrong: an entrance the owner finds too quick (one-token change after the design review).
- **R-502:** M5 — outgoing cover zoom-back → reduced(travel) (cover class, no bounce, matches the 1.0 s scroll) — cost if wrong: a slower zoom-back than the 0.5 s it had.
- **R-503:** M6 — spent-total ring → reduced(travel) (chart/dial draw) — no overshoot on a value — cost if wrong: the ring takes 1.0 s instead of 0.6 s.
- **R-504:** M7 — report table rewritten (file:line | old | token | reduced | reason) + a deviations list — cost if wrong: none.
- **R-505:** M8 — the Fuji hint's transition is .opacity under Reduce Motion — the contract's Reduce Motion rule — cost if wrong: one mechanical ternary (CI).
- **R-506:** the final whole-branch review runs on the strongest tier at effort max — the strongest tier this session has used for every T1 seat (contract § "bậc mạnh nhất"); one reviewer in passes by area, brief final-review-brief.md with the parked list — cost if wrong: a weaker review than another tier would give.
- **R-507:** TripKit tests only — ST-3 m1 (an older generation's failed set lets the next same-category set run), m2 (== [] at :199/:205), R-478 c (LargestFit cost pins on other ranges) — mutant shown for each pin — cost if wrong: none.
- **R-508:** R-439 fixed — the panel Task held in @State, cancelled on every stage/day change, checked after the sleep (!cancelled, stage != .large, same day); § 5.4 row — cost if wrong: a mistyped app edit caught by CI.
- **R-509:** Minor 1 — under Reduce Motion the cover title and sun fade only (offset/scale fixed when reduceMotion); § 5.8b row 13 amended — the contract's Reduce Motion rule; pre-existing but 5.8b's token sits on it — cost if wrong: none.
- **R-510:** Minor 3 — the queued GPS alarm Task returns unless the ride is still the one it was queued for; § 5.9 row — pre-existing, one line, a wrong alarm is the worst kind of bug for this app — cost if wrong: an alarm queued in the same instant as a re-select is dropped (the next fix re-queues it).
- **R-511:** R-478 a/b — TalkShowFit counts lines by one measured line of the same string; "no room" comment reworded; § 5.6 row 4 "trên máy nhỏ, ngang" — cost if wrong: a size a point off from before on some phrases.
- **R-512:** Settings › Số đo shows "ms/s"; the footer says the median counts every end and Instruments tells them apart — 0.2 minors — cost if wrong: none.
- **R-513:** the R-476 row (offline during the beat + area change, duyệt thiết kế) and § 5.7 rows 2/13 in Vietnamese — cost if wrong: none.
- **R-514:** NetworkStatus doc names R-312's exception (a download's state reads raw; its line may flip on a flaky signal, accepted) — the rule written one way — cost if wrong: none.
- **R-515:** Look.plain's doc says PlainPressStyle draws no dim — cost if wrong: none.
- **R-516:** lint-motion flags interactiveSpring (RED first) and the implementer names the Animation statics checked — cost if wrong: none.
- **R-517:** CI app job gains a "Resolve packages" step (resolve; on failure clear ~/Library/Caches/org.swift.swiftpm/artifacts and resolve once more), replacing R-367's pre-decided removal — the fault is SwiftPM's artifact cache, a pin cannot change it — cost if wrong: ~20 s per run on a fault, or a step to delete.
- **R-518:** the review's "Leave" verdicts are accepted as residuals for the report (4.1 tie-break, R-345, 0.2 takesMark (not true as stated), 0.2 SpendTab/Shopping probes, 5.1a source ≤ 0, 5.1b waiter count, R-411, 5.2 residuals, R-475, R-478 d, R-482, R-466) — none changes what a traveller sees beyond what the device rows cover — cost if wrong: one of them surfaces on the device and needs a later task.
- **R-519:** M-1 (large → medium → peek within 0.38 s cancels the settle Task, so the map does not catch up until the next list read) accepted as a residual — the handoff allows one fix wave and no second; it follows R-508's wording, which was mine — cost if wrong: after a fast double drop the map stays on its last camera until the next scroll or tap; the fix is one line (cancel `settling` only when the panel goes back to large, and on a day change), written into the report.
- **R-520:** N-1 (NetworkStatus doc says "Chờ mạng", the label is "Chờ có mạng") accepted — a doc comment's paraphrase — cost if wrong: none.
- **(không số)** (line 126) Parked: a removed tie-break (B #22) survives by dictionary order with ~1/70 chance — Ruling: accepted as is — a reversed tie-break is killed deterministically and the tie only orders equal-date files of one trim — cost if wrong: a future edit dropping the tie-break passes CI by chance once in ~70 runs. Waiting on CI deb87a0.

