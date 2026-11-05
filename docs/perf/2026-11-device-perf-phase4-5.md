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
