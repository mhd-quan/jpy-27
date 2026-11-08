# Dùng khi mất sóng, Cài đặt và log — 8/11/2026

Hai phạm vi người dùng giao thêm trước khi merge nhánh Phase 4–5 (PR #10) vào `main`, sau khi build thành
công trên máy. Spec này là nguồn cho kế hoạch thực hiện. Thiết kế đã được duyệt trong hội thoại ngày 8/11;
các lựa chọn của người dùng ghi ở mục **Đã chọn**.

## Đã chọn

- Gói "Tải tất cả" gồm cả bốn nhóm: bản đồ và ảnh bản đồ các ngày; ảnh quán, khách sạn; gói dịch
  Nhật–Việt và gói nghe tiếng Nhật; ảnh địa hình Fuji và dự báo mây.
- Sửa tải bản đồ bằng cách để app tự chứa style (không phụ thuộc site).
- Công cụ kiểm tra của bản Debug có cả trong Release, ở trang **Nhà phát triển**.
- Log ghi mọi sự kiện, toạ độ làm tròn khoảng 1 km, giữ 14 ngày, tối đa khoảng 10 MB, xuất `.zip`.
- Tuỳ chọn trải nghiệm thêm: tốc độ đọc tiếng Nhật mặc định; giữ màn hình sáng khi đang theo dõi chuyến.
- Merge PR #10 bằng **squash**, lời commit không có tên model (R-347 khép lại theo cách (b)).

## Hiện trạng và nguyên nhân lỗi

1. **Không tải được vùng bản đồ nào.** Màn "Dùng khi mất sóng" báo "Không kết nối được máy chủ bản đồ" ở
   cả 10 vùng. Nguyên nhân: tên miền `jpy27.delphyra.tech` không có bản ghi DNS nào (A, AAAA, CNAME, HTTPS
   đều trống ngày 8/11; `delphyra.tech` vẫn phân giải). `OfflineMaps.make` hỏi style của gói ở
   `https://jpy27.delphyra.tech/map/jp27-light@<build>.json` trước khi tạo gói (`served`, dòng 417–429);
   không có DNS thì `fetch` trả nil và mọi vùng rơi vào `.refused(unreachable)`. Bản đồ sống vẫn chạy vì
   nó đọc style đóng trong app và lấy tile thẳng từ `tiles.openfreemap.org`.
2. **Ô biểu tượng của Cài đặt bị tràn.** `SettingsIcon` vẽ SF Symbol theo cỡ chữ 15 trong khung 30×30
   nhưng không co và không cắt, nên một glyph rộng (`mountain.2` ở "Bóng địa hình") tràn ra ngoài ô; cỡ
   thật của glyph còn đổi theo cách `Form` xếp biểu tượng của `Label`.
3. **Cài đặt là một trang dài** (`SettingsView.swift`, 1.440 dòng): quyền, chuyến đi, nhật ký, offline,
   chẩn đoán xếp liền; chú thích dài; công cụ kiểm tra chỉ có trong Debug; "Kính trên bản đồ" và "Bóng địa
   hình" chỉ có tác dụng khi bật "Đo khung hình bản đồ".
4. **Không có log lưu lại.** Có `os.Logger` ở vài chỗ (audio, sync, records) nhưng không có gì giữ qua lần
   mở app, và không có cách gửi cho người sửa lỗi.

## Phần 1 — Sẵn sàng khi mất sóng

### 1.1 Style của gói nằm trong app

- Trước khi tạo một gói, app nạp style đóng trong app vào cơ sở dữ liệu của MapLibre bằng
  `MLNOfflineStorage.preloadData(_:forURL:modificationDate:expirationDate:eTag:mustRevalidate:completionHandler:)`
  (có trong header MapLibre 7.0.0), dưới đúng URL mà vùng tải ghi trong định nghĩa của nó, và chỉ tạo gói
  sau khi completion handler được gọi. Hạn dùng đặt xa (không hết hạn trong chuyến), `mustRevalidate: false`.
- URL của style chỉ còn là **khoá**: không ai cần trả lời nó. Giữ dạng `…/jp27-light@<tên build>.json`
  cho build ghim. Khi bản đồ đọc build hiện tại của OpenFreeMap (`currentTemplate`), nội dung là style đóng
  trong app viết lại theo template đó (`StyleInfo.pointing`), dưới một URL khoá riêng cho template ấy (hai
  template khác nhau không bao giờ chung một khoá).
- Nhãn của gói (`PackTag`) vẫn ghi build mà style **đã nạp** thật sự giữ, đọc từ chính bytes đã nạp. Quy
  tắc chọn khoá, bytes và build là hàm thuần trong TripKit, có test.
- Nạp lại mỗi lần mở app, trước khi các gói được đọc và tiếp tục (`configure`), để một gói tải dở không bao
  giờ phải hỏi mạng lấy style. Nạp lỗi thì vùng báo lỗi rõ ràng ("Không nạp được style của bản đồ"), không
  im lặng.
- Bỏ đường hỏi site: không còn trạng thái "Bản đồ trên web khác bản trong app"; bỏ công cụ Debug "Giả style
  khác bản". `checkPinnedTiles` (hỏi OpenFreeMap) giữ nguyên.
- Site và tên miền không còn cần cho app. Việc gắn lại tên miền cho Worker là việc riêng của người dùng
  nếu muốn site chạy.

### 1.2 Gói "Toàn tuyến"

Một vùng thêm, id `overview`, tên "Toàn tuyến", đứng đầu danh sách: khung bao của mọi vùng cộng lề, zoom
5–10 (vài trăm tile). Nhờ nó bản đồ thu nhỏ và ảnh bản đồ của ngày đi qua nhiều vùng vẫn vẽ được khi mất
sóng. Khung bao tính bằng hàm thuần trong TripKit, có test.

### 1.3 Các mục và trạng thái

Trang "Dùng khi mất sóng" có một danh sách "Sẵn sàng khi mất sóng", mỗi dòng một mục, mỗi dòng có trạng
thái, dung lượng khi biết, và nút tải hoặc thử lại riêng:

| Mục | Sẵn sàng khi | Ghi chú |
| --- | --- | --- |
| Bản đồ | mọi vùng (cả Toàn tuyến) hoàn tất cho build bản đồ đang đọc | danh sách vùng như hiện nay, mở ra từ dòng này |
| Ảnh bản đồ các ngày | mỗi ngày (cả ngày thay thế) có ảnh trên đĩa ở cỡ trang đo gần nhất | vẽ qua mạng; ảnh vẽ khi mất sóng không lưu, như hiện nay |
| Ảnh quán, khách sạn | mọi ảnh từ xa đã trên đĩa | `OfflinePhotos` hiện có |
| Ảnh địa hình Fuji | mỗi điểm ngắm và mỗi trang khu Fuji có ảnh ở cỡ đo gần nhất, theo chế độ sáng tối đang dùng (cả hai khi Giao diện là Tự động) | MapKit snapshotter, cần mạng |
| Dự báo mây | đỉnh và mọi điểm ngắm có dự báo tải trong 12 giờ qua | chỉ giữ bản gần nhất; dòng ghi giờ cập nhật |
| Gói dịch Nhật–Việt | `LanguageAvailability` báo đã cài | iOS hiện hộp xác nhận của nó |
| Gói nghe tiếng Nhật | `AssetInventory` báo đã cài cho `SpeechTranscriber` ja-JP | máy không hỗ trợ: "Máy này chưa nghe được tiếng Nhật" |

Trạng thái của mỗi mục là một trong: sẵn sàng; thiếu (kèm "x/y" khi đếm được); đang tải (kèm phần trăm);
chờ mạng; lỗi (kèm lý do); không hỗ trợ trên máy này. Tổng hợp cho dòng ở trang chính: "Sẵn sàng", "Thiếu
N mục", "Đang tải 42%", hoặc "Cần tải lại" khi bản đồ cũ. Mô hình trạng thái và câu tổng hợp là thuần
trong TripKit, có test.

Cỡ trang ngày và cỡ thẻ, trang Fuji đo được lần gần nhất được lưu lại để tải trước dùng; chưa đo lần nào
thì mục đó ghi "Mở trang Hôm nay một lần" (hoặc trang Fuji) thay vì đoán cỡ.

### 1.4 Tải tất cả

- Một nút "Tải tất cả". Bấm lúc đang dùng dữ liệu di động thì hỏi trước: "Đang dùng dữ liệu di động. Bản
  đồ và ảnh có thể tốn vài trăm MB." với "Tải luôn" và "Đợi Wi‑Fi".
- Ngay lúc bấm (trang đang mở, nên hộp xác nhận của iOS hiện được): xin tải gói dịch và gói nghe. Sau đó
  lần lượt: ảnh quán, khách sạn → bản đồ → ảnh bản đồ các ngày → ảnh địa hình Fuji → dự báo mây. Thứ tự
  là hàm thuần trong TripKit; mục đã sẵn sàng thì bỏ qua.
- Vẫn là một việc tải của app (`Downloads`): chạy tiếp khi chuyển sang phần khác của app, theo dõi lại
  khi mở lại app, một Live Activity cho cả việc (continued processing task như hiện nay). Dòng tiến độ thêm
  các mục mới. "Xong" chỉ khi mọi mục sẵn sàng; nếu không, ghi mục nào thiếu.
- Mỗi bước bắt đầu, xong hay lỗi đều ghi log (Phần 3).

## Phần 2 — Cài đặt

### 2.1 Ô biểu tượng

Mọi dòng dùng một kiểu ô: 30×30, góc 8, nền màu; glyph co cho vừa trong khoảng 60% ô (resizable, giữ tỉ
lệ, cùng độ đậm) và bị cắt theo khung ô. Không glyph nào tràn ra được, bất kể glyph rộng hay cỡ chữ hệ
thống.

### 2.2 Bố cục

Trang chính (từ trên xuống), mỗi dòng mở một trang và ghi giá trị hiện tại bên phải:

1. **Thẻ chuyến đi** (như hiện nay).
2. **Cần xem** — chỉ hiện khi có việc: sổ ghi chép mở lỗi; quyền bị tắt; bản đồ cần tải lại hoặc chưa sẵn
   sàng từ 14 ngày trước ngày đi; lỗi báo thức gần nhất; **đang giả lỗi** (dải đỏ, có nút tắt).
3. **Chuyến đi** — Ngày thay thế, Tốc độ đi bộ, Chạy thử.
4. **Trải nghiệm** — Giao diện (trang với ba ảnh nhỏ như hiện nay); Bản đồ (trang: "Kính trên bản đồ",
   "Bóng địa hình (tốn pin hơn)" — nay là tuỳ chọn thật, có tác dụng bất kể đang đo; mặc định giữ như cũ:
   kính bật, bóng tắt); Đọc tiếng Nhật (Bình thường / Chậm, là tốc độ của nút đọc thường; "Đọc chậm" vẫn
   luôn chậm); Giữ màn hình sáng khi đi tàu (bật/tắt).
5. **Riêng tư** — Quyền (giá trị "5/6 đã bật"); Nhật ký vị trí (bật/tắt, xoá lịch sử, số chỗ ghé và điểm
   vết).
6. **Dùng khi mất sóng** (Phần 1).
7. **Hỗ trợ** — Kiểm tra; Log; Số đo; Nguồn và ghi công; Nhà phát triển.
8. Chân trang: phiên bản và số build của app, ngày của dữ liệu nghiên cứu.

Mỗi trang con có nhiều nhất một câu chú thích ngắn (khoảng một dòng). `SettingsView.swift` tách thành các
file theo trang trong `Features/Settings/`, với một file chung cho ô biểu tượng, dòng và trang.

### 2.3 Kiểm tra

Trang "Kiểm tra" có nút "Chạy kiểm tra". Mỗi mục cho kết quả ổn, cảnh báo hoặc lỗi, kèm một dòng ngắn:

- **Quyền**: từng quyền app cần.
- **Sẵn sàng khi mất sóng**: tổng hợp của Phần 1.
- **Bộ nhớ**: chỗ trống của máy (cảnh báo dưới 1 GB) và dung lượng app đang dùng (gói bản đồ, ảnh, cache,
  log).
- **Sổ ghi chép**: mở bình thường, không có lỗi lưu đang treo.
- **Nhắc giờ và báo thức**: số nhắc đang chờ, lỗi báo thức gần nhất, số lần đặt lại từ lúc mở app.
- **Đồng bộ**: lần đồng bộ thành công gần nhất với máy kia.
- **Mạng**: có mạng hay không; máy chủ tile và máy chủ dự báo có trả lời không.
- **Đồng hồ**: đang Chạy thử thì cảnh báo.

Kết quả lần chạy gần nhất được lưu (giá trị của dòng ở trang chính, và đi kèm khi xuất log) và ghi vào log.
Thứ tự, mức và câu tổng hợp là thuần trong TripKit, có test.

### 2.4 Nhà phát triển

Có cả trong Release. Gồm mọi công cụ hiện chỉ có trong Debug: báo thức thử 2 và 5 phút; báo thức trong
hệ thống; giả lỗi lưu; giả lỗi đọc sổ chi; thử ghi trùng chỉ số; thông báo "Đã tới" thử (hai kiểu); vị trí
lúc; so khung bản đồ; ảnh bản đồ đã lưu; so màu ảnh; Fuji chỉ ảnh địa hình; ảnh địa hình Fuji đã lưu và xoá;
đo khung hình bản đồ. Bỏ "Giả style khác bản" (1.1).

- Bật một công cụ giả lỗi phải qua hộp xác nhận. Không công cụ giả lỗi nào giữ trạng thái qua lần mở app
  sau. Khi một công cụ giả lỗi đang bật, trang chính hiện dải đỏ ở mục Cần xem.
- Mỗi lần dùng một công cụ đều ghi log.

### 2.5 Hai tuỳ chọn mới

- **Đọc tiếng Nhật**: lưu trong `UserDefaults`; `Speaker.say(_:)` không chỉ định tốc độ thì đọc theo
  tuỳ chọn này; lời gọi "Đọc chậm" vẫn đọc chậm.
- **Giữ màn hình sáng khi đi tàu**: khi bật, trong lúc có chuyến đang theo dõi (`RideLiveService`) và app
  đang mở, màn hình không tự khoá. Việc giữ màn hình sáng đi qua một chỗ duy nhất nhận nhiều lý do (thẻ đưa
  nhân viên xem ở Nói chuyện đang dùng nó), nên tắt lý do này không làm tắt lý do kia. Logic gộp lý do là
  thuần, có test.

## Phần 3 — Log

### 3.1 Lưu

- Mỗi ngày một file JSON Lines trong `Application Support/Logs/`, tên theo ngày của máy
  (`yyyy-MM-dd.jsonl`). Mỗi dòng: thời điểm (ISO 8601, mili giây), mức (`info`, `warning`, `error`), nhóm,
  câu, và các trường phụ dạng chuỗi.
- Ghi ở nền, theo đợt (vài giây một lần, hoặc khi đủ một số dòng), và ghi hết ra đĩa khi app rời màn hình.
  Mọi dòng cũng đi tới `os.Logger` cùng subsystem và nhóm, nên Console vẫn đọc được.
- Giữ 14 ngày và tối đa khoảng 10 MB; quá thì xoá ngày cũ nhất trước, không bao giờ xoá file của hôm nay.
  Quy tắc giữ và xoá là thuần trong TripKit, có test.
- Không ghi được log thì không làm phiền người dùng, nhưng trang Log hiện lỗi đó.

### 3.2 Ghi gì

Mở app, vào nền, quay lại; mọi lỗi lưu (cùng chỗ đã tới UI); từng bước của việc tải offline và lỗi của gói
bản đồ; nạp style; kiểm build tile; đặt, đổi, huỷ nhắc giờ, geofence và báo thức, cùng lỗi của chúng; theo
dõi chuyến (chọn, bắt đầu, kết thúc); vào và ra geofence; đồng bộ (kết nối, gửi, nhận, lỗi); dự báo (nguồn,
lỗi); gói ngôn ngữ; kết quả kiểm tra; thay đổi tuỳ chọn; công cụ nhà phát triển; báo cáo crash và treo máy
của MetricKit (`MXDiagnosticPayload`, giữ nguyên JSON trong thư mục log).

Không ghi: chữ người dùng tự gõ (ghi chú, tên khoản chi, nhật ký); tên máy của người kia (ghi vài ký tự đầu
của dấu vân tay thay vào); toạ độ chính xác — mọi toạ độ làm tròn tới 0,01° (khoảng 1 km) bằng một hàm
thuần trong TripKit, có test.

### 3.3 Trang Log và xuất

- Trang "Log": các dòng mới nhất (khoảng 200), lọc Tất cả / Cảnh báo / Lỗi; mỗi dòng có giờ, nhóm, câu.
- "Xuất log": tạo `JP27-log-<ngày>-<giờ>.zip` gồm các file log, báo cáo crash và treo máy, các payload
  MetricKit đang giữ, và `info.json` (phiên bản và build, phiên bản iOS, đời máy, ngôn ngữ, múi giờ, chỗ
  trống, các tuỳ chọn không riêng tư, trạng thái sẵn sàng offline, kết quả kiểm tra gần nhất), rồi mở bảng
  chia sẻ. Nén bằng `NSFileCoordinator` với tuỳ chọn `.forUploading`, không thêm thư viện. Làm ngoài main.
- "Xoá log" có hộp xác nhận. Dòng ở trang chính ghi tổng dung lượng log.

## Ràng buộc

Giữ mọi ràng buộc của hợp đồng Phase 4–5 (`docs/superpowers/plans/2026-11-04-execution-contract-phase4-5.md`):
không `Task.detached`, `DispatchQueue.global`, `@unchecked Sendable`, `nonisolated(unsafe)` hay
`MainActor.assumeIsolated` khi không có lý do ghi ngay trên dòng; không lỗi lưu im lặng (`lint-saves`);
chuyển động qua token và tôn trọng Reduce Motion (`lint-motion`); Low Power Mode dừng việc nền không cần;
chữ tiếng Việt theo giọng hiện có; không đụng `src/data` (R-86); giữ quy tắc chạy thử; không tên model trong
repo. TripKit không import framework chỉ có trên Apple, mọi test chạy bằng `swift test` trên Linux. Code app
chỉ biên dịch trong CI "App builds", phải 0/0 cảnh báo.

## Kiểm

- TripKit: test cho khoá, bytes và build của style nạp; khung bao Toàn tuyến; mô hình sẵn sàng và câu tổng
  hợp; thứ tự tải; kết quả kiểm tra và câu tổng hợp; dòng log và cách mã hoá; làm tròn toạ độ; quy tắc giữ
  và xoá log; gộp lý do giữ màn hình sáng.
- CI "App builds" 0/0; `swift test`; `node --test 'scripts/*.test.mjs'`; `lint-saves`; `lint-motion`;
  `check-plan`.
- Những gì chỉ thấy được trên máy ghi thành dòng trong `docs/superpowers/checklists/2026-11-device-offline-settings.md`
  với ô trống, không bao giờ báo là đã làm. Dòng đầu tiên: tải một vùng nhỏ có mạng rồi bật Chế độ máy bay
  và mở bản đồ vùng đó — nếu gói vẫn báo không kết nối được, MapLibre không đọc style đã nạp và cần phương án
  khác (gắn lại tên miền cho site là đường lui).

## Ngoài phạm vi

Bản đồ MapKit sống của trang Fuji khi mất sóng (chỉ có ảnh địa hình); bản đồ offline của Apple Maps; tài
liệu đo hiệu năng Phase 4–5 (vẫn là việc của người dùng); đổi build tile ghim; deploy site hay sửa DNS.

## Kết thúc nhánh

Sau khi các task qua review và CI 0/0: cập nhật mô tả PR #10 (thêm hai phạm vi, việc người dùng làm trên
máy), rồi squash-merge vào `main` với tiêu đề và lời commit đặt tường minh, không có tên model (mặc định của
GitHub ghép lời của mọi commit, gồm cả `adc3ea0`).
