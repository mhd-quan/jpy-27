# Đo và kiểm trên máy — Phase 4–5

Những bước không agent nào làm được: đo bằng Instruments, nhìn animation, MetricKit sau một ngày dùng. Mỗi task của
Phase 4–5 chép bước của mình vào đây, dưới tiêu đề của task, đã chỉnh theo code thật.

**Điền gì.** Mỗi bước có ô kết quả: điền **Đạt / Không đạt**, hay con số, kèm ghi chú khi cần.

**Bản build.** Release, mở từ màn hình chính, trừ khi bước ghi khác. Product › Profile (⌘I) cũng build Release.

**Kịch bản.** Mã S1–S10 là mười kịch bản của [`2026-11-baseline.md`](2026-11-baseline.md):

| Mã | Kịch bản |
| --- | --- |
| S1 | Trang chủ → trang ngày |
| S2 | Bản đồ: ghim → sheet địa điểm |
| S3 | Lịch trình → Fuji |
| S4 | Fuji → điểm ngắm |
| S5 | Trang địa điểm: vuốt ảnh |
| S6 | Bản đồ: vuốt dòng thời gian |
| S7 | Chi tiêu: "Ghi chi" |
| S8 | Thẻ câu, xoay |
| S9 | Trang ngày: dấu tích |
| S10 | Mở app nguội |

Một bước đo kịch bản thì đo như file đó tả: 5 lần, lấy trung vị, so với bảng nền.

## Bước 1 — Task 0.2: mốc đo, Số đo, MetricKit

Bản Release ở baseline commit. Instruments: Animation Hitches + os_signpost (dòng Points of Interest), Attach vào JP27
đã mở từ màn hình chính.

| # | Bước | Đạt khi | Kết quả | Ghi chú |
| --- | --- | --- | --- | --- |
| 1 | Chạy S1, S2, S3, S4, S7 và phần mở thẻ của S8, mỗi cái một lần. | Mỗi lần chạm có đúng một khoảng `transition` ở Points of Interest, có sự kiện `first-frame`, kết thúc `settled`. Nhãn là `today → day`, `map → place`, `plan → fuji`, `fuji → fujiSpot`, `spend → expense`, `phrase`. | | |
| 2 | Cùng các lần ở bước 1, nhìn track Hitches. | Khung cuối của animation (zoom, sheet trồi lên, trang trượt vào) nằm trước cuối khoảng. Nếu animation còn chạy sau khi khoảng đã hết, ghi kịch bản và quãng còn lại (ms): mốc chờ 350/500 ms phải tăng. | | |
| 3 | Mở một sheet (S2) rồi vuốt đóng ngay, trong nửa giây. Mở lại. | Khoảng thứ nhất kết thúc `dismissed`. Lần mở lại có khoảng mới, kết thúc `settled`. | | |
| 4 | Chạy S5, S6, S9 và phần xoay của S8. | Các sự kiện `place.photo`, `map.fly`, `day.check`, `phrase.turn` hiện ở Points of Interest, mỗi hành động một lần. `map.fly` không hiện liên tục từng khung khi chỉ cuộn trong một mục. | | |
| 5 | Sau bước 1–4, mở Cài đặt › Chẩn đoán › Số đo. | Phần "Chuyển trang" có các nhãn ở bước 1, đúng số lần, có số ms. Bên dưới có số lần của các sự kiện ở bước 4. | | |
| 6 | Kiểm MetricKit: Xcode › Debug › Simulate MetricKit Payloads, khi app chạy từ Xcode. Hoặc dùng app một ngày, mở lại hôm sau. | Số đo › MetricKit có một dòng ngày: giật khi cuộn, giật khi chuyển động, mở app, các signpost. "Chia sẻ JSON" bấm được và gửi được file. Nếu sau hai ngày vẫn trống, xem Cài đặt › Quyền riêng tư & Bảo mật › Phân tích & Cải tiến: iOS có thể chỉ gửi khi bật chia sẻ với nhà phát triển (chưa kiểm). | | |
| 7 | Dùng app như thường vài phút. Zoom vào và ra ở thẻ ngày, sheet địa điểm, thẻ câu, nạp tiền, mua sắm. Vuốt lùi, chồng sheet lên sheet. | Mọi thứ chạy như bản trước Task 0.2. Không có gì khác ngoài dòng "Số đo" mới trong Chẩn đoán. | | |
| 8 | Đo nền S1–S10 theo `2026-11-baseline.md`. | Bảng "Kết quả" ở đó đã điền đủ. | | |

## Task 4.1 — Bản đồ tĩnh: khung đầu có ảnh, không snapshot lúc zoom, bản đồ thật không trống

Bản Release ở commit của Task 4.1, trừ bước 4 và 5: trang **Cài đặt › Chẩn đoán › So khung bản đồ** chỉ có trong
bản Debug (chạy từ Xcode). Instruments như Bước 1: Animation Hitches + os_signpost. Sự kiện mới `map.snapshot` ở
Points of Interest: một lần cho mỗi ảnh bản đồ được vẽ (một snapshotter chạy). Ảnh lấy từ bộ nhớ hay từ đĩa không
có sự kiện.

| # | Bước | Đạt khi | Kết quả | Ghi chú |
| --- | --- | --- | --- | --- |
| 1 | S1, lần đầu với một ngày từ khi cài bản này: trang chủ → zoom vào ngày đó. | Không có `map.snapshot` nào nằm trong khoảng `today → day`. `map.snapshot` đến sau `settled` của khoảng đó, một lần. | | |
| 2 | S1 lại với đúng ngày ấy, app còn mở (ảnh ở bộ nhớ). Quay màn hình, xem từng khung. | Khung đầu tiên của trang ngày đã có ảnh bản đồ, không có ô xám. Không có `map.snapshot`. | | |
| 3 | S1, đo như `2026-11-baseline.md`: 5 lần, trung vị. | Không tệ hơn nền. | | |
| 4 | S9 (bản Debug). Dùng một trang ngày đã mở ở bước 1 (hay đã mở lúc có mạng, trên máy này), để ảnh của nó đã nằm trên đĩa. Mở So khung bản đồ một lần, chờ cả hai khung hiện, rồi ra (lần đầu trang này tự vẽ và ghi một ảnh của riêng nó). Mở lại So khung bản đồ, đọc dòng "Ảnh bản đồ trên máy" (số ảnh, MB). Vào trang ngày ấy, đánh dấu 5 điểm dừng, mỗi lần một dấu tích. Quay lại So khung bản đồ (ra rồi vào lại để trang đọc lại). | Từ `day.check` đầu tới `day.check` cuối: 5 sự kiện `day.check`, 0 sự kiện `map.snapshot` (chỉ đếm `map.snapshot` trong khoảng đó). Mỗi chấm đổi sang xám ngay khi đánh dấu, ảnh bản đồ không nháy. Số ảnh trong `Caches/MapSnapshots` bằng lần đọc trước khi đánh dấu. Không còn "ảnh cũ" (file `.png` của bản trước, xoá lúc mở app). | | |
| 5 | So khung (bản Debug): So khung bản đồ, chọn lần lượt Ngày 1 đến 12 và ngày thay thế. Chụp màn hai ngày: một ngày đi xa, một ngày quanh một chỗ. | Hai khung "Ảnh" và "Bản đồ thật" trùng nhau: cùng tâm, cùng mức phóng, ghim ở cùng chỗ, chấm cùng cỡ cùng màu. Khác nhau được phép: số trên chấm của ảnh là SF Bold 11, của bản đồ thật là Noto Sans Bold 11; góc dưới bản đồ thật có logo MapLibre và nút ghi công. Đính kèm ảnh chụp. | | |
| 6 | Điện thoại để giao diện Sáng. Mở một trang ngày có ảnh bìa tối (trang chuyển nền tối), lần thứ hai trở đi (màu ảnh đã biết). | Ảnh bản đồ là kiểu tối. Chấm điểm dừng màu đỏ của chế độ tối, viền đen, như trên bản đồ thật ở Cài đặt giao diện Tối. Chỉ một `map.snapshot` cho trang (không vẽ sáng rồi tối). Nếu trang có bản đồ chạm được (khách sạn, đường đi bộ), chạm: bản đồ thật cũng tối, không nháy sáng. | | |
| 7 | Chế độ máy bay. Mở trang một khách sạn (hoặc đường đi bộ, mua sắm) đã xem lúc có mạng. Chạm bản đồ. Lặp lại, lần này kéo bản đồ ngay sau khi chạm. | Ảnh vẫn hiện tới khi bản đồ thật vẽ xong, hay tối đa 2 giây, rồi mờ đi. Không lúc nào thấy ô trống. Cú kéo ngay sau khi chạm kéo được bản đồ, và ảnh đi luôn. | | |
| 8 | Chạy lại S2–S10 như `2026-11-baseline.md`. | Không kịch bản nào tệ hơn nền. | | |
| 9 | (Tuỳ chọn) Xoá app, cài lại, có mạng. Mở lần đầu một trang ngày có ảnh bìa tối. | Ghi lại: có thể thấy ảnh bản đồ sáng rồi đổi sang tối, hai `map.snapshot` (màu ảnh chưa biết ở khung đầu). Lần mở sau chỉ một. | | |

## Task 4.2 — Audio session ngoài main, nhả có hẹn

Bản Release ở commit của Task 4.2, trừ bước 7–11: dòng **Cài đặt › Chẩn đoán › Phiên âm thanh** chỉ có trong bản
Debug (chạy từ Xcode). Dòng đó đọc lại khi mở trang hay khi chạm, và ghi ai giữ phiên âm thanh: "Phát âm" (kèm "chờ
nhả" trong nửa giây trước khi nhả), "Nghe" hay "Không ai giữ". Sau đó là "nhả lỗi N": số lần huỷ phiên thất bại hẳn kể
từ khi mở app. Lần huỷ bị từ chối vì bận (`isBusy`) được thử lại một lần sau 150 ms, và chỉ tính khi cả lần thử lại cũng
lỗi: lần đầu bận mà lần thử lại được thì không tính, và Console không ghi gì. Mọi lệnh session chạy trên hàng đợi
`tech.delphyra.jp27.audio-session`. Chỉ lệnh lỗi hẳn mới ghi ở Console (subsystem `tech.delphyra.jp27`, category
`audio`), mỗi lần một dòng: số dòng `setActive false failed` bằng N. Không bước nào đo một kịch bản S1–S10: tab Sổ tay
(danh sách câu) không có trong bảng đó.

| # | Bước | Đạt khi | Kết quả | Ghi chú |
| --- | --- | --- | --- | --- |
| 1 | Time Profiler, Attach vào JP27 đã mở từ màn hình chính. Tab Sổ tay: vừa cuộn vừa chạm loa ở 10 câu liên tiếp, mỗi câu nghe hết rồi mới chạm câu sau. Lọc call tree theo `AVAudioSession`. | Không có `setActive` hay `setCategory` nào trên Main Thread. Chúng nằm trên thread của hàng đợi `…audio-session`. Nếu còn `setActive` dưới `-[AVSpeechSynthesizer speakUtterance:]` trên main, ghi lại kèm số ms: đó là lệnh riêng của bộ đọc, gọi khi phiên đã bật (chưa kiểm). | | |
| 2 | Mở Nhạc, phát một bài. Trong app chạm loa một câu, nghe hết. | Nhạc nhỏ xuống khi câu được đọc, và trở lại âm lượng thường trong ≤ 1 s sau khi câu dứt (hẹn 0,5 s). | | |
| 3 | Nhạc đang phát. Chạm loa một câu, rồi chạm câu khác ngay khi câu đầu dứt, trong nửa giây. | Giữa hai câu nhạc vẫn nhỏ, không bật to rồi nhỏ lại. Sau câu thứ hai nhạc trở lại như bước 2. | | |
| 4 | Gạt công tắc Chuông/Im lặng sang im lặng. Chạm loa một câu. | Vẫn nghe câu được đọc. | | |
| 5 | Nhạc đang phát. Mở Nghe, bắt đầu nghe. Nói (hay bật từ máy khác) một câu Sổ tay biết, để câu trả lời hiện dưới câu nghe được. Vẫn đang nghe, chạm loa ở câu trả lời. | Micro vẫn chạy: nói một câu tiếng Nhật sau đó thì câu đó hiện ra. Câu app vừa đọc không hiện thành câu nghe được. Nhạc nhỏ suốt lúc nghe. | | |
| 6 | Nhạc đang phát. Như bước 5, nhưng giữ (nhấn lâu) loa ở câu trả lời để câu được đọc chậm, rồi chạm nút dừng Nghe khi câu còn đang đọc. | Câu đọc tiếp đến hết, ra loa ngoài. Nhạc nhỏ tới hết câu, rồi trở lại trong ≤ 1 s. | | |
| 7 | Nhạc đang phát. Bắt đầu nghe, không đọc gì, rồi dừng Nghe. Mở Chẩn đoán › Phiên âm thanh (bản Debug). | Nhạc trở lại âm lượng thường ngay. Dòng ghi "Không ai giữ · nhả lỗi 0". | | |
| 8 | Bản Debug: chạm loa một câu, nghe hết, rồi mở Chẩn đoán › Phiên âm thanh. | "Không ai giữ · nhả lỗi 0": phiên đã được nhả sau câu. Nếu còn "Phát âm", phiên chưa được nhả: ghi lại. | | |
| 9 | Bản Debug. Đang gọi điện thoại (hay FaceTime âm thanh), mở Nghe, chạm bắt đầu. Sau cuộc gọi, mở Chẩn đoán › Phiên âm thanh. | Nghe báo "Không bắt đầu nghe được." (hay micro không mở). Sau cuộc gọi, nhạc hay app khác phát lại bình thường. Dòng ghi "Không ai giữ", "nhả lỗi" vẫn 0. Nếu "nhả lỗi" tăng, xem Console category `audio`: huỷ một phiên chưa bật đã báo lỗi (chưa kiểm, R-233). | | |
| 10 | Bản Debug. Dùng Nghe và loa xen kẽ vài phút như bước 2–7. Mở Chẩn đoán › Phiên âm thanh. | "nhả lỗi 0". Nếu khác 0, chép các dòng `setActive false failed` ở Console vào ghi chú: số dòng bằng N. Một lần huỷ bận rồi thử lại được là bình thường: không tính, không ghi dòng nào. | | |
| 11 | Bản Debug. Nhạc đang phát. Tab Sổ tay: giữ (nhấn lâu) loa ở một câu dài để câu được đọc chậm, rồi chạm loa ở câu khác khi câu đầu còn đang đọc. Nghe hết câu thứ hai, chờ 2 s, rồi mở Chẩn đoán › Phiên âm thanh. | Câu đầu dừng, câu thứ hai được đọc hết, và câu đầu không đọc tiếp sau đó. Nhạc nhỏ suốt từ câu đầu tới hết câu thứ hai, không bật to lúc chuyển câu, rồi trở lại một lần, khoảng 0,5 s sau khi câu thứ hai dứt (≤ 1 s). Dòng ghi "Không ai giữ · nhả lỗi 0". | | |
| 12 | Bản Release, so với bản nền: build commit nền `74ceccf` như `2026-11-baseline.md` (mục "Bản build") hướng dẫn, rồi bản ở commit của Task 4.2. Trên mỗi bản, ở một trang yên (tab Sổ tay, không cuộn, không phát gì khác), chạm loa ở cùng một câu 5 lần, mỗi lần nghe hết, và để ý giọng đọc bắt đầu sau cú chạm bao lâu. Không có signpost nào đo lúc giọng bắt đầu (`phrase.turn` chỉ đánh dấu nút xoay của thẻ câu), nên bước này nghe bằng tai. | Giọng bắt đầu nhanh như ở bản nền, không thấy trễ hơn. Nút loa đổi dạng ngay khi chạm ở cả hai bản; giờ giọng chờ lệnh session chạy xong trên hàng đợi rồi mới đọc. Nếu thấy trễ hơn, ghi lại cảm nhận (bao lâu, lần nào). | | |

## Task 4.3 — Nguồn điện thấp theo dõi trực tiếp trên bìa trang chủ

Bản Release ở commit của Task 4.3. `AppModel.lowPower` đọc lại `ProcessInfo.isLowPowerModeEnabled` mỗi lần có
`NSProcessInfoPowerStateDidChange`; vòng lật bìa (`TodayHome`, `.task(id:)`) và chuyển động trôi của ảnh đọc nó.

| # | Bước | Đạt khi | Kết quả | Ghi chú |
| --- | --- | --- | --- | --- |
| 1 | Mở tab Hôm nay, để bìa tự lật (đợi một lần lật). Kéo Control Center xuống, bật Nguồn điện thấp. | Bìa dừng lật ngay, kể cả khi đang đợi 6 giây: không có lần lật nào sau đó. Ảnh đang hiện thôi trôi bằng cách thu về cỡ nghỉ trong khoảng 0,5 giây, không đứng khựng: đừng tính đó là lỗi. | | |
| 2 | Giữ Nguồn điện thấp bật 20 giây rồi tắt (không thoát app, không đổi tab). | Bìa lật lại sau khoảng 6 giây và ảnh trôi lại, không cần mở lại app. Lưu ý: bìa tự nghỉ sau khi đã đi hết một vòng các ảnh (mỗi lần mở lại tab Hôm nay thì vòng đếm lại từ đầu). Nếu đã để bìa chạy hết một vòng trước bước 1, hãy rời tab Hôm nay rồi quay lại trước khi tắt Nguồn điện thấp; bìa đứng yên vì đã nghỉ thì không tính là lỗi. | | |
| 3 | Mở app khi Nguồn điện thấp đang bật từ trước (S1). | Bìa đứng yên từ khung đầu. Tắt Nguồn điện thấp: bìa lật lại. | | |
| 4 | Mở app (Release), sau đó mở Cài đặt › Chẩn đoán, đọc dòng số lần đặt lại nhắc giờ. Chạm một dấu tích điểm dừng rồi đọc lại. | Mở app: 1 lần. Chạm dấu tích: tăng đúng 1. (B3.) Điều kiện của B4: trước chuyến, định vị đang được cho phép (khi đó mỗi lần mở app có một `requestLocation()`, và kết quả của nó không được gây lần đặt lại thứ hai). | | |
| 5 | Trước chuyến, mở app có định vị bật; Time Profiler (Main Thread) trong khung của một chạm dấu tích. | Không có công việc CoreLocation (`requestLocation`) và không có công việc đặt lại (`AppModel.reschedule()`: nhắc giờ, geofence, báo thức) chạy trong khung của lần chạm: nó chạy sau 300 ms, qua `Coalescer`. (B3, B4.) | | |

## Task 5.1 — Trang album: một lần giải mã mỗi ảnh, ảnh ghép sẵn, không gì chuyển động trong lớp đã gộp

Bản Release ở commit của Task 5.1, trừ bước 1: trang **Cài đặt › Chẩn đoán › Lệch màu ảnh** chỉ có trong bản Debug
(chạy từ Xcode). Instruments: Animation Hitches + os_signpost như Bước 1, thêm SwiftUI (đếm body) ở bước 2–4. Ảnh ở
đầu trang album (địa điểm, ngày, khách sạn, điểm trên vòng đi bộ, điểm ngắm Fuji) giờ là một ảnh ghép sẵn ngoài luồng
chính (`PhotoCache.ambient`), giữ trong bộ nhớ và trong `Caches/Ambient`. Màu trang lấy từ ảnh đầu và giữ suốt trang.
"Lần thứ hai" là trang đã mở một lần trước đó, app còn mở.

| # | Bước | Đạt khi | Kết quả | Ghi chú |
| --- | --- | --- | --- | --- |
| 1 | Bản Debug: Cài đặt › Chẩn đoán › Lệch màu ảnh. Chờ hai nhóm tính xong (ảnh bìa, 20 ảnh Commons đầu). | Dòng "Lớn nhất" của mỗi nhóm và dòng tổng không quá 0,02 (độ lệch lớn nhất của một kênh, màu đọc từ lần giải mã của ảnh đầu trang so với màu bản trước đọc từ ảnh nhỏ 96 px). Ghi số lớn nhất của từng nhóm và ảnh lệch nhiều nhất. | | |
| 2 | S1, lần thứ hai với cùng một ngày. Instrument SwiftUI, đếm body của `PlanDayContent` trong khoảng `today → day`. | ≤ 2. | | |
| 3 | S2 với một địa điểm kiểu album (điểm tham quan có từ 2 ảnh), lần thứ hai. Đếm body của `PlanAmbientPage` trong khoảng `map → place`. | ≤ 2. | | |
| 4 | S4, lần thứ hai với cùng một điểm ngắm có ảnh. Đếm body của `FujiSpotContent` trong khoảng `fuji → fujiSpot`. | ≤ 2. | | |
| 5 | S1, S2, S4, đo như `2026-11-baseline.md` (5 lần, trung vị), Animation Hitches. | 0 hitch trong khoảng zoom của cả ba. Ghi trung vị và so với nền. | | |
| 6 | S5: trang một địa điểm có từ 4 ảnh, vuốt 3 ảnh, dừng. | 0 khung rớt khi cú vuốt dừng. Màu trang không đổi khi vuốt sang ảnh khác. | | |
| 7 | S1 với Time Profiler: ở trang chủ để thẻ ngày hiện ảnh bìa của ngày đó, rồi chạm thẻ. | Trong khoảng `today → day` không có `CGImageSourceCreateThumbnailAtIndex` nào cho ảnh bìa ngày đó: thẻ, bìa trang chủ và trang ngày dùng chung một lần giải mã nguyên ảnh. | | |
| 8 | Duyệt thiết kế. Chụp màn bản 1b89170 và bản này, cùng máy: một trang địa điểm kiểu album, một trang ngày, một khách sạn, một điểm ngắm Fuji; mỗi trang ở giao diện Sáng và Tối (8 cặp, trang đã mở một lần để ảnh đã có). Đặt cạnh nhau trong `docs/perf/2026-11-task-5.1/`. | Từng cặp giống nhau: ảnh, bản mờ, chỗ tan, chữ. Màu ảnh không lệch sắc giữa hai bản (cùng sRGB). Khác được chấp nhận: màu trang không đổi theo ảnh khi vuốt; khi ảnh chưa tới (lần mở đầu), khung ảnh là màu trang thay vì ô xám. | | |
| 9 | Tên vào thanh. Ở bản 1b89170 và bản này, cuộn chậm từng trang: địa điểm kiểu album (mở từ bản đồ, là sheet), trang ngày (mở từ trang chủ, là trang đẩy), khách sạn, điểm ngắm, và ba trang có ảnh cao cố định (địa điểm thường, Đang ở quán, Fuji). Ghi phần ảnh còn thấy khi tên hiện vào giữa thanh. | Ở mỗi trang, tên hiện vào thanh ở cùng chỗ ở cả hai bản (lệch không quá khoảng 8 pt). Ở đầu trang tên không bao giờ hiện. | | |
| 10 | Xoá app, cài lại bản này (hay lần mở đầu sau khi cập nhật), có mạng. Trong 2 giây đầu, mở một trang ngày. | Trang phóng ra trên nền giấy, không đổi màu lúc đang phóng. Màu tới một lần, mờ dần ngắn, sau khi trang phóng xong. Mở lại trang đó: màu có từ khung đầu. | | |
| 11 | Có mạng, chưa tải ảnh ngoại tuyến. Mở lần đầu trang một quán kiểu album (đã đặt bàn) có ảnh từ mạng. | Ảnh tải về và mờ dần vào. Trang nằm trên nền giấy suốt lượt này, kể cả sau khi ảnh đã tới. Đóng, mở lại: màu có từ khung đầu. | | |
| 12 | Tắt hẳn app (vuốt khỏi đa nhiệm), bật Chế độ máy bay, mở lại trang của bước 11. | Ảnh hiện (từ `Caches/Ambient`), mờ dần vào. Không có ô trống hay ô xám. | | |
| 13 | Bật Cài đặt › Trợ năng › Màn hình & cỡ chữ › Giảm độ trong suốt. Mở một trang địa điểm kiểu album, vuốt qua các ảnh. | Ảnh tan thẳng vào màu trang, không có bản mờ dưới ảnh, như bản 1b89170 với cùng cài đặt. Ảnh tới thì mờ dần vào cả khối. Vuốt êm. | | |
| 14 | S2 và S4, quay màn hình, xem từng khung lúc zoom vừa dừng. | Ảnh đầu trang không nhảy khung (không bị cắt lại hay đổi cỡ) lúc zoom dừng. Nếu có, ghi trang nào. | | |
| 15 | S1, S2 và S4, lần thứ hai với cùng một trang (app còn mở, trang đã mở xong một lần trước đó). Quay màn hình, xem từng khung từ lúc chạm tới lúc zoom dừng. | Ảnh đầu trang có ngay từ khung đầu của lần zoom: không mờ dần vào, không có khung nào chỉ có màu trang hay nền giấy ở chỗ ảnh. Nếu có, ghi trang nào và mấy khung. | | |
| 16 | Tắt hẳn app, mở lại (trang chủ lạnh), Time Profiler từ lúc mở tới khi bìa và thẻ ngày hôm nay đã hiện. Lọc `CGImageSourceCreateThumbnailAtIndex`. | Ảnh bìa của ngày hôm nay được giải mã một lần, dù bìa (xin 2400) và thẻ ngày (xin 1800) cùng xin nó. | | |
