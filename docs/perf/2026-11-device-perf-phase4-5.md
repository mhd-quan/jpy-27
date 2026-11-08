# Đo trên máy — Phase 4–5

Những bước của Phase 4–5 cần app chạy thật: đo, chụp màn, duyệt thiết kế, thử trên máy. **Chỉ người dùng làm**,
trên máy thật, bản **Release**, mở từ màn hình chính (trừ khi bước ghi khác). Agent không có máy: không bước
nào ở đây đã được làm, và không ô nào được agent điền. Mỗi task chép bước của mình vào dưới tiêu đề của nó, đã
chỉnh theo code thật, kèm ô trống cho số hay kết luận. Bước đo một kịch bản ghi mã S1–S10 của
`docs/perf/2026-11-baseline.md`.

## 0.2 — Số đo: signpost, Chẩn đoán › Số đo, MetricKit

Bản Release của baseline commit, Instruments như `docs/perf/2026-11-baseline.md` § Cài Instruments.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | S1: trang chủ, chạm thẻ ngày → trang ngày | os_signpost (`tech.delphyra.jp27` / `perf`) có khoảng `push.today`, có event `first-frame` bên trong | |
| 2 | S2: tab Bản đồ, chạm ghim → sheet địa điểm | khoảng `sheet.place` có `first-frame` | |
| 3 | S7: Chi tiêu, chạm "Ghi chi" | khoảng `sheet.expense` có `first-frame` | |
| 4 | Ba bước trên, xem lời kết của khoảng | `settled`, kết thúc cùng lúc zoom dừng (không phải `cap` 1 giây sau khi trang hiện). Toàn `cap` nghĩa là UIKit không báo xong cho trang; ghi lại | |
| 5 | Mở và đóng nhanh vài sheet, vuốt về giữa chừng một trang đẩy, rồi dừng Instruments | mọi khoảng đều có lời kết (`settled`, `cap`, `replaced` hay `timeout`); không khoảng nào còn mở | |
| 6 | Sau ngày dùng đầu tiên (MetricKit gửi số mỗi ngày một lần; muốn thử ngay: bản Debug chạy từ Xcode, Debug › Simulate MetricKit Payloads), Cài đặt › Chẩn đoán › Số đo | có dòng "Theo ngày" và "Chuyển cảnh"; trước lần gửi đầu: "Chưa có số đo" | |
| 7 | Số đo › "Chia sẻ JSON", gửi sang máy tính | các file `metrics-….payload.json`, mở được, là JSON của MetricKit | |

## 4.1

Đo (bước 1–3): bản Release, Instruments như `docs/perf/2026-11-baseline.md`. Bước 2b và 4–9: bản Debug được, cần
Cài đặt › Chẩn đoán › "Ảnh bản đồ đã lưu" và "So khung bản đồ" (chỉ có trong bản Debug). Ảnh bản đồ nằm trong
`Caches/MapSnapshots`: `<frameID>-<hash>.jpg` và `.json` đi kèm (chỗ các ghim trên ảnh).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | S1: trang chủ, chạm thẻ một ngày đã mở trước đó trong lần chạy này → trang ngày | khung đầu của trang (event `first-frame` trong `push.today`) đã có ảnh bản đồ, không có ô xám | |
| 2 | S1 lần đầu cho một ngày chưa từng mở (hoặc sau khi xoá app): xem os_signpost | event `map.snapshot` (bản đồ vẽ ảnh) nằm sau lời kết `settled` của `push.today`, hoặc ≥ 400 ms sau `first-frame`; không có `map.snapshot` thứ hai cho cùng trang | |
| 2b | Mở trang một khách sạn có ảnh chưa tải (lần đầu, có mạng), trong lúc zoom | không có `map.snapshot` trong lúc zoom; nếu màu trang tới giữa chừng và đổi sáng/tối, ảnh bản đồ đổi một lần sau khi zoom dừng | |
| 3 | S9: trang ngày, chạm dấu tích 5 lần | không có `map.snapshot` nào trong 5 lần chạm; ghim của điểm vừa đánh dấu đổi xám ngay trên ảnh | |
| 4 | Chẩn đoán › "Ảnh bản đồ đã lưu": ghi số; mở trang ngày, đánh dấu 5 điểm, bỏ đánh dấu; quay lại Chẩn đoán | số ảnh không đổi (một ảnh cho mỗi khung) | |
| 5 | Chẩn đoán › "So khung bản đồ", vài ngày (cả ngày đi bộ ngắn), cả "Bản đồ thật chồng lên ảnh"; chụp màn | ảnh và bản đồ thật đóng khung giống hệt: cùng tâm, cùng mức phóng, đường và ghim trùng nhau | |
| 6 | Trang khách sạn › "Quanh khách sạn": chạm bản đồ rồi chờ; lần khác (trang khác, chưa mở bản đồ) chạm rồi kéo ngay | Chờ: ảnh ở yên tới khi bản đồ thật vẽ xong rồi mờ đi, không có khung trống hay xám. Kéo ngay khi bản đồ chưa vẽ xong: ảnh nhấc lên khi ngón tay bắt đầu kéo, thấy bản đồ di chuyển theo tay | |
| 7 | Như bước 6 ở chế độ máy bay (vùng chưa tải) | ảnh rời đi chậm nhất khoảng 3 giây sau khi chạm | |
| 8 | Duyệt thiết kế, sáng và tối: trang ngày có vài điểm đã đánh dấu; so ghim đã ghé trên ảnh với tab Bản đồ cùng ngày; so ảnh cũ (trước bản này) với ảnh mới | ghim đã ghé trên ảnh đọc như trên bản đồ thật (xám, viền, số trắng; viền dày hơn khoảng 1 pt, số là font hệ thống); nút "kéo" trên nền thẻ đục, không còn kính mờ. Ghi nhận xét | |
| 9 | Mở lại app sau khi đã mở nhiều trang (thư mục quá 40 MB), hoặc ngay sau khi cài bản này lên bản cũ | Chẩn đoán › "Ảnh bản đồ đã lưu" không còn "ảnh kiểu cũ" và dưới 40 MB | |

## 4.2

Bước 1: bản Release, Instruments template **Time Profiler** (không phải template của
`docs/perf/2026-11-baseline.md`). Bước 2–8: bản nào cũng được, mở Apple Music (hay Spotify), phát một bài rồi
quay lại JP27, loa ngoài, không tai nghe. Bước 7 cần Console trên máy Mac (subsystem `tech.delphyra.jp27`,
category `audio`). Không có mã S: không kịch bản nào trong `docs/perf/2026-11-baseline.md` đọc câu. Việc của
session âm thanh chạy trên hàng đợi `jp27.audio-session`; nhạc to lại khoảng nửa giây sau câu đọc cuối (lúc
app nhả session).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Sổ tay: vừa cuộn danh sách câu vừa bấm nút loa của 10 câu liên tiếp. Trong Time Profiler, chọn main thread, tìm `setActive` và `setCategory` | không có `-[AVAudioSession setActive:withOptions:error:]` hay `setCategory:mode:options:error:` trên main thread; chúng nằm trên hàng đợi `jp27.audio-session` | |
| 2 | Nhạc đang phát. Sổ tay, bấm đọc một câu, chờ câu đọc xong | nhạc nhỏ lại trong lúc đọc, **to lại** chậm nhất 1 giây sau khi câu đọc xong | |
| 3 | Tắt hẳn app (vuốt khỏi app switcher), mở lại, nhạc đang phát; bấm đọc câu đầu tiên. Làm lại với công tắc Chuông/Im lặng ở **im lặng** | nhạc nhỏ lại (không dừng hẳn), câu nghe rõ cả khi im lặng, nhạc to lại sau câu | |
| 4 | Hai câu gần nhau: bấm đọc một câu, và trong vòng nửa giây sau khi nó đọc xong bấm đọc câu khác. Lần khác: bấm câu thứ hai khi câu đầu còn đang đọc | câu thứ hai đọc trọn từ đầu tới cuối (không bị cắt); câu đầu dừng ngay khi bấm câu thứ hai; nhạc nhỏ suốt hai câu, to lại sau câu thứ hai | |
| 5 | Một câu rồi Nghe: bấm đọc một câu, ngay khi câu xong (trong nửa giây) mở Nghe và bấm nghe, nói một câu tiếng Nhật, bấm dừng | Nghe chép được câu nói (micro không bị tắt); bấm dừng thì nhạc to lại trong vòng 1 giây | |
| 6 | Dừng Nghe giữa câu (như bước 7 của Task 3.4b): đang nghe, bấm đọc một câu dài (đọc chậm), bấm dừng Nghe khi câu mới đọc được nửa; rồi bấm nghe lần nữa | câu đọc tiếp tới hết, không bị cắt; nhạc to lại chậm nhất 1 giây sau khi câu đọc xong; lần nghe sau chép được | |
| 7 | Console, lọc category `audio`, trong lúc làm bước 2–6 | không có dòng "… failed: …". Một dòng "… busy, tried again in 150 ms …" được phép nếu nhạc vẫn to lại; ghi lại nếu có | |
| 8 | Nghe một câu (Sổ tay, bấm đọc) với nhạc của app khác đang phát, rồi về màn hình chính ngay khi câu vừa dứt. Không đang theo một chuyến tàu (lúc đó app chạy tiếp ở nền) | nhạc lên lại trong 1 giây. Nếu nhạc chỉ lên lại khi mở lại JP27, ghi lại | |

## 4.3

Bước 1–4: bản nào cũng được. Bước 5 là phép đo Instruments: bản Release, template Time Profiler. Mã S theo
`docs/perf/2026-11-baseline.md`: bước 4 là S10, bước 5 là S9; bước 1–3 không có mã S.
Nguồn điện thấp bật/tắt từ Control Center khi app đang mở ở trang chủ (`AppModel.lowPower`).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Trang chủ, bìa đang lật (đợi một lần lật), bật Nguồn điện thấp từ Control Center rồi quay về app | bìa dừng ngay, không lật thêm trang; ảnh bìa không còn trôi chậm | |
| 2 | Vẫn ở trang chủ, tắt Nguồn điện thấp | bìa lật lại sau khoảng 6 giây, ảnh bìa trôi lại | |
| 3 | Mở app lúc Nguồn điện thấp đang bật, vào trang chủ | bìa đứng yên từ đầu | |
| 4 (S10) | Cài đặt › Chẩn đoán, dòng số lần chạy lịch nhắc (`model.reschedules` = `rescheduler.runs`), mở app một lần từ tắt hẳn | số lần chạy = 1 | |
| 5 (S9) | Bản Release. Trang ngày: Time Profiler đang ghi, chạm dấu tích của một điểm; đọc main thread quanh lần chạm | không có việc của CoreLocation (`CLLocationManager`) trên main thread trong khung của lần chạm | |

## 5.8a

## 5.1a

Bước 1: bản Debug (Cài đặt › Chẩn đoán › "So màu ảnh: mới và cũ" chỉ có trong bản Debug). Bước 2–3: bản Release,
Instruments như `docs/perf/2026-11-baseline.md`, track os_signpost (`tech.delphyra.jp27` / `perf`): mỗi lần ImageIO
giải mã một ảnh là một event `photo.decode`, mỗi lần ghi file màu là một event `photo.tones`. Lúc mở app, khoảng
2 giây sau, app đọc màu của mọi ảnh bìa một lượt (mỗi ảnh một `photo.decode`, một `photo.tones` khi xong): mở app rồi
chờ nửa phút trước khi đo. Bước 4–5: bản nào cũng được. Màu đã đọc nằm trong
`Application Support/Photos/tones-2.json`; file `tones-1.json` của bản cũ không còn được đọc, nên lần đầu sau khi cài
bản này, trang nào mở trước khi màu của nó được đọc sẽ mở trên nền giấy một lần.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Chẩn đoán › "So màu ảnh: mới và cũ", chờ dòng kết quả (20 ảnh: các ảnh bìa ngày, rồi ảnh địa điểm đóng gói). Ghi cả hai số: "Từ ảnh nguyên" (màu đọc từ ảnh trang vẽ, cách mới) và "Từ nền 160 px" (màu đọc từ nền 160 px của lớp mờ, trước khi làm mờ) | "Từ ảnh nguyên: lệch" ≤ 0,02. Số thứ hai là đường dự phòng: ghi lại dù số đầu đạt | |
| 2 | S1: trang chủ, để bìa và các thẻ ngày hiện ra, chạm thẻ một ngày chưa mở trong lần chạy này → trang ngày | trong khoảng `push.today` không có `photo.decode` nào cho ảnh của ngày (ảnh lấy từ bản đã giải mã cho trang chủ); cả trang ngày nhiều nhất một `photo.decode` cho mỗi ảnh nó hiện | |
| 3 | S2 lần đầu sau khi cài bản này (hoặc một địa điểm có nhiều ảnh chưa từng mở): tab Bản đồ, chạm ghim → sheet địa điểm, chờ 2 giây | một `photo.tones` cho cả lượt mở trang (không phải một cho mỗi ảnh), khoảng 1 giây sau màu cuối cùng; không `photo.decode` thứ hai cho cùng một ảnh trong lượt mở | |
| 4 | Có mạng. Mở trang một quán ăn có ảnh chưa từng xem, chưa tải ở Cài đặt (ảnh từ mạng) | trang mở trên nền giấy, không có màu nào hiện dần trong lúc zoom; ảnh tải về rồi hiện như trước. Màu có thể tới ở lần mở sau (hoặc muộn hơn trong chính trang đó, khi trang vẽ lại: ghi lại nếu thấy) | |
| 5 | Duyệt thiết kế, sáng và tối: lớp mờ dưới ảnh (phần ảnh tan vào nền) của một trang địa điểm và một trang ngày, so với bản trước | lớp mờ trông như cũ: cùng độ mờ, cùng màu, không viền cứng ở mép. Ghi nhận xét | |

## 5.1b

## 5.2

## 5.5

## 5.4

## 5.3

## 5.6

## 5.7

## 5.9

## 5.8b

## 6.2
