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
giải mã một ảnh là một event `photo.decode`, kèm tên ảnh và cỡ xin (`commons/….webp @1800`, hay đường dẫn ảnh bìa),
mỗi lần ghi file màu là một event `photo.tones`. Lúc mở app, khoảng
2 giây sau, app đọc màu của mọi ảnh bìa một lượt (mỗi ảnh một `photo.decode`, một `photo.tones` khi xong): mở app rồi
chờ nửa phút trước khi đo. Bước 4–5: bản nào cũng được. Bước 6: bản Release, Instruments như
`docs/perf/2026-11-baseline.md`, track Animation Hitches (không có mã S). Màu đã đọc nằm trong
`Application Support/Photos/tones-2.json`; file `tones-1.json` của bản cũ không còn được đọc, nên lần đầu sau khi cài
bản này, trang nào mở trước khi màu của nó được đọc sẽ mở trên nền giấy một lần.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Chẩn đoán › "So màu ảnh: mới và cũ", chờ dòng kết quả (20 ảnh: các ảnh bìa ngày, rồi ảnh địa điểm đóng gói). Ghi cả hai số: "Từ ảnh nguyên" (màu đọc từ ảnh trang vẽ, cách mới) và "Từ nền 160 px" (màu đọc từ nền 160 px của lớp mờ, trước khi làm mờ) | "Từ ảnh nguyên: lệch" ≤ 0,02. Số thứ hai là đường dự phòng: ghi lại dù số đầu đạt | |
| 2 | S1: trang chủ, để bìa và các thẻ ngày hiện ra. (a) Chạm thẻ của ngày có ảnh bìa đang hiện trên bìa trang chủ → trang ngày. (b) Lần khác, một ngày có ảnh bìa riêng mà bìa trang chủ chưa hiện trong lần chạy này (chỉ thấy trên thẻ). Đọc các `photo.decode` theo tên ảnh trong event | (a) 0 `photo.decode` cho ảnh bìa đó trong khoảng `push.today`: ảnh lấy từ bản bìa trang chủ đã giải mã nguyên ảnh. (b) đúng 1 cho ảnh bìa đó: thẻ giải mã bản thu nhỏ 1200 px, không dùng được cho cỡ 1800 của trang ngày (R-351). Bìa nằm cạnh bìa đang hiện có thể đã được bìa trang chủ dựng sẵn: khi đó 0 cũng đúng, ghi lại | |
| 3 | S2 lần đầu sau khi cài bản này (hoặc một địa điểm có nhiều ảnh chưa từng mở): tab Bản đồ, chạm ghim → sheet địa điểm, chờ 2 giây | một `photo.tones` cho cả lượt mở trang (không phải một cho mỗi ảnh), khoảng 1 giây sau màu cuối cùng; không có `photo.decode` thứ hai cho cùng một tên ảnh trong lượt mở | |
| 4 | Có mạng. Mở trang một quán ăn có ảnh chưa từng xem, chưa tải ở Cài đặt (ảnh từ mạng) | trang mở trên nền giấy, không có màu nào hiện dần trong lúc zoom; ảnh tải về rồi hiện như trước. Màu có thể tới ở lần mở sau (hoặc muộn hơn trong chính trang đó, khi trang vẽ lại: ghi lại nếu thấy) | |
| 5 | Duyệt thiết kế, sáng và tối: lớp mờ dưới ảnh (phần ảnh tan vào nền) của một trang địa điểm và một trang ngày, so với bản trước | lớp mờ trông như cũ: cùng độ mờ, cùng màu, không viền cứng ở mép. Ghi nhận xét | |
| 6 | Trang chủ đang hiện các bìa; rồi tab Lịch trình, cuộn nhanh danh sách ngày; rồi một trang ngày, cuộn nhanh các dòng địa điểm. Các ô ảnh nhỏ ở đó giờ có thể vẽ từ bản đã giải mã nguyên ảnh (lớn hơn ô nhiều lần) | 0 hitch trong lúc cuộn | |

## 5.1b

Bản Release, Instruments như `docs/perf/2026-11-baseline.md`: track os_signpost (`tech.delphyra.jp27` / `perf`),
SwiftUI (View Body) và Animation Hitches. Mỗi ảnh đầu trang album được ghép sẵn một lần (bản mờ và ảnh nét tan dần
thành một ảnh): mỗi lần ghép xong hay đọc từ đĩa là một event `photo.ambient` "`<ảnh> <rộng>x<cao> made|disk`", cỡ
khung tính bằng điểm. Ảnh ghép nằm trong `Caches/Ambient` (giữ dưới 40 MB mỗi lần mở app, ảnh lâu không dùng đi
trước), làm lại được bất cứ lúc nào. Màu trang lấy từ ảnh đầu và giữ suốt lúc trang mở: vuốt sang ảnh khác không đổi
nền nữa. Bước 9, 10 và 14 là **duyệt thiết kế** (mắt người, không có số). Ghép ảnh là việc nền: trang đóng hay đổi ảnh trước khi ghép xong thì việc ghép dừng, không giữ, không ghi; ở Nguồn điện thấp app không ghép ảnh mới.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1a | S1, lần đầu mở ngày đó trong lần chạy này: trang chủ, để bìa hiện ra, chạm thẻ của ngày có ảnh bìa đang hiện → trang ngày. Đọc View Body và hitch trong khoảng `push.today`; quay chậm màn hình nếu được | `PlanDayContent` ≤ 2 lần body; 0 hitch. Khung đầu: ảnh bìa nét phủ kín khung (đã giải mã ở trang chủ), chưa có bản mờ dưới phần tan, chân ảnh do lớp tan che; rồi ảnh ghép mờ dần lên trên trong 0,2 giây. Ghi lại khung đầu trông thế nào so với lúc ảnh ghép đã lên (một event `photo.ambient` `made`) | |
| 1b | S1 lần hai cho cùng ngày đó | `PlanDayContent` ≤ 2 lần body; 0 hitch; ảnh ghép có từ khung đầu, không mờ dần; không có `photo.ambient` | |
| 2 | S2: tab Bản đồ, chạm ghim một địa điểm kiểu album → sheet địa điểm (`sheet.place`) | `PlanAmbientPage` ≤ 2 lần body; 0 hitch | |
| 3 | S3: tab Lịch trình → trang Fuji (`push.plan`) | 0 hitch (phép đọc tiêu đề của `detailPage` đã đổi) | |
| 4 | S4: trang Fuji, chạm một chỗ ngắm có ảnh (`sheet.fujiSpot`) | `FujiSpotAlbum` ≤ 2 lần body; 0 hitch (`FujiSpotCard` là thẻ trên bản đồ 3D, không phải trang này) | |
| 5 | S5: trang một địa điểm nhiều ảnh, vuốt qua vài ảnh rồi dừng | 0 khung rơi khi dừng vuốt; màu nền, thẻ và chữ của trang không đổi khi vuốt | |
| 6 | Một trang album chưa từng mở: mở, vuốt qua mọi ảnh, đóng; mở lại; rồi tắt hẳn app (vuốt khỏi app switcher), mở lại cùng trang và vuốt qua mọi ảnh. Đọc các `photo.ambient` | lần đầu: một `made` cho mỗi ảnh đã hiện, mọi event của trang cùng một cỡ khung; lần hai: không có; sau khi mở lại app: một `disk` cho mỗi ảnh, không có `made`. Nếu một ảnh có hai cỡ khung trong cùng một lần mở, ghi lại | |
| 7 | Có mạng. Trang một quán có ảnh từ mạng chưa từng tải (chưa tải ở Cài đặt): mở, chờ ảnh tải xong, vuốt và cuộn; đóng rồi mở lại | lần đầu: nền giấy suốt đời trang, kể cả sau khi ảnh đã tải, khi vuốt và khi cuộn (ảnh tải xong trước khi zoom dừng thì màu có thể tới một lần, ngay khi zoom xong: ghi lại); lần mở lại: màu có từ khung đầu | |
| 8 | Xoá app, cài lại; mở app rồi mở ngay một trang địa điểm kiểu album có ảnh trong app (trong vài giây đầu, trước khi app đọc trước màu) | nền giấy suốt lần zoom; zoom xong màu tới một lần (mờ dần 0,2 giây), rồi không đổi nữa khi vuốt hay cuộn | |
| 9 | **Duyệt thiết kế.** Tiêu đề trên thanh: sheet địa điểm, trang ngày đẩy trong Hôm nay, trang khách sạn, thẻ chỗ ngắm Fuji; trên hai cỡ máy (ví dụ một máy Pro và một máy Pro Max), cuộn chậm qua ảnh | tên nhỏ và mép mềm hiện khi ảnh gần cuộn hết (đáy ảnh còn khoảng 130 pt dưới thanh) như bản trước; ở đầu trang và lúc vừa mở xong chưa cuộn thì không có | |
| 10 | **Duyệt thiết kế.** Mở một trang album, chụp màn (ảnh ghép vừa làm, từ bộ nhớ); tắt hẳn app, mở lại đúng trang đó, chụp màn (ảnh ghép đọc từ đĩa, JPEG). Phóng to phần tan | hai ảnh như nhau: không có khối JPEG, không có dải màu trong phần mờ | |
| 11 | Bật Giảm độ trong suốt (Cài đặt › Trợ năng › Màn hình & cỡ chữ), mở một trang địa điểm và một trang ngày | không có bản mờ dưới ảnh, ảnh nét tan vào màu trang như bản trước với Giảm độ trong suốt; không có `photo.ambient` | |
| 12 | Bật Giảm chuyển động, làm lại bước 1a và 8 | ảnh ghép vẫn mờ dần lên, màu trang vẫn mờ dần sang (cùng 0,2 giây); không có chuyển động nào khác | |
| 13 | Đang mở một trang album, đổi sáng/tối từ Control Center rồi quay lại app | trang sang bản sáng/tối của cùng màu, không chớp; không có `photo.ambient` mới | |
| 14 | **Duyệt thiết kế.** Chụp màn trước và sau, sáng và tối: trang địa điểm, trang ngày, trang khách sạn, thẻ chỗ ngắm Fuji, ở đầu trang. Bản "trước" build từ `866f093`. Mỗi trang và mỗi chế độ một file trong `docs/perf/screens-5.1b/`, trước bên trái, sau bên phải: `place-light.png`, `place-dark.png`, `day-light.png`, `day-dark.png`, `stay-light.png`, `stay-dark.png`, `fuji-light.png`, `fuji-dark.png` | giống nhau; khác biệt duy nhất được chấp nhận: màu nền không theo ảnh khi vuốt (ảnh thứ hai trở đi nằm trên màu của ảnh đầu). Ghi nhận xét về độ nét của ảnh và độ mờ | |
| 15 | Bật Nguồn điện thấp (Control Center). Mở một trang album chưa từng mở (ảnh chưa ghép); rồi, trang vẫn mở, tắt Nguồn điện thấp. Đọc các `photo.ambient` | lúc Nguồn điện thấp bật: không có `made`; ảnh vẫn hiện (ảnh nét phủ kín khung, chưa có bản mờ dưới phần tan). Tắt đi: đúng một `made` cho ảnh đang hiện, ảnh ghép mờ dần lên trên. Một trang đã mở trước đó vẫn hiện ảnh ghép khi Nguồn điện thấp bật (`disk` sau khi mở lại app) | |

## 5.2

Bản Release, Instruments như `docs/perf/2026-11-baseline.md`: track os_signpost (`tech.delphyra.jp27` / `perf`),
SwiftUI (View Body), Animation Hitches. Tên ở chân ảnh đầu trang (trang địa điểm thường, "Đang ở quán", trang Fuji)
không còn nằm trên `ultraThinMaterial` che bằng mask: dưới nó là bản mờ 160 px của chính ảnh, phần sau chân ảnh vẽ
một lần thành một ảnh nhỏ với độ mờ dần lên trộn sẵn vào alpha, lớp tối 0,42 đè lên; không có bản mờ thì chỉ lớp tối
0,55. Mỗi lần vẽ ảnh nhỏ ấy là một event `hero.foot` "`<ảnh hay picture> <rộng>x<cao>`", cỡ chân ảnh tính bằng điểm.
Trang Fuji chưa có bản mờ (Task 5.3 đưa vào ảnh chụp địa hình đã làm mờ): tạm thời chỉ lớp tối 0,55 trên bản đồ.
Bước 5, 6, 9 và 10 là **duyệt thiết kế** (mắt người, không có số); PR ghi "Cần duyệt thiết kế" cho 5.2.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Simulator › Debug › Color Off-screen Rendered. Mở sheet một địa điểm thường (không phải kiểu album; chạm ghim trên tab Bản đồ), trang "Đang ở quán" (nút "Nói ở quán" trên trang một quán ăn hay cửa hàng có ảnh), trang Fuji; nhìn chân ảnh lúc zoom ra và lúc cuộn | chân ảnh không vàng; ở trang Fuji chỉ hai nút kính ("Bản đồ 3D", "Tìm bằng camera") được phép vàng | |
| 2 | S3 (tab Lịch trình → trang Fuji, `push.plan`), Metal System Trace trên máy: thời gian GPU mỗi khung trong lần mở và trong 1,2 giây bản đồ bay khi đổi vùng, so với baseline (`a996140`) | giảm so baseline (đây là phần vật liệu rời khỏi bản đồ sống; trang Fuji chưa có bản mờ) | |
| 3 | Sheet một địa điểm thường (S2 với một ghim không phải kiểu album) và trang "Đang ở quán": hitch và View Body trong lần mở; đếm `hero.foot` | 0 hitch; một `hero.foot` cho mỗi lần mở có bản mờ trong bộ nhớ (thêm một khi chân ảnh đổi cao, ví dụ vuốt sang ảnh có hay không có dòng tác giả); không có chuỗi `hero.foot` mỗi khung trong lúc zoom (nếu có: lần zoom bố trí chân ảnh ở nhiều cỡ, ghi lại) | |
| 4 | Time Profiler, bước 3: thời gian của `FootPicture.draw` (vẽ ảnh nhỏ trên main thread), hay của hàm gọi nó `FootPicture.picture` nếu nó đã được inline | dưới 1 ms mỗi lần (ước tính: ảnh tối đa khoảng 100 × 50 px với bản mờ 160 px) | |
| 5 | **Duyệt thiết kế.** Địa điểm thường có nhiều ảnh: vuốt chậm, vuốt nhanh | ghi lại lúc nào chân ảnh đổi sang bản mờ của ảnh mới (đổi ngay, không mờ dần) và chỗ đó có thành một cú "giật" không. Nếu có: phương án dự phòng là mỗi trang ảnh mang bản mờ của riêng nó (trượt cùng ảnh) | |
| 6 | **Duyệt thiết kế.** Bật Giảm độ trong suốt (Cài đặt › Trợ năng › Màn hình & cỡ chữ), mở ba trang của bước 1 | không có bản mờ, chỉ lớp tối 0,55; tên và dòng dưới nó vẫn đọc được trên ảnh sáng (tuyết, trời) | |
| 7 | Bật Nguồn điện thấp. Mở một địa điểm thường chưa từng mở trong lần chạy này; rồi, trang vẫn mở, tắt Nguồn điện thấp | lúc bật: chân ảnh chỉ có lớp tối 0,55 (bản mờ không được làm); tắt đi: bản mờ mờ dần lên một lần (0,2 giây) | |
| 8 | Mở một địa điểm thường có ảnh chưa giải mã (mở app lần đầu, hay ảnh tải từ mạng); đóng rồi mở lại | lần đầu: chân ảnh lớp tối 0,55, rồi bản mờ mờ dần lên một lần sau khi ảnh hiện; lần mở lại: bản mờ có từ khung đầu, không mờ dần | |
| 9 | **Duyệt thiết kế.** Trang Fuji, có mạng: đổi vùng để bản đồ bay 1,2 giây | tên, "富士山", dòng số liệu đọc được trên bản đồ nét (chưa có bản mờ tới Task 5.3) | |
| 10 | **Duyệt thiết kế.** Chụp màn trước và sau, sáng và tối, ở đầu trang. Bản "trước" build từ `7691ad2`. Mỗi trang và mỗi chế độ một file trong `docs/perf/screens-5.2/`, trước bên trái, sau bên phải: `place-bright-light.png`, `place-bright-dark.png` (địa điểm thường, ảnh sáng), `place-dark-light.png`, `place-dark-dark.png` (ảnh tối), `atplace-light.png`, `atplace-dark.png`, `fuji-online-light.png`, `fuji-online-dark.png`, `fuji-offline-light.png`, `fuji-offline-dark.png` | ghi nhận xét: độ mờ so với vật liệu cũ, độ đọc được của chữ trắng (bản mờ không có lớp tối sẵn của vật liệu), chỗ mờ bắt đầu có mềm như trước không. Thêm một ảnh có đường ngang rõ (mái nhà, đường chân trời) chạy qua chỗ mờ bắt đầu: phần mờ dưới tên nối tiếp ảnh nét phía trên, không lệch lên xuống hay sang ngang (tức ảnh nét phủ đúng khung ảnh đầu trang) | |

## 5.5

Bản Release, Instruments như `docs/perf/2026-11-baseline.md`: track os_signpost (`tech.delphyra.jp27` / `perf`),
SwiftUI (View Body) và Animation Hitches. Sheet "Ghi chi" (`ExpenseEditor`) giờ có đủ số tiền, loại, cách trả, ngày và
chỗ ngay từ lúc tạo, trước khung đầu: không còn `onAppear` ghi lại các ô, không còn lượt body thứ hai, và loại/cách trả
chỉ đổi (có hoạt ảnh `Motion.pick`) khi người dùng chọn một chỗ trong danh sách "Ở đâu". Phần dưới ảnh đầu trang của
trang địa điểm (trang thường và trang album), trang Fuji và thẻ điểm ngắm, và cả trang một chuyến tàu, là `LazyVStack`:
mục nào cuộn tới mới được dựng. Trên trang chuyến tàu chỉ thẻ đang theo dõi (`PlanRideLive`) và dải ga
(`PlanStationStrip`) đọc vị trí trực tiếp; mỗi ga chỉ nhận "đã qua" và "ga tới", nên một điểm GPS chỉ vẽ lại các ga đổi.
Bước 6 là **duyệt thiết kế** (mắt người, không có số).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | S7 (Chi tiêu: chạm "Ghi chi", `sheet.expense`): số lần body của `ExpenseEditor` trong khoảng signpost; làm thêm một lần từ trang một địa điểm (nút "Ghi chi" trên thanh, chỗ có sẵn) và một lần sửa một khoản đã ghi (chạm một dòng ở tab Chi tiêu) | 1 lần body mỗi lần mở; loại và cách trả không đổi hay chạy hoạt ảnh sau khung đầu; so với baseline (`a996140`) | |
| 2 | Sheet "Ghi chi" mở, trong một ngày của chuyến (chạy thử được: Cài đặt › Chạy thử), rồi đi bộ vài phút để có nhiều điểm GPS | View Body của `ExpenseEditor` vẫn 1 suốt lúc đi (sheet bên ngoài có thể chạy lại body mỗi điểm GPS; ô nào cũng không đổi). Đi vào trong 150 m của một chỗ khác trong lịch hôm đó, sheet vẫn mở: chỗ, loại, cách trả, số tiền trên sheet không đổi, và View Body của `ExpenseEditor` tăng nhiều nhất một lần | |
| 3 | Mở "Ghi chi" cho chỗ A, chọn chỗ B trong "Ở đâu", rồi chọn lại A | loại và cách trả theo B, rồi theo lại A; mỗi lần chọn một tiếng `pick`; lúc mở không có tiếng nào | |
| 4 | Sửa một khoản có ghi chú dài hơn 500 ký tự (nếu có; khoản cũ từ máy kia hay file CSV) | ô ghi chú hiện 500 ký tự đầu ngay từ khung đầu, có dòng "Ghi chú dài hơn 500 ký tự…"; lưu giữ 500 ký tự đầu như trước | |
| 5 | S2 (tab Bản đồ: chạm ghim → sheet địa điểm, `sheet.place`) với địa điểm có nhiều mục nhất (nhiều section nhất: thực đơn, cửa hàng, Fuji, lịch); ghi tên địa điểm; làm cả một trang thường (không phải kiểu album) | chạm → khung đầu và số lần body của `PlaceView` giảm so baseline (`a996140`) | |
| 6 | **Duyệt thiết kế.** Cỡ chữ Trợ năng lớn nhất (Cài đặt › Trợ năng › Màn hình & cỡ chữ › Chữ lớn hơn). Cuộn chậm từ đầu tới cuối: trang địa điểm của bước 5, trang Fuji (S3), một thẻ điểm ngắm có ảnh (S4, chỗ có "Đường chân trời"), trang một chuyến tàu nhiều ga | không có cú nhảy dưới ngón tay khi một mục được dựng (thẻ số "tới đỉnh · hướng nhìn · độ cao" của điểm ngắm đổi sang xếp dọc mà không đẩy trang); thanh cuộn có thể đổi dài một chút; ghi lại chỗ nào nhảy | |
| 7 | S4 (trang Fuji → chạm một điểm ngắm, `sheet.fujiSpot`) và S3 (`push.plan`, trang Fuji): chạm → khung đầu, số lần body | giảm so baseline (`a996140`) | |
| 8 | Thẻ điểm ngắm có ảnh, có mạng: cuộn xuống "Tia ngắm" (bản đồ 3D thứ hai), lên lại đầu trang, rồi xuống lại; xem "Mây ở đây" | bản đồ "Tia ngắm" được dựng khi cuộn tới, không lúc mở; khi quay lại thì ghi xem nó có dựng lại (nháy trắng, bay lại camera) không — Task 5.3 thay bản đồ này; "Mây ở đây" không hiện lại "Đang tải dự báo…" khi đã có số | |
| 9 | Một chuyến đang theo dõi (nút "Theo dõi chuyến"; trên tàu thật, hay chạy thử), trang chuyến tàu mở: View Body qua vài điểm GPS | `PlanRideContent` không chạy lại body theo điểm GPS; `PlanStationStrip` và `PlanRideLive` chạy lại; trong `PlanStationRow` chỉ ga vừa qua và ga tới chạy lại | |

## 5.4

Bản Release, Instruments như `docs/perf/2026-11-baseline.md`: track os_signpost (`tech.delphyra.jp27` / `perf`),
SwiftUI (View Body) và Animation Hitches. Trên tab Bản đồ, mục dưới đường đọc giữa danh sách sáng lên ngay, không có
hoạt ảnh khi ngón tay đang cuộn. Bản đồ (đường đang đọc đậm lên, quầng quanh điểm dừng, các chỗ ghé bên cạnh) và
camera chỉ theo khi đường đọc đứng yên 150 ms, cùng một lúc. Mỗi lần camera được yêu cầu di chuyển có một sự kiện
signpost `map.fly` (`MapTab.move`: cuộn, chạm, Vị trí, Cả ngày, chỗ ghé bên cạnh). Chạm một mục thì bản đồ bay ngay,
và mục sáng lên với `Motion.pick`. Dải điểm dừng chỉ cuộn khi điểm ở giữa thật sự đổi: không hoạt ảnh khi đang cuộn
danh sách, lướt tới (`Motion.settle`) khi chạm.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | S6 (tab Bản đồ, bảng ở giữa: vuốt nhanh dòng thời gian qua 8 mục rồi dừng): đếm sự kiện `map.fly` trong cả cú vuốt; track Hitches trong lúc vuốt | `map.fly` = 1, sau khi dừng; 0 hitch trên dòng thời gian; so với baseline (`a996140`) | |
| 2 | Cùng cú vuốt nhanh, nhìn bản đồ | trong lúc vuốt bản đồ đứng yên: đường đậm, quầng và chỗ ghé không nhảy theo từng mục; khi dừng, chúng đổi cùng lúc với camera bay | |
| 3 | Cuộn chậm, dừng một chút (khoảng nửa giây) ở mỗi mục, qua 3 mục | `map.fly` = 3, mỗi lần sau một lần dừng | |
| 4 | Vuốt nhanh rồi chạm ngay một dòng khác trong vòng 150 ms sau khi dừng (hay chạm một điểm trên dải) | bản đồ bay tới mục vừa chạm và ở đó; không bay ngược về mục cú vuốt dừng | |
| 5 | Vuốt rồi ngay lập tức chọn ngày khác trên dải ngày | bản đồ khung cả ngày mới; không bay tới một điểm của ngày cũ | |
| 6 | Kéo bảng lên toàn màn hình, cuộn qua vài mục, rồi hạ bảng xuống | khi bảng che bản đồ không có `map.fly`; khi hạ xuống, bản đồ bay một lần tới mục đang đọc, đã có quầng và đường đậm | |
| 7 | Bật Giảm chuyển động (Cài đặt › Trợ năng › Chuyển động), chạm một dòng rồi cuộn | camera nhảy thẳng tới chỗ mới, không bay; mục chạm sáng lên với hoạt ảnh ngắn (mờ dần); dải điểm không lướt khi đang cuộn danh sách, còn khi chạm thì cuộn tới chỗ mới bằng một nhịp chậm dần ngắn 0,2 s | |
| 8 | Cuộn danh sách qua vài điểm dừng, nhìn dải điểm trong phần đầu bảng | dải theo kịp, không có hoạt ảnh lướt dưới ngón tay; khi đi qua một đoạn đường (mục di chuyển) điểm ở giữa dải không đổi thì dải không cuộn | |
| 9 | Kéo bản đồ bằng tay, rồi trong vòng 4 giây cuộn danh sách qua một mục và dừng | bản đồ không bay (để yên chỗ người dùng kéo tới); quầng và đường đậm vẫn đổi theo mục đã dừng | |
| 10 | Vuốt nhanh qua vài mục rồi chạm nút Vị trí ngay (trong vòng 150 ms sau mục cuối) | bản đồ bay tới vị trí của mình; quầng, đường đậm và chỗ ghé bên cạnh khớp với dòng đang sáng, không ở lại mục cũ | |

## 5.3

Bản Release, Instruments như `docs/perf/2026-11-baseline.md`: track os_signpost (`tech.delphyra.jp27` / `perf`),
SwiftUI (View Body), Animation Hitches, Allocations. Địa hình 3D ở đầu trang Fuji và trên thẻ chỗ ngắm (ảnh đầu
thẻ khi chỗ đó không có ảnh, và mục "Tia ngắm") giờ là một ảnh MapKit chụp sẵn (`MKMapSnapshotter`), với đỉnh, các
điểm ngắm và tia ngắm vẽ lên trên. Bản đồ sống chỉ được gắn khi trang đã zoom xong và mạng ổn định, nằm dưới ảnh; ảnh
ở lại thêm 0,8 giây rồi mờ đi. Đã gắn thì bản đồ sống ở lại tới khi rời trang, mạng chập chờn không dựng lại nó. "Có
mạng" mà trang dùng giờ chỉ đổi sau khi giữ nguyên 2 giây. Ảnh nằm trong `Caches/Fuji` (giữ dưới 40 MB mỗi lần mở
app, ảnh lâu không dùng đi trước), làm lại được bất cứ lúc nào. Mỗi lần chụp là một event `fuji.snapshot`; mỗi ảnh
chụp xong hay đọc từ đĩa là một event `fuji.picture` "`<tên> made|disk`"; mỗi lần một bản đồ sống lên màn hình là
một event `fuji.live`. Cài đặt › Chẩn đoán (bản Debug) có "Fuji: chỉ ảnh địa hình" (không gắn bản đồ sống, không
giữ qua lần mở app) và "Ảnh địa hình Fuji đã lưu" với nút "Xoá". Bước 1 là spike của chủ dự án. Bước 2, 16, 17, 18 và 22
là **duyệt thiết kế** (mắt người, không có số); PR ghi "Cần duyệt thiết kế" cho 5.3.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | **Spike (Step 1).** Bản Debug, bật "Fuji: chỉ ảnh địa hình", có mạng. Mở trang Fuji, chọn lần lượt bốn vùng; mở thẻ một chỗ ngắm không có ảnh và một chỗ có ảnh (mục "Tia ngắm") | ghi lại: ảnh chụp có giữ địa hình 3D (núi nổi khối) và góc nghiêng camera không, hay ra phẳng nhìn từ trên xuống. Có: một task sau bỏ bớt bản đồ sống (ảnh đứng một mình làm đầu trang). Không: giữ như bây giờ | |
| 2 | **Duyệt thiết kế.** Như bước 1, rồi tắt công tắc, đóng và mở lại trang để thấy bản đồ sống lên dưới ảnh | ghim đỉnh Fuji trên ảnh đứng đúng đỉnh núi như trên bản đồ sống: `Snapshot.point(for:)` có thể bỏ qua độ cao (3.776 m) khi camera nghiêng, ghim khi đó nằm thấp hơn đỉnh. Các điểm ngắm và tia ngắm trùng với bản đồ sống; khi ảnh mờ đi không thấy ghim nhảy chỗ | |
| 3 | S3 (tab Lịch trình → trang Fuji, `push.plan`), lần đầu mở trong lần chạy này. Đọc hitch, View Body và các event trong khoảng `push.plan` | 0 hitch trong zoom; `fuji.live` chỉ sau khi zoom xong, không bao giờ trong zoom; `fuji.snapshot` (nếu ảnh chưa có) cũng sau zoom | |
| 4 | S4 (trang Fuji, chạm một chỗ ngắm có ảnh, `sheet.fujiSpot`), rồi một chỗ không có ảnh | 0 hitch trong zoom. Thẻ có ảnh: không có `fuji.live` tới khi cuộn tới mục "Tia ngắm" (nằm trong `LazyVStack`); thẻ không ảnh: `fuji.live` sau khi zoom xong | |
| 5 | Debug: "Xoá" ảnh địa hình. Có mạng ổn định, mở trang Fuji | trong zoom: nền xanh đêm (chưa có ảnh); sau zoom: bản đồ sống lên dưới nền, 0,8 giây sau nền mờ đi (0,2 giây). Song song: một `fuji.snapshot` và một `fuji.picture` `made`; bản mờ của địa hình tới dưới tên "Fuji" (trước đó chỉ lớp tối 0,55). Ảnh chụp xong trong 0,8 giây ấy không phủ lên bản đồ sống: nền xanh đêm ở lại tới lúc mờ đi, chỉ một lần mờ; ảnh để dành cho lần mở sau và cho bản mờ dưới tên | |
| 6 | Sau bước 5: rời trang, mở lại; rồi tắt hẳn app (vuốt khỏi app switcher), mở lại trang Fuji | lần mở lại: ảnh có từ khung đầu, không có `fuji.snapshot` hay `fuji.picture`; sau khi mở lại app: một `fuji.picture` `disk`, không có `made`. Bản mờ dưới tên có ngay khi ảnh hiện | |
| 7 | Có mạng, bản đồ sống đã lên: chọn vùng khác trên dải vùng, vài lần | camera bay tới vùng mới trong 1,0 giây (trước là 1,2); ghim không trượt từ vùng cũ sang; bản mờ dưới tên giữ của vùng trước tới khi ảnh vùng mới được chụp xong, rồi đổi. Mỗi vùng chưa có ảnh: một `fuji.snapshot` | |
| 8 | Bật "Fuji: chỉ ảnh địa hình" (hay tắt mạng, với ảnh đã có), chọn vùng khác | ảnh vùng cũ đứng yên với ghim của nó tới khi ảnh vùng mới có, rồi mờ chéo sang (0,2 giây); ghim đi cùng ảnh, không trượt | |
| 9 | Network Link Conditioner: trang Fuji mở, bản đồ sống đã lên; bật/tắt mạng 10 lần trong 20 giây. Instruments › Allocations, lọc `MKMapView` | không thêm `MKMapView` nào; `fuji.live` không có thêm; bản đồ không chớp sang sơ đồ la bàn; dòng số liệu không chớp "không có mạng" với mỗi lần lật ngắn hơn 2 giây | |
| 10 | Có ảnh trên đĩa (bước 6). Bật Chế độ máy bay, tắt hẳn app, mở lại trang Fuji và thẻ một chỗ ngắm đã mở trước đó | ảnh địa hình với ghim và tia ngắm (không phải sơ đồ la bàn); dòng số liệu có "không có mạng"; không có `fuji.snapshot`, không có `fuji.live` | |
| 11 | "Xoá" ảnh địa hình, bật Chế độ máy bay, mở trang Fuji; rồi, trang vẫn mở, tắt Chế độ máy bay | lúc không mạng: sơ đồ la bàn; có mạng lại khoảng 2 giây sau: sơ đồ nhường chỗ cho nền xanh đêm, bản đồ sống lên dưới nó (`fuji.live`), 0,8 giây sau nền mờ đi; một `fuji.snapshot` | |
| 12 | Như bước 5, nhưng tắt mạng ngay khi bản đồ sống vừa lên (trong 0,8 giây) | nền không bao giờ được gỡ khi không mạng; có mạng lại (giữ 2 giây) thì đếm lại 0,8 giây rồi mới mờ đi | |
| 13 | Bản đồ 3D (nút "Bản đồ 3D" ở trang Fuji), có mạng, chờ địa hình tải xong; bật Chế độ máy bay một phút, xoay và nghiêng bản đồ; rồi tắt | bản đồ sống ở lại suốt (các mảnh đã tải vẫn hiện), các nút la bàn, nghiêng, vị trí và thước vẫn ở đó; không hiện dòng "Không có mạng…"; Allocations không thêm `MKMapView` | |
| 14 | Bật Nguồn điện thấp. "Xoá" ảnh địa hình, mở trang Fuji, chọn vài vùng; rồi, trang vẫn mở, tắt Nguồn điện thấp | lúc bật: không có `fuji.snapshot`; bản đồ sống vẫn lên khi có mạng; dưới tên "Fuji" chỉ lớp tối 0,55, không làm bản mờ (kể cả cho ảnh đọc từ đĩa). Tắt đi: đúng một `fuji.snapshot` cho vùng đang chọn, rồi bản mờ của nó tới dưới tên. Ảnh đã có trước đó vẫn hiện khi Nguồn điện thấp bật | |
| 15 | Bật Giảm chuyển động, làm lại bước 5 và 7 | camera nhảy thẳng tới vùng mới, không bay; nền và ảnh vẫn mờ đi hay mờ chéo trong 0,2 giây; không có chuyển động nào khác | |
| 16 | **Duyệt thiết kế.** Bước 5 và 6, quay chậm màn hình nếu được: lúc ảnh (hay nền) mờ đi để lộ bản đồ sống | ghi lại: ảnh và bản đồ sống có trùng nhau (khung, màu, độ nét) không, chỗ chuyển có thành một cú "giật" không. Nếu có: ghi lại để chỉnh nhịp 0,8 giây hay cách mờ. Lần đầu có mạng (bước 5): chỉ một lần mờ, của nền xanh đêm; ảnh chụp xong giữa nhịp 0,8 giây không hiện lên giữa chừng | |
| 17 | **Duyệt thiết kế.** Đổi vùng với ảnh (bước 8) và với bản đồ sống (bước 7) | mờ chéo giữa hai ảnh trông liền, không chớp sang nền; bản mờ dưới tên đổi vùng không chớp sang lớp tối 0,55 | |
| 18 | **Duyệt thiết kế.** Chụp màn trước và sau, sáng và tối, ở đầu trang: trang Fuji có mạng, trang Fuji không mạng (có ảnh và không có ảnh), thẻ một chỗ ngắm không có ảnh. Bản "trước" build từ `c1490bc`. Mỗi trang và mỗi chế độ một file trong `docs/perf/screens-5.3/`, trước bên trái, sau bên phải: `fuji-online-light.png`, `fuji-online-dark.png`, `fuji-offline-picture-light.png`, `fuji-offline-picture-dark.png`, `fuji-offline-plot-light.png`, `fuji-offline-plot-dark.png`, `spot-light.png`, `spot-dark.png` | ghi nhận xét: bản mờ địa hình dưới tên và độ đọc được của chữ trắng trên nó; ảnh chụp so với bản đồ sống (màu, độ nét) | |
| 19 | Đang mở trang Fuji, đổi sáng/tối từ Control Center rồi quay lại app | bản đồ sống sang chế độ mới; ảnh của chế độ đó được chụp (một `fuji.snapshot`) hay đọc lại, không chớp | |
| 20 | Network Link Conditioner "100% Loss" (mạng có nhưng không đi). "Xoá" ảnh địa hình, mở trang Fuji, chờ 20 giây; rồi tắt Conditioner, rời trang và mở lại | lần đầu: một `fuji.snapshot`, không có `fuji.picture` (bỏ sau 15 giây), trang không treo; lần mở lại: lại một `fuji.snapshot`, rồi một `fuji.picture` `made` | |
| 21 | Debug: đọc dòng "Ảnh địa hình Fuji đã lưu" sau bước 6 | ghi lại định dạng máy ghi (`HEIC` hay `JPG`) và dung lượng | |
| 22 | **Duyệt thiết kế.** Có ảnh của một vùng trên đĩa (đã mở vùng ấy ở lần chạy trước), chưa mở vùng ấy trong lần chạy này. Mở trang Fuji có mạng ở vùng khác, chờ nền mờ đi (bản đồ sống đã lên); bật Chế độ máy bay, chờ hơn 2 giây, chọn vùng ấy | bản đồ sống ở lại và bay tới vùng mới, không đổi sang ảnh hay sơ đồ la bàn; địa hình vùng mới có thể thiếu mảnh (chưa từng tải trong lần chạy này) dù ảnh của vùng ấy có trên đĩa mà không hiện. Ghi lại trông thế nào (trống, xám, mờ) để quyết định có cần đưa ảnh lên lại trên bản đồ sống khi không có mạng không | |

## 5.6

Bản Release, Instruments như `docs/perf/2026-11-baseline.md`: track os_signpost (`tech.delphyra.jp27` / `perf`),
instrument SwiftUI (View Body và cập nhật layout) và Animation Hitches. Thẻ câu toàn màn hình (`TalkShowCard`, mở
bằng cách chạm một câu trong Sổ tay, Nghe, thẻ tại quán hay trang chủ) giờ có hai bản dựng sẵn, dọc và ngang
(`TalkShowLayout`), mỗi bản dựng một lần trong khung cố định của nó. Cỡ chữ tiếng Nhật của mỗi bản được đo một lần
bằng UIKit và được nhớ theo câu, hướng, khung, cỡ chữ Trợ năng và Chữ đậm. Mỗi lần đo (không có trong bộ nhớ) có một
sự kiện signpost `phrase.fit` "upright|sideways <rộng>x<cao>". Nút xoay đổi bản bằng `TalkTurn`, chỉ có phép xoay và
độ mờ, với `Motion.settle` (một nhịp lò xo nhẹ khi thẻ nằm yên). Bật Giảm chuyển động thì chỉ mờ chéo trong 0,2 giây.
Bước 3 là **duyệt thiết kế** (mắt người, không có số).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | S8 (Sổ tay: mở thẻ một câu dài, ví dụ một câu nghe được trong Nghe dài 3 dòng trở lên, rồi chạm nút xoay; sau đó xoay lại dọc), instrument SwiftUI và track Hitches, từ lúc chạm nút xoay tới khi thẻ đứng yên. Làm thêm với một câu ngắn | body và layout của `TalkShowLayout` chạy một lần ở khung đầu (bản mới vào); giữa khung đầu và khung cuối của lần xoay không có cập nhật layout nào của `Text`; 0 hitch; không có `phrase.fit` lúc chạm (cả hai hướng đã đo lúc mở thẻ); so với baseline (`a996140`) | |
| 2 | Nhìn chậm (quay màn hình rồi xem từng khung) lần xoay ở bước 1, cả hai chiều | chữ không bao giờ nhảy sang cách ngắt dòng khác giữa chừng: mỗi bản giữ đúng cách ngắt dòng của nó từ khung đầu tới khung cuối | |
| 3 | **Duyệt thiết kế.** Cùng lần xoay đó, nhìn bằng mắt ở tốc độ thật | trong lúc xoay, hai bản cố định (dọc và ngang) vừa cùng xoay vừa mờ chéo vào nhau, chỗ trước đây là một khối chữ xoay; thẻ dừng ở hướng mới với một nhịp lò xo nhẹ. Ghi: chấp nhận được hay không, và vì sao | |
| 4 | Cỡ chữ Trợ năng lớn nhất (Cài đặt › Trợ năng › Màn hình & cỡ chữ › Chữ lớn hơn), mở thẻ một câu có cả romaji và nghĩa tiếng Việt, xem cả dọc và ngang | romaji và nghĩa không bị cắt; chữ Nhật không có dấu "…"; chữ Nhật ở cỡ lớn nhất vừa chỗ còn lại, không bị thu nhỏ thêm (lưới 0,5): nếu thấy chữ Nhật nhỏ hẳn đi so với chỗ trống còn lại thì phép đo và SwiftUI lệch nhau, ghi lại câu và hướng | |
| 5 | Bật Chữ đậm (Cài đặt › Trợ năng › Màn hình & cỡ chữ › Chữ đậm), cùng câu, cả dọc và ngang | chữ Nhật không có dấu "…" và không vượt khung; ở cỡ lớn nhất vừa chỗ, không bị lưới 0,5 thu nhỏ thêm. App đo chữ Nhật dưới Chữ đậm ở độ đậm `.heavy`, một bậc trên `.bold`; việc SwiftUI vẽ đúng một bậc như vậy chưa được kiểm, bước này kiểm nó. Ghi lại nếu chữ nhỏ hơn chỗ trống rõ rệt hay bị cắt | |
| 6 | Bật Giảm chuyển động (Cài đặt › Trợ năng › Chuyển động), chạm nút xoay hai lần (ngang rồi dọc) | không có phép xoay: bản cũ mờ đi, bản mới (đã nằm ngang hay đã dựng thẳng) mờ hiện lên trong khoảng 0,2 giây | |
| 7 | Mở thẻ từ một dòng câu (zoom ra), rồi đóng bằng cách kéo xuống (kéo chậm, thả giữa chừng để thẻ quay lại, rồi kéo đóng hẳn). Track os_signpost | chữ ở cỡ cuối ngay khung đầu, không thu nhỏ sau khi mở; trong lúc mở có đúng 2 sự kiện `phrase.fit` (một cho mỗi hướng; nhiều hơn nghĩa là khung đổi cỡ theo từng khung hình của lần zoom); trong lúc kéo đóng: 0 `phrase.fit`; mở lại cùng câu: 0 `phrase.fit`; chạm → khung đầu so với baseline (`a996140`) | |
| 8 | Chạm nút xoay hai lần thật nhanh (lần hai khi lần một chưa xong), rồi làm lại ba lần | thẻ dừng ở hướng của lần chạm cuối; không có bản thứ ba hay bản mờ nào ở lại; chữ không nhảy | |
| 9 | Rung: chạm nút xoay (sang ngang), xoay lại (dọc), chạm Phát âm, Đóng | một tiếng `press` khi sang ngang và khi phát âm; dựng thẳng và đóng thì không rung (như trước) | |

## 5.7

Bản Release, Instruments như `docs/perf/2026-11-baseline.md`: track os_signpost (`tech.delphyra.jp27` / `perf`),
SwiftUI (View Body), Animation Hitches, Allocations. Trang chủ (trước chuyến) nạp trước trang ngày khi thẻ ngày
nằm yên giữa carousel (`Prefetch.day`, lúc cuộn về `idle`) hoặc khi ngón tay chạm xuống thẻ; chạm xuống ảnh bìa
thì nạp trước trang địa điểm (`Prefetch.place`: màu, ảnh giải mã 1800, veil; không ghép ảnh vì chưa biết cỡ sheet).
Mỗi lần nạp bắt đầu có một sự kiện signpost `prefetch` "<day:khoá|place:id> <rest|touch> <rộng>x<cao của hero>"
(`-` khi chưa đo được trang). Tối đa 3 lần nạp cùng lúc, lần mới huỷ lần cũ nhất. Không bao giờ tải ảnh qua mạng.
Bản đồ chỉ được vẽ khi nạp lúc nằm yên và đã biết màu trang; khi chạm chỉ đọc từ bộ nhớ hay đĩa.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | S1 (Bước 4 của brief): dừng carousel ở một thẻ ngày, chờ 2 s, chạm thẻ đó → trang ngày zoom mở. Đo chạm → khung đầu (`push.today`); quay màn 240 fps nếu cần nhìn từng khung | khung đầu < 50 ms; trang ngày mở ra đã có ảnh (ảnh ghép, không phải ô xám hay ảnh rõ thay chỗ), màu trang và bản đồ ngay ở khung đầu; so với baseline (`a996140`) | |
| 2 | Khớp khoá (R-456, T1): open a day that rested: no `map.snapshot` and no `photo.ambient made` event after the push; if either shows, the prefetch key differs from the page's (pruning thrash, T1) | sau khi đẩy trang: 0 `map.snapshot`, 0 `photo.ambient … made` | |
| 3 | Khớp cỡ hero (UNVERIFIED: chiều dài trang chủ đo được có bằng của trang ngày không): mở một ngày chưa nạp trước, so `<rộng>x<cao>` của sự kiện `photo.ambient` với của sự kiện `prefetch` lúc thẻ đó nằm yên. Làm hai lần: thanh tab đầy đủ, và thanh tab đã thu nhỏ (cuộn trang chủ xuống trước) | hai cỡ bằng nhau ở cả hai lần | |
| 4 | Vuốt nhanh carousel ngày qua khoảng 6 thẻ rồi để nó dừng | đúng 1 sự kiện `prefetch day:… rest`, cho thẻ nó dừng; không có sự kiện cho các thẻ lướt qua | |
| 5 | Chạm một ga trên tuyến metro (thẻ tự cuộn tới) | khi thẻ dừng: 1 `prefetch day:… rest` cho thẻ của ga đó; thẻ di chuyển im lặng (không rung) | |
| 6 | Vuốt tay chậm qua từng thẻ | vẫn rung `page` mỗi thẻ như trước (feelsPages chung một bộ theo dõi pha cuộn với việc nạp trước) | |
| 7 | Đặt ngón lên một thẻ, giữ một chút rồi kéo carousel đi (chạm biến thành cuộn), làm qua vài thẻ | có thể có `prefetch day:… touch` cho thẻ đã chạm; không bao giờ quá 3 lần nạp đang chạy (lần thứ tư huỷ lần cũ nhất); không hitch | |
| 8 | Bật Chế độ nguồn điện thấp. Dừng carousel ở một thẻ; rồi chạm thẻ đó | lúc dừng: không có `prefetch`; lúc chạm: 1 `prefetch day:… touch`; trang mở với ảnh rõ thay chỗ (không ghép ảnh mới, như 5.1b) và màu trang | |
| 9 | Đang có lần nạp chạy (vừa dừng ở thẻ), bật Chế độ nguồn điện thấp | lần nạp dừng; không có `photo.ambient … made` sau đó cho đến khi chạm | |
| 10 | Chạm ảnh bìa trên trang chủ | 1 `prefetch place:… touch`; sheet địa điểm mở với màu trang ở khung đầu; ảnh rõ có ngay, ảnh ghép hiện dần sau; khi giữ ngón, ảnh bìa trông như trước (kiểu plain của hệ thống, `PlainButtonStyle().makeBody`) | |
| 11 | Tắt mạng (Chế độ máy bay), dừng ở một ngày có ảnh từ xa chưa tải về | không có yêu cầu mạng nào cho ảnh (Instruments › Network); không có `photo.decode` cho ảnh đó; trang mở ra trên nền giấy như trước | |
| 12 | Bộ nhớ (R-457, T6): dừng lần lượt ở cả 12 thẻ ngày (mỗi thẻ 2 s), rồi cuộn lên ảnh bìa và để nó tự lật một vòng. Track Allocations / Memory | ghi bộ nhớ đỉnh; đếm sự kiện `photo.decode` của ảnh bìa trên trang chủ sau đó (mỗi cái là một ảnh bìa bị đẩy khỏi bộ nhớ, giải mã lại) | |

## 5.9

## 5.8b

## 6.2
