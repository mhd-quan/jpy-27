# Kiểm trên máy — Dùng khi mất sóng, Cài đặt và log

Những bước không agent nào làm được: bản đồ offline thật của MapLibre, Chế độ máy bay, tắt hẳn app. Mỗi task của
kế hoạch `docs/superpowers/plans/2026-11-09-offline-and-settings.md` chép bước kiểm của mình vào đây, đã chỉnh theo
code thật; chưa bước nào được làm. Bản build: Release, mở từ màn hình chính, trừ khi bước ghi khác. Điền cột
**Kết quả** (Đạt / Không đạt, kèm điều thấy được).

## § 1 — Task 1: style của gói nằm trong app; gói Toàn tuyến

Trước khi tạo một gói, và mỗi lần mở app, app nạp style đóng trong app vào cơ sở dữ liệu của MapLibre dưới URL mà
gói ghi (`https://jpy27.delphyra.tech/map/jp27-light@<tên build>.json`); tên miền đó không cần trả lời. Nếu MapLibre
không đọc style đã nạp, gói sẽ hỏi tên miền đó và không bao giờ tải được: vùng ghi "Không kết nối được, đang thử
lại" dù có mạng. Khi đó cần phương án khác; đường lui là gắn lại tên miền cho Worker của site.

Làm trên bản cài mới (xoá app JP27 trước bước 1), để bước 5 chưa có ảnh bản đồ nào được lưu.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Có mạng (Wi‑Fi). Cài đặt › Dùng khi mất sóng › Nara › Tải. | Nara qua "Đang chuẩn bị…", "Đang tải · x %", tới "Đã tải · <dung lượng>". Không lúc nào ghi "Không kết nối được, đang thử lại" mà đứng ở 0 % (nếu có: MapLibre không đọc style đã nạp, xem đoạn trên). | |
| 2 | Bật Chế độ máy bay. Mở tab Bản đồ ở Nara, zoom từ 9 tới 16 (thu nhỏ tới cả vùng, phóng to tới phố). | Đủ đường, khối nhà, chữ ở mọi mức zoom đó. Nếu vùng vẫn báo không kết nối được: MapLibre không đọc style đã nạp; đường lui là gắn lại tên miền cho Worker. | |
| 3 | Tắt Chế độ máy bay. Tải một vùng lớn (Tokyo); khi tới khoảng 20 %, vuốt tắt hẳn app (app switcher). Bật Chế độ máy bay, mở app, vào Dùng khi mất sóng. Rồi tắt Chế độ máy bay. | Khi máy bay: Tokyo ghi "Chờ có mạng · x %". Tắt máy bay: Tokyo tải tiếp từ chỗ đã dừng tới "Đã tải", không báo lỗi style và không ghi "Không kết nối được, đang thử lại" khi đã có mạng. | |
| 4 | Có mạng. Tải "Toàn tuyến" (dòng đầu tiên của danh sách). Bật Chế độ máy bay, mở tab Bản đồ, thu nhỏ tới cả Kantō–Kansai. | "Toàn tuyến" tới "Đã tải · <dung lượng>" (vài MB, vài trăm ô). Khi máy bay: có nền bản đồ (bờ biển, đường lớn, tên thành phố) ở zoom 5–10, cả ở chỗ giữa các vùng. | |
| 5 | Vẫn Chế độ máy bay. Mở trang một ngày đi qua hai vùng (ví dụ ngày chuyển từ vùng này sang vùng kia) mà chưa mở lần nào trên bản cài này, nên ảnh bản đồ của nó chưa được lưu. | Ảnh bản đồ của ngày vẽ được, có nền (nhờ Toàn tuyến đã tải), không phải ô trống hay chỉ có đường đi trên nền trơn. | |
| 6 | Cố gắng tối đa, đạt cũng chứng minh ít: chỉ hỏng khi MapLibre đã đẩy style ra khỏi bộ nhớ đệm, mà không có cách bắt nó làm thế. Có mạng. Tải một vùng lớn chưa có (Kyoto, Uji), ở khoảng 20 % chạm vòng để dừng ("Tạm dừng · x %"). Đừng tắt app. Dùng bản đồ sống ở mức phố thật lâu, lướt nhiều khu ở các vùng khác (để bộ nhớ đệm khoảng 50 MB của MapLibre đầy và bỏ bớt đồ cũ). Quay lại, chạm vòng để tải tiếp. | Vùng tải tiếp tới "Đã tải", không ghi "Không kết nối được, đang thử lại" khi có mạng (trước khi chạm, app nạp lại style dưới URL của gói). | |

## § 2 — Task 2: log lưu trên máy, báo cáo crash, xuất `.zip`

Mỗi dòng log đi vào `Application Support/Logs/<yyyy-MM-dd>.jsonl` (ngày theo đồng hồ của máy, giờ trong dòng là giờ
thật kể cả khi đang chạy thử) và tới Console (subsystem `tech.delphyra.jp27`, nhóm là category). Khi app ở trước mặt,
dòng chờ tối đa 2 giây rồi mới ghi; khi app đã rời màn hình, và với mọi dòng lỗi, dòng được ghi ngay. Trang
Cài đặt › Hỗ trợ › Log có từ Task 7; trước đó, đọc các dòng bằng Console trên máy Mac (cắm cáp, chọn iPhone, lọc
subsystem `tech.delphyra.jp27`).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Mở app từ màn hình chính, dùng khoảng 5 phút, về màn hình chính (rời app), đợi một lúc, mở lại. Vào Cài đặt › Hỗ trợ › Log (chọn "Tất cả"). | Có "Mở app" (kèm `version`, `build`, `ios`), "Vào app", "Rời app", "Vào app", đúng thứ tự giờ (dòng mới nhất ở trên cùng). | |
| 2 | Rời app rồi vuốt tắt hẳn app ngay (app switcher), không đợi. Mở lại app, vào trang Log. | Dòng "Rời app" của lần trước vẫn có, ngay trước "Mở app" của lần này (app ghi log ra đĩa trước khi bị treo). | |
| 3 | Trang Log › "Xuất log", lưu vào Tệp. Mở file `.zip` trong Tệp (chạm để giải nén). | File `JP27-log-<ngàyGiờ>.zip` mở được; bên trong có thư mục `JP27-log-…` với `Logs/` (các file `*.jsonl`), `info.json`, và `metrics/` nếu Số đo đã nhận payload nào. Mở một `.jsonl`: mỗi dòng một đối tượng JSON, có `"t":"…Z"` với mili giây. | |
| 4 | Chỉ khi app từng bị crash hay treo: mở app vào ngày hôm sau (MetricKit gửi báo cáo ở lần mở sau). Vào trang Log, lọc "Lỗi". | Dòng "Báo cáo crash, treo máy" (lỗi) với `crashes`, `hangs`, `cpu`, `disk`, `launch`; file xuất có `Logs/diagnostics/<yyyyMMdd>T<HHmmss>Z.json`. Một báo cáo không có crash hay treo hiện là "Báo cáo chẩn đoán" (cảnh báo). | |
| 5 | Trong chuyến, quyền vị trí "Luôn luôn", cần dòng "Vào vùng" của Task 3: vuốt tắt hẳn app buổi tối, hôm sau đi tới một điểm của ngày mà không mở app (iOS tự mở app ở nền khi vào vùng). Mở app sau đó, vào trang Log. | Có dòng "Vào vùng" với `place` và `at` (toạ độ làm tròn 0,01°), giờ là lúc tới điểm, dù app không mở lúc đó. | |

## § 3 — Task 3: dòng log của từng việc

Các dòng đọc ở trang Log (Task 7), hoặc trước đó bằng Console trên máy Mac (subsystem `tech.delphyra.jp27`). Không
dòng nào được mang tên máy, chữ người dùng gõ hay nói, hay toạ độ chưa làm tròn: máy kia hiện bằng `peer`, 8 chữ số
hex đầu của dấu vân tay khoá của nó. Báo thức thử nằm ở Cài đặt › Nhà phát triển (Task 4), chỉ có ở bản Debug cho tới
Task 7 (từ đó có ở mọi bản), nên bước 2 làm trên bản Debug.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Có mạng. Cài đặt › Dùng khi mất sóng › tải một vùng chưa có (ví dụ Nara), đợi tới "Đã tải". Vào trang Log. | Theo thứ tự: "Bắt đầu tải" (`areas` = `nara`, `photos` = `false`), "Nạp style" (`build`, `url`), "Vùng xong" (`area` = `nara`, `bytes`), "Kết thúc tải" (`subtitle` = `Xong`). Không có dòng "Vùng xong" cho những vùng đã tải từ trước. | |
| 2 | Bản Debug. Cài đặt › Nhà phát triển › "Báo thức thử sau 2 phút", rồi ngay "Báo thức thử sau 5 phút". Để báo thức reo, tắt nó, rời app rồi mở lại. Vào trang Log. | "Đặt báo thức" (`ride` = `debug.wake`, `at` là giờ UTC dạng `…T…Z`, `source` = `ride`), rồi "Đổi báo thức" với `at` muộn hơn 3 phút; sau khi mở lại: "Bỏ báo thức đã qua" cho `debug.wake`. Không dòng nào có "Ga thử". | |
| 3 | Hai máy đã ghép, cả hai bật đồng bộ và mở JP27 ở gần nhau. Trên máy này ghi một khoản chi có ghi chú (ví dụ "bánh cá thử log") và tự gõ tên một quán không có trong dữ liệu. Đợi máy kia nhận. Vào trang Log của máy này. | "Kết nối máy kia", "Gửi sổ chi" (`peer`, `rows`), "Máy kia đã lưu sổ chi"; có thể có "Nhận sổ chi" (`rows`, `rejected`, `changed`). `peer` là 8 chữ số hex, giống nhau ở mọi dòng của cùng máy kia. | |
| 4 | Trang Log › "Xuất log", mở file `.zip` trong Tệp. Mở các `.jsonl` của hôm nay (ứng dụng đọc văn bản, hoặc trên Mac), tìm tên máy kia (như ở trang đồng bộ), tên máy này, "bánh cá thử log" và tên quán đã gõ ở bước 3. | Không thấy chữ nào trong số đó ở bất kỳ file nào. | |
| 5 | Trong chuyến, có quyền vị trí "Luôn luôn": tới một điểm có vòng geofence của ngày (quán ăn, ga). Vào trang Log. | "Đặt geofence" (`count`, `added`, `removed`) lúc vòng đổi; "Vào vùng" với `place` (id), `kind` và `at` có đúng hai chữ số sau dấu chấm (ví dụ `35.69,139.69`). Không có dòng "Ra vùng": app chỉ theo dõi lúc vào vòng. | |

## § 4 — Task 4: Cài đặt theo trang, ô biểu tượng, Trải nghiệm, Riêng tư

Ô biểu tượng giờ vẽ glyph co vừa khung giữa của ô (18 pt trong ô 30 pt ở Cài đặt; nửa ô ở `GlyphTile`) và cắt theo
góc ô, nên không glyph nào tràn ra được dù rộng hay cỡ chữ lớn. Kính và bóng địa hình nay là tuỳ chọn thật (khoá mới
`map.glass`, `map.relief`; công tắc cũ trong Chẩn đoán không được đọc lại, nên bóng địa hình bắt đầu ở Tắt). Giữ màn
hình sáng đi qua một chỗ (`KeepAwake`) nhận hai lý do: thẻ câu đưa nhân viên xem, và chuyến đang theo dõi khi công
tắc bật; vẫn giữ khi bật Nguồn điện thấp (người dùng đã chọn).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | **Duyệt thiết kế.** Chụp màn ở chế độ Sáng và Tối, ở cỡ chữ mặc định và cỡ lớn nhất (Cài đặt iPhone › Trợ năng › Màn hình & cỡ chữ › Chữ lớn hơn, bật cỡ trợ năng, kéo hết): trang chính của Cài đặt (cả nhóm Cần xem nếu có), Giao diện, Bản đồ (ô "Bóng địa hình" là `mountain.2`, chỗ từng tràn), Quyền, Nhật ký vị trí, Nhà phát triển (bản Debug có thêm công cụ); và các màn dùng `GlyphTile`: Hôm nay (nút "Chạy thử một ngày trong chuyến", thẻ nhật ký, thẻ hỏi quyền vị trí), Sổ tay (ô tình huống, sổ tay hướng dẫn), Lịch trình (các liên kết dưới ngày), trang Fuji (ô tàu), thẻ địa điểm trên tab Bản đồ, Chi tiêu (ô danh mục, đồng bộ sổ chi). | Mọi glyph nằm gọn trong ô của nó, không chạm mép, độ đậm như nhau; ô vẫn 30×30 dù cỡ chữ lớn nhất. Không ô nào trống (tên glyph sai thì ô trống: `circle.lefthalf.filled`, `hand.raised.fill`, `sun.max.fill`, `hammer.fill`, `map.fill` là tên mới). | |
| 2 | Cài đặt › Trải nghiệm › Bản đồ, tắt "Kính trên bản đồ" (không bật "Đo khung hình bản đồ"). Mở tab Bản đồ. | Panel, dải ngày và các nút trên bản đồ có nền đặc, không còn kính. Bật lại: kính trở lại. Dòng Bản đồ ở trang chính ghi "Không kính", rồi "Kính". | |
| 3 | Cũng trang đó, bật "Bóng địa hình", có mạng. Mở tab Bản đồ và trang một ngày ở vùng núi (Hakone, Fuji). Rồi bật Chế độ máy bay, mở lại một vùng đã tải. | Có mạng: có bóng núi trên mọi bản đồ; trang chính ghi "Kính · bóng núi". Máy bay: bản đồ vẫn vẽ như thường, chỉ không có bóng núi (ô độ cao không nằm trong gói), app không báo lỗi. | |
| 4 | Cài đặt › Trải nghiệm › "Đọc tiếng Nhật": Chậm. Vào Sổ tay, chạm nút đọc của một câu; giữ lâu nút đó; mở thẻ câu toàn màn và chạm nút loa. Rồi đặt Bình thường, giữ lâu nút đọc. | Khi Chậm: cả chạm, giữ lâu và nút loa của thẻ đều đọc chậm. Khi Bình thường: chạm đọc thường, giữ lâu ("Đọc chậm") vẫn chậm. | |
| 5 | Bật "Giữ màn hình sáng khi đi tàu" (Tự động khoá của iPhone đặt 30 giây hay 1 phút). Theo dõi một chuyến (thật hoặc Chạy thử), để máy yên 5 phút với app trên màn. Rồi bấm kết thúc chuyến, để yên. | Khi theo dõi: màn không tự khoá. Sau khi kết thúc: màn khoá sau thời gian Tự động khoá của máy. | |
| 6 | Theo dõi một chuyến với công tắc bật, mở một thẻ câu toàn màn (Sổ tay), vào Cài đặt tắt công tắc giữ sáng rồi quay lại thẻ (hoặc kết thúc chuyến trong lúc thẻ mở), để yên. Rồi đóng thẻ. | Thẻ vẫn giữ màn sáng. Đóng thẻ, không còn chuyến giữ sáng: màn khoá theo cài đặt máy. | |
| 7 | Tắt một quyền trong Cài đặt của iPhone (ví dụ Ảnh: Không). Mở Cài đặt của app. Chạm "1 quyền đang tắt" ở Cần xem, bấm "Mở Cài đặt", cho phép lại, quay về app. | Riêng tư › Quyền ghi "4/5 đã bật", Cần xem có "1 quyền đang tắt". Sau khi cho phép lại, trang Quyền vẫn mở (không tự lùi về trang chính) và dòng Ảnh có dấu tích; lùi về: dòng Cần xem đã mất, Quyền ghi "5/5 đã bật". | |
| 8 | Trang chính, cuối trang. Đổi Giao diện, kính, bóng địa hình, tốc độ đọc, giữ sáng, nhật ký vị trí, một ngày thay thế, bắt đầu rồi dừng Chạy thử. Vào trang Log (Task 7) hoặc Console. | Chân trang ghi "JP27 <phiên bản> (<build>) · Dữ liệu nghiên cứu ngày …". Mỗi lần đổi một dòng nhóm `settings`: "Giao diện", "Kính trên bản đồ", "Bóng địa hình", "Đọc tiếng Nhật", "Giữ màn hình sáng khi đi tàu", "Nhật ký vị trí", "Ngày thay thế", "Chạy thử", mỗi dòng một `value` là lựa chọn (`dark`, `false`, `slow`, `on`, khoá ngày…), không có chữ tự gõ. | |

## § 5 — Task 5: Sẵn sàng khi mất sóng — trạng thái 7 mục, gói ngôn ngữ

Cài đặt › Dùng khi mất sóng mở đầu bằng nhóm "Sẵn sàng khi mất sóng": Bản đồ, Ảnh bản đồ các ngày, Ảnh quán, khách
sạn, Ảnh địa hình Fuji, Dự báo mây, Gói dịch Nhật–Việt, Gói nghe tiếng Nhật. Danh sách vùng nay ở trang con "Bản đồ
offline" (chạm dòng Bản đồ). Dòng "Dùng khi mất sóng" ở trang chính ghi "Sẵn sàng", "Thiếu N mục", "Đang tải 42%"
hoặc "Cần tải lại". Ảnh bản đồ các ngày, Fuji và dự báo chỉ tải được bằng "Tải tất cả" (Task 6); ở đây chỉ kiểm
trạng thái của chúng. Ảnh Fuji được đếm cả sáng lẫn tối cho mỗi khu và mỗi thẻ chỗ ngắm có ảnh chụp; thẻ không có ảnh chụp luôn trên nền xanh hoàng hôn nên chỉ đếm ảnh tối (hiện là 69 ảnh).

Làm trên bản cài mới (xoá app JP27 trước bước 1), Wi‑Fi, trừ khi bước ghi khác.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Bản cài mới, **chưa mở** trang Fuji hay thẻ chỗ ngắm nào. Mở Cài đặt › Dùng khi mất sóng. | Trong chốc lát các dòng ghi "Đang kiểm tra…", rồi: Ảnh bản đồ các ngày ghi "x/y ngày" (trang Hôm nay đã hiện lúc mở app) hoặc "Mở trang Hôm nay một lần"; Ảnh địa hình Fuji ghi "Mở trang Fuji một lần"; Dự báo mây ghi "Chưa mới · 0/32 nơi"; trang chính ghi "Thiếu N mục". | |
| 2 | Mở trang Fuji (tab Lịch trình › Fuji), quay lại trang Dùng khi mất sóng. Rồi mở thẻ chỗ ngắm **không có ảnh chụp**: hiện chỉ có Fujisan Yume no Ōhashi (ngày 5; đầu thẻ là địa hình), quay lại. Rồi mở thẻ một chỗ ngắm **có ảnh chụp** (ví dụ Tháp Chūreitō: có mục "Tia ngắm"), quay lại. | Sau trang Fuji: "Mở một chỗ ngắm chưa có ảnh chụp". Sau thẻ không ảnh: "Mở một chỗ ngắm có ảnh chụp". Sau thẻ có ảnh: "x/69 ảnh" (x nhỏ: chỉ những ảnh đã vẽ khi mở). | |
| 3 | Dòng Bản đồ: chạm vào. Trên "Bản đồ offline", tải "Toàn tuyến" và một vùng nhỏ (Nara). Vuốt trái một vùng đã tải. Quay lại trong lúc đang tải. | Trang con có đủ vùng như trước, "Toàn tuyến" đầu tiên; vuốt trái hiện "Xoá", giữ lâu hiện menu "Xoá", chạm "Tải" và vòng có rung như trước. Ở trang Dùng khi mất sóng, dòng Bản đồ ghi "Đang tải x%" rồi "2/11 vùng · <dung lượng>"; trang chính ghi "Đang tải x%" khi đang tải. | |
| 4 | Dòng Ảnh quán, khách sạn: chạm "Tải" (hay vòng). Đợi xong. | Dòng tới "Đã lưu đủ N ảnh"; trước đó vòng chạy và dừng được như trước. | |
| 5 | Dòng Gói dịch Nhật–Việt (nếu ghi "Chưa tải"): chạm "Tải". | iOS hiện **hộp xác nhận của nó** đúng một lần (không hai hộp chồng nhau), phủ trên trang này. Xác nhận, đợi: dòng tới "Sẵn sàng" (có thể cần ra vào trang một lần). Nếu gói đã có từ trước: dòng ghi "Sẵn sàng", không có nút. Máy không dịch được: "Máy này chưa dịch được Nhật sang Việt". | |
| 6 | Dòng Gói nghe tiếng Nhật (nếu ghi "Chưa tải"): chạm "Tải". | Dòng ghi "Đang tải x%", tăng khoảng mỗi giây, rồi "Sẵn sàng". Sau đó tab Sổ tay › Nghe bắt đầu nghe ngay, không tải gì thêm. Máy không có tiếng Nhật cho nghe (nếu có máy như thế): "Máy này chưa nghe được tiếng Nhật", không có nút. | |
| 7 | Gói nghe chưa có (máy khác, hoặc Cài đặt iPhone › Chung › Dung lượng: không xoá được thì bỏ bước này). Bật Chế độ máy bay, chạm "Tải" ở Gói nghe. | Nút bị mờ khi máy bay; nếu bấm được trước khi mất mạng: dòng ghi lý do lỗi hoặc "Chờ có mạng", không treo "Đang tải 0%" mãi. | |
| 8 | Có mạng. Mở trang Fuji và để thẻ "Mây lúc này" tải; mở vài thẻ chỗ ngắm. Quay lại Dùng khi mất sóng. | Dự báo mây ghi "Chưa mới · x/32 nơi · cập nhật <giờ Nhật>" (giờ của dự báo cũ nhất; thêm "ngày d/m" nếu không phải hôm nay ở Nhật). | |
| 9 | Đổi Giao diện của máy (Sáng ↔ Tối) khi đang ở trang Hôm nay, rồi về Dùng khi mất sóng. | Ảnh bản đồ các ngày đếm lại theo chế độ mới (ngày không có ảnh bìa đổi ảnh bản đồ theo sáng tối), số có thể giảm; không treo, không lỗi. | |
| 10 | Mở Log (Task 7) hoặc Console sau các bước trên. | Nhóm `offline` có dòng "Sẵn sàng khi mất sóng" với `item`, `state` mỗi khi một mục đổi loại trạng thái (không phải mỗi phần trăm); "Tải gói nghe tiếng Nhật" `start`/`installed`. Không có chữ người dùng gõ. | |
| 11 | **Chỉ kiểm được từ 4/10/2027** (14 ngày trước chuyến, theo đồng hồ thật; Chạy thử không đổi được). Khi còn mục thiếu, mở Cài đặt. Rồi làm cho đủ, mở lại. | Cần xem có "Chưa sẵn sàng khi mất sóng", chạm vào mở Dùng khi mất sóng; khi bản đồ cũ thì chỉ có "Bản đồ offline cần tải lại". Khi mọi mục sẵn sàng (hoặc không hỗ trợ): dòng biến mất. Sau 29/10/2027 (giờ Nhật) không còn hiện. | |

## § 6 — Task 6: Tải tất cả

Trang Dùng khi mất sóng có nút "Tải tất cả" ở nhóm trên cùng (cùng dòng tiến độ của việc tải) khi còn mục thiếu; nút mờ
khi không có mạng hoặc lúc trang còn đang kiểm tra. Một lần bấm: gói dịch và gói nghe bắt đầu ngay (nếu thiếu), rồi một
việc tải gồm mọi vùng bản đồ còn thiếu, ảnh quán, khách sạn, ảnh bản đồ các ngày, ảnh địa hình Fuji và dự báo mây, với
**một** Live Activity. Ảnh bản đồ các ngày và Fuji chỉ vẽ khi app đang mở (rời app thì chờ, Live Activity ghi "chờ mở
app"); dự báo tải được cả khi rời app. Việc tải chỉ ghi "Xong" khi cả 7 mục đều "Sẵn sàng" (hoặc máy không hỗ trợ); nếu
không, dòng cuối ghi mục nào thiếu ("Gói dịch chưa tải", "Fuji 60/69 ảnh"…). Ba dòng Ảnh bản đồ các ngày, Ảnh địa hình
Fuji, Dự báo mây có nút "Tải" riêng khi còn thiếu.

Trước bước 1: bản cài mới, đã mở trang Hôm nay, trang Fuji, một thẻ chỗ ngắm không có ảnh chụp và một thẻ có ảnh chụp
(§ 5 bước 2), để các mục không còn "Mở … một lần". Wi‑Fi, trừ khi bước ghi khác.

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Wi‑Fi. Cài đặt › Dùng khi mất sóng › "Tải tất cả", từ đầu (chưa tải gì). Ở lại trong app đến khi xong; kéo màn hình khoá xuống xem Live Activity vài lần. | Có rung khi bấm. Hộp xác nhận gói dịch của iOS hiện một lần. Live Activity ghi tiến độ, lần lượt có "Bản đồ x/11 vùng", "Ảnh x/y", "Ảnh bản đồ x/13", "Fuji x/69", "Dự báo" và phần trăm; phần đã xong thì không còn ghi; thanh tiến độ không lùi. Mọi dòng tới "Sẵn sàng" (hoặc "Máy này chưa …"). Dòng cuối, ở trang và ở Live Activity: "Xong". | |
| 2 | Dữ liệu di động (tắt Wi‑Fi). Bấm "Tải tất cả". Chọn "Đợi Wi‑Fi". Bật lại Wi‑Fi, đợi một phút. | Hộp "Đang dùng dữ liệu di động" / "Bản đồ và ảnh có thể tốn vài trăm MB." với "Tải luôn" và "Đợi Wi‑Fi". "Đợi Wi‑Fi": không tải gì, không Live Activity; có Wi‑Fi lại cũng không tự tải. | |
| 3 | Dữ liệu di động, gói dịch chưa có. Bấm "Tải tất cả" › "Tải luôn". | Hộp hỏi đóng xong mới hiện hộp xác nhận gói dịch của iOS, đúng một lần; việc tải bắt đầu như bước 1. | |
| 4 | Xoá app, cài lại, làm phần "Trước bước 1". "Tải tất cả"; khi Live Activity ghi "Fuji x/69", về màn hình chính. Đợi 10 s, rồi dừng từ nút trên Live Activity. Mở lại app. Bấm "Tải tất cả" lần nữa. | Khi ở ngoài app: Live Activity ghi "Fuji x/69 · chờ mở app" (hoặc dự báo đang chạy), số Fuji không tăng. Sau khi dừng và mở lại: dòng việc tải ghi "Đã dừng". Bấm lại: đi tiếp từ chỗ thiếu (x không về 0), tới "Xong". | |
| 5 | Đang vẽ ảnh bản đồ các ngày (Live Activity "Ảnh bản đồ x/13"), về màn hình chính 10 s rồi mở lại app, không dừng. Đợi xong. Bật Chế độ máy bay, mở từng ngày (cả ngày dự phòng). | Mở lại thì việc tải đi tiếp. Không ngày nào có ảnh bản đồ trắng hay trống; ảnh hiện ngay, không chờ. | |
| 6 | Bắt đầu "Tải tất cả", khi đang vẽ Fuji thì tắt hẳn app (vuốt lên trong trình chuyển app, không dừng gì). Mở lại app, ở lại trong app. | Việc tải tự đi tiếp (không có Live Activity mới) từ chỗ thiếu, rồi dòng việc tải ghi kết quả. Log có "Tải tiếp việc tải dở" với `extras`. | |
| 7 | Bắt đầu "Tải tất cả", về màn hình chính, dừng từ Live Activity, rồi tắt hẳn app. Mở lại app, ở lại trong app một phút. | Dòng việc tải ghi "Đã dừng"; không vẽ thêm gì (log không có "Bắt đầu phần tải" sau lần mở này). "Tải tất cả" lại thì đi tiếp. | |
| 8 | Sau bước 1 (mọi dòng "Sẵn sàng"), mở nhiều trang quán và ngày (để thư mục ảnh đầy thêm), tắt hẳn app, hôm sau mở lại (lần mở app dọn thư mục ảnh). Vào Dùng khi mất sóng. | Ảnh bản đồ các ngày và Ảnh địa hình Fuji vẫn "Sẵn sàng". | |
| 9 | Sau khi xong, bật Chế độ máy bay. Mở từng ngày, trang Fuji, vài thẻ chỗ ngắm (cả có và không có ảnh chụp), tab Sổ tay › Nói chuyện: dịch một câu, bấm nghe. | Đều dùng được: ảnh bản đồ ngày, ảnh địa hình Fuji (sáng và tối theo thẻ), dịch và nghe. Dòng Dự báo mây ghi "Sẵn sàng · cập nhật <giờ Nhật>"; thẻ mây hiện dự báo đã tải. | |
| 10 | Chỉ dòng Ảnh địa hình Fuji còn thiếu (ví dụ xoá app, cài lại, làm phần "Trước bước 1"): chạm "Tải" ở dòng đó. Làm lại với Ảnh bản đồ các ngày và Dự báo mây. | Mỗi nút bắt đầu một việc tải có Live Activity riêng; dòng ghi "Đang tải x%" khi chạy (không còn nút), rồi "Sẵn sàng"; dòng việc tải ghi "Xong" khi đủ phần đó. | |
| 11 | Trong lúc vẽ 69 ảnh Fuji (bước 1), xem bộ nhớ trong Xcode (Debug navigator › Memory) hoặc dùng app bình thường. | App không bị hệ thống tắt giữa chừng (không văng); bộ nhớ không tăng mãi theo từng ảnh. | |
| 12 | Gói nghe đang tải lâu (mạng chậm) khi các phần khác đã xong. | Dòng việc tải có thể ghi "Gói nghe chưa tải" trước khi gói nghe xong; dòng Gói nghe vẫn tới "Sẵn sàng" sau đó. Ghi lại điều thấy được. | |
| 13 | Mở Log (Task 7) sau các bước trên. | Nhóm `offline` có: "Tải tất cả" (`plan`, `expensive`); "Bắt đầu tải" và "Kết thúc tải" có `extras`, `everything`; mỗi phần "Bắt đầu phần tải" và "Xong phần tải" (`part`, `done`, `total`, `paused`); "Chờ mạng để tải tiếp", "Chờ mở app để vẽ tiếp" mỗi lần chờ một dòng (không phải mỗi giây); "Dừng phần tải" khi dừng. Không có một dòng cho mỗi ảnh, không có toạ độ, không có chữ người dùng gõ. | |
