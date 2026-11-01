# JP27 cho iPhone

App iOS của chuyến đi, viết bằng SwiftUI cho iOS 26 (Liquid Glass), chỉnh cho màn hình iPhone Pro Max nhưng vẫn chạy trên iPhone nhỏ hơn. Toàn bộ nội dung của site nằm trong app và dùng được khi mất sóng; phần mới là theo dõi chuyến đi: đã ghé đâu, đã mua gì, đã chi bao nhiêu, đang ở đâu so với lịch.

## Chạy

```sh
brew install xcodegen      # một lần
cd ios && xcodegen         # tạo JP27.xcodeproj từ project.yml
open JP27.xcodeproj
```

Cần Xcode 26 trở lên. Trước khi chạy trên máy thật: điền `DEVELOPMENT_TEAM` trong `project.yml` (hoặc chọn team trong Xcode), rồi bật cho App ID các capability **App Groups** (`group.tech.delphyra.jp27`), **WeatherKit** và **Time Sensitive Notifications**. Bản đồ MapLibre được Swift Package Manager tải về ở lần build đầu.

Khi dữ liệu của site thay đổi:

```sh
node scripts/export-ios.mjs                     # viết lại ios/JP27/Resources/Trip/*.json, ios/Shared/schedule.json, public/map/*.json
cd ios/Packages/TripKit && swift test           # chạy được cả trên Linux
```

`swift test` đối chiếu đồng hồ lịch trình bằng Swift với đầu ra của `scripts/check-plan.mjs` (file `Tests/TripKitTests/Fixtures/check-plan.txt`; chạy lại `node scripts/check-plan.mjs > …` khi lịch đổi).

## Cấu trúc

```
ios/
  project.yml                 XcodeGen: app, widget extension, quyền, chế độ nền
  Packages/TripKit/           lõi không có giao diện, build và test được trên Linux
    Model/                    Trip, Guide: đúng dạng JSON xuất từ site
    Plan/                     PlanEngine (bản Swift của check-plan.mjs), Replanner, Itinerary, Reminders
    Ride/                     RideTracker: ga kế, sắp xuống, Fuji bên nào, giờ tới
    Food/                     MenuMatcher, HeardMatcher: so tên món/câu tiếng Nhật, không dùng AI
    Money/                    hạng mục chi, ước tính, tiền mặt cần cho hai ngày tới
    Nearby/, Tracking/        điểm gần đây, Fuji từ chỗ đứng, geofence, nhật ký, tốc độ đi bộ
  Shared/                     dùng chung app và widget: App Group, Live Activity, schedule.json
  JP27/
    App/                      AppModel, tab bar, điều hướng, deep link jp27://
    Data/                     SwiftData: đánh dấu, bỏ điểm, chi tiêu, nạp tiền, đồ đã mua, nơi đã ghé, vết đi
    Services/                 vị trí, thông báo, AlarmKit, Live Activity, CoreMotion, WeatherKit, bản đồ offline, ảnh
    Design/                   thẻ, dòng timeline, dòng địa điểm, bản đồ MapLibre
    Features/                 Today, Map, Plan, Talk, Spend, Journal, Fuji, Settings
  JP27Widgets/                widget điểm tiếp theo, Live Activity khi đi tàu
```

Ảnh Commons tự host của site (`public/img/commons`) và style bản đồ (`public/map`) được đưa thẳng vào app dưới dạng thư mục, không chép lại.

## Tab bar

| Tab | Dùng khi | Gồm nội dung site |
| --- | --- | --- |
| **Hôm nay** | mở điện thoại là thấy việc kế tiếp | điểm tiếp theo kèm ảnh, giờ rời đi, đang trễ bao nhiêu và nên bỏ gì; phần còn lại của ngày; trước chuyến: đếm ngày, lịch đặt chỗ |
| **Bản đồ** | đang đi bộ | bản đồ ngày, chấm vị trí, khoảng cách tới điểm kế, chỗ rẽ gần đây |
| **Lịch trình** | xem trước, xem lại | 12 ngày theo nơi ngủ, ngày thay thế Kawaguchiko; Ăn uống, Chỗ ở, Trên tàu, Fuji, Đặt chỗ, Mua sắm, Ngân sách |
| **Sổ tay** | ở quầy, ở quán | 32 tình huống, câu riêng của chuyến, tên ga, nghe và dịch, quét menu, cẩm nang (vé, hành lý, hoàn thuế, onsen) |
| **Chi tiêu** | sau mỗi lần trả tiền | sổ chi theo ngày, ví tiền mặt và Suica, ngân sách so với thực chi, giỏ mua sắm |

Thanh phụ dưới tab bar (bottom accessory) luôn cho biết chuyện đang diễn ra: chuyến tàu đang đi (ga kế, Fuji bên nào) hoặc đếm ngược tới lúc phải rời đi.

## Từng yêu cầu dùng gì

| Yêu cầu | Cách làm |
| --- | --- |
| Đánh dấu chỗ đã đi, món đã mua, ghi chi | SwiftData (`Checkmark`, `Purchase`, `Expense`, `Topup`), lưu trong App Group |
| Vị trí trong tương quan lịch | `Itinerary.project`: điểm đang tới, khoảng cách và phút đi bộ theo tốc độ thật, chỗ rẽ của ngày xếp theo khoảng cách |
| Dùng khi mất sóng | toàn bộ dữ liệu và ảnh Commons nằm trong app; gói bản đồ offline MapLibre theo từng vùng; ảnh quán tải trước một lần; dự báo mây lưu lại lần gần nhất |
| Nhắc giờ bus, phà, tàu, Shinkansen | `ReminderPlanner` → thông báo **Time Sensitive** lúc phải rời đi (đã trừ thời gian đi bộ ra ga); tối đa 64 thông báo nên chỉ xếp hai ngày tới và xếp lại khi mở app, khi đổi vị trí lớn, và bằng BGAppRefresh |
| Live Activity khi đi tàu | ActivityKit + Dynamic Island: ga kế, số ga còn lại, giờ tới, "chuẩn bị xuống" sau ga áp chót, Fuji bên trái hay phải theo dữ liệu địa hình, nút đi bộ tới điểm kế tiếp |
| Đi bộ tới điểm kế | mở Apple Maps chế độ đi bộ — chỉ dùng Apple Maps cho việc dẫn đường từng ngã rẽ, thứ MapLibre không làm |
| Tới gần quán thì hiện món nên gọi | `CLMonitor` (geofence chạy nền, xoay vòng 20 vòng tròn theo lịch) → thông báo kèm món, cách trả tiền, dự kiến chi → thẻ tại quán: món, câu để nói, ghi chi thật |
| Dòng tiền | `CashPlan`: tiền mặt cần cho các quán chỉ nhận tiền mặt trong hai ngày tới, so với tiền đang có |
| Widget | WidgetKit: điểm tiếp theo, thời gian còn lại trước lúc rời đi, ảnh nền của điểm đó (ảnh thu nhỏ trong App Group); màn hình khoá có bản chữ |
| Quét menu | VisionKit để ngắm, Vision `RecognizeTextRequest` để đọc, Translation dịch offline; dòng nào trùng tên món trong `menus-*.json` thì gắn "nên gọi" và giá — chỉ so chuỗi (`MenuMatcher`) |
| Báo thức xuống ga | AlarmKit, đặt lại khi giờ tới thay đổi theo vị trí thật |
| Tính lại lịch khi trễ | `PlanEngine` là bản Swift của `check-plan.mjs` (test khớp từng dòng), chạy từ vị trí và giờ hiện tại; `Replanner` tìm ít điểm nhất cần bỏ (ưu tiên điểm tuỳ chọn, không bao giờ bỏ chỗ đã đặt) để kịp chuyến kế: "Trễ 12 phút cho Ginza Line 16:15 — bỏ Umezono thì kịp" |
| Tốc độ đi bộ thật | CoreMotion: nhịp đi bộ từ `CMPedometer` lúc đang đi, cộng thời gian thật của các đoạn đã đi; `PaceModel` chỉnh mọi giờ đi bộ của lịch |
| Tìm Fuji bằng AR | ARKit (`gravityAndHeading`) + RealityKit đặt dấu theo hướng và góc cao của đỉnh (tính cả độ cong Trái Đất và khúc xạ); máy có LiDAR thì dựng lưới cảnh để nhà cửa gần che dấu đúng như che núi |
| Dự báo mây theo giờ | WeatherKit hourly ở đỉnh Fuji và ở chỗ đứng, ra khả năng thấy núi từng giờ |
| Nhật ký tự động | `CLVisit` ghi nơi đã ghé, khớp với điểm trong lịch; PhotoKit lấy ảnh theo giờ và nơi chụp; mỗi tối một trang: đã ghé, trễ bao nhiêu, bỏ chỗ nào, ghé thêm đâu, heatmap đường đã đi, số bước |
| Nghe rồi dịch | SpeechAnalyzer + SpeechTranscriber tiếng Nhật trên máy, Translation sang tiếng Việt; câu nào giống câu "bạn có thể nghe" trong sổ câu thì hiện luôn câu đáp |

## Pin và quyền riêng tư

Vị trí chỉ chạy liên tục khi app đang mở, khi đang đi tàu (Live Activity) hoặc khi đang chạy cho kịp một chuyến; còn lại chỉ có visit và geofence, do hệ thống đánh thức app. Mọi thứ nằm trên máy: không có máy chủ, không có tài khoản. Quyền được xin lúc cần tới (vị trí luôn bật cho geofence và nhật ký, ảnh cho nhật ký, micro cho nghe dịch, báo thức cho xuống ga).

## Kiểm tra trên máy thật

Phần lõi đã được test; phần giao diện và các framework hệ thống chỉ build được bằng Xcode. Những chỗ nên thử sớm: thông báo Time Sensitive (cần capability), geofence khi khoá màn hình, Live Activity cập nhật trong lúc đi tàu, gói ngôn ngữ Nhật–Việt của Translation và SpeechTranscriber (tải một lần khi có mạng), gói bản đồ offline (style lấy từ `https://jpy27.delphyra.tech/map/`, cần deploy site trước). "Chạy thử" trong Cài đặt dời đồng hồ của app tới bất kỳ lúc nào trong chuyến để tập dượt trước tháng 10/2027.
