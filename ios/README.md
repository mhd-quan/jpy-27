# JP27 cho iPhone

App iOS của chuyến đi, viết bằng SwiftUI cho iOS 26 (Liquid Glass), chỉnh cho màn hình iPhone Pro Max nhưng vẫn chạy trên iPhone nhỏ hơn. Toàn bộ nội dung của site nằm trong app và dùng được khi mất sóng; phần mới là theo dõi chuyến đi: đã ghé đâu, đã mua gì, đã chi bao nhiêu, đang ở đâu so với lịch.

## Chạy

```sh
brew install xcodegen      # một lần
cd ios && xcodegen         # tạo JP27.xcodeproj từ project.yml
open JP27.xcodeproj
```

Project là file sinh ra, không theo dõi thư mục: mỗi lần kéo code mới có thêm, bớt hay đổi tên file Swift, chạy lại `xcodegen` (hoặc lại lệnh `use-profile.py` đã dùng). Thiếu bước này Xcode báo "Cannot find … in scope" cho những gì nằm trong file mới.

Cần Xcode 26 trở lên; Xcode 27 để có mép cuộn mềm trên iOS 27 (xem Liquid Glass). Bản đồ MapLibre được Swift Package Manager tải về ở lần build đầu. Bundle ID, App Group, team, profile và entitlements là build setting trong `Config/Signing.xcconfig`; cấu hình riêng của máy bạn nằm ở `Config/Signing.local.xcconfig` (không commit).

**Simulator** không cần tài khoản: app tự ký để chạy cục bộ. WeatherKit từ chối bản này nên dự báo mây lấy từ Open-Meteo; camera, AR, geofence nền và báo thức chỉ thử được trên máy thật.

**Máy thật**, tuỳ thứ bạn có:

| Có gì | Làm gì | Thiếu so với bản đầy đủ |
| --- | --- | --- |
| Tài khoản Apple Developer | `JP27_TEAM = <team id>` trong `Config/Signing.local.xcconfig`, bật App Groups, WeatherKit, Time Sensitive cho App ID | không thiếu gì |
| `.p12` + `.mobileprovision` được cấp | nhấp đúp `.p12` (nhập mật khẩu của nó), rồi `python3 scripts/use-profile.py app.mobileprovision [widgets.mobileprovision]` | những gì profile không cấp; không có profile cho widget thì không có widget và Live Activity |
| Một Apple Account bất kỳ (miễn phí) | thêm vào Xcode → Settings → Accounts, tạo chứng chỉ Apple Development, rồi `python3 scripts/use-profile.py --personal-team` | WeatherKit, Time Sensitive; bản cài hết hạn sau 7 ngày |

`use-profile.py` đọc profile (team, bundle ID, App Group, WeatherKit, Time Sensitive, loại profile, máy được cài, hạn), chép nó vào chỗ Xcode tìm, kiểm tra chứng chỉ của nó có trong Keychain, viết `Config/Signing.local.xcconfig` cùng entitlements chỉ gồm những gì profile cấp (một entitlement profile không có là ký hỏng), rồi chạy `xcodegen`. Chỉ có profile cho app thì nó dùng `project.app-only.yml`: cùng project, bỏ widget extension. Profile ad hoc hoặc enterprise không cho gắn debugger: Edit Scheme → Run → Info → bỏ chọn "Debug executable". Thiếu WeatherKit thì dự báo mây lấy từ [Open-Meteo](https://open-meteo.com/) (miễn phí, không cần khoá); thiếu Time Sensitive thì nhắc giờ tàu là thông báo thường.

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
  project.app-only.yml        như trên, bỏ widget extension (ký bằng một profile)
  Config/Signing.xcconfig     bundle ID, App Group, team, profile, entitlements; *.local.* là của máy bạn
  scripts/use-profile.py      ký bằng .p12 + .mobileprovision được cấp, hoặc bằng Personal Team
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
    Design/                   bảng màu và dấu (Theme), thẻ, timeline đường ray, dòng địa điểm, bản đồ MapLibre
    Features/                 Today, Map, Plan, Talk, Spend, Journal, Fuji, Settings
  JP27Widgets/                widget điểm tiếp theo, Live Activity khi đi tàu
```

Ảnh Commons tự host của site (`public/img/commons`) và style bản đồ (`public/map`) được đưa thẳng vào app dưới dạng thư mục, không chép lại.

## Tab bar

| Tab | Dùng khi | Gồm nội dung site |
| --- | --- | --- |
| **Hôm nay** | mở điện thoại là thấy việc kế tiếp | điểm tiếp theo kèm ảnh, giờ rời đi, đang trễ bao nhiêu và nên bỏ gì; phần còn lại của ngày; trước chuyến: trang bìa (xem dưới) |
| **Bản đồ** | đang đi bộ | bản đồ ngày, chấm vị trí, khoảng cách tới điểm kế, chỗ rẽ gần đây |
| **Lịch trình** | xem trước, xem lại | 12 ngày theo nơi ngủ, ngày thay thế Kawaguchiko; Ăn uống, Chỗ ở, Trên tàu, Fuji, Đặt chỗ, Mua sắm, Ngân sách |
| **Sổ tay** | ở quầy, ở quán | 32 tình huống, câu riêng của chuyến, tên ga, nghe và dịch, quét menu, cẩm nang (vé, hành lý, hoàn thuế, onsen) |
| **Chi tiêu** | sau mỗi lần trả tiền | sổ chi theo ngày, ví tiền mặt và Suica, ngân sách so với thực chi, giỏ mua sắm |

Thanh phụ dưới tab bar (bottom accessory) luôn cho biết chuyện đang diễn ra: chuyến tàu đang đi (ga kế, Fuji bên nào) hoặc đếm ngược tới lúc phải rời đi.

Glyph của tab: cổng torii cho Hôm nay (asset vẽ riêng, SF Symbols không có), `map`, một lộ trình nối hai điểm cho Lịch trình, あ trong bóng thoại cho Sổ tay (giống nút "Nói" của web), `wallet.bifold` cho Chi tiêu. Phương tiện: mũi Shinkansen cho Shinkansen, thuyền buồm cho tàu hải tặc hồ Ashi, đường hầm cho metro. Nút hệ thống (cài đặt, đóng, xoá) giữ glyph chuẩn của Apple.

## Bảng màu và trang bìa

Hinomaru: giấy trắng ấm (`Paper`, thẻ `Card`) và một màu đỏ cờ (`AccentColor`, #BC002D, sáng hơn khi tối nền). Đỏ chỉ dùng cho thứ cần thấy ngay: đếm ngược, giờ rời đi, trễ, điểm đã ghé (đóng như con dấu hanko). Sọc thứ hai là chàm (`Ai`); vàng (`Kin`) cho món đặc trưng, matcha cho đã đặt và tiến độ, hồng anh đào (`Sakura`) làm nền cho đỏ. Màu loại địa điểm lấy từ thuốc nhuộm truyền thống (hồng hồng cho ăn, chàm cho tham quan, tử đằng cho chỗ ở, đào cho mua sắm); mọi thứ di chuyển giữ màu của hãng tàu. Chữ Nhật làm hoạ tiết dùng Hiragino Mincho, con số dùng SF Rounded. Tất cả nằm trong `Design/Theme.swift` và các colorset.

Trước chuyến, tab Hôm nay là trang bìa (`Features/Today/TodayHome.swift`):
- **Ảnh bìa.** Mỗi ngày một ảnh Commons có sẵn trong app (chạy cả khi mất sóng). Ảnh tràn dưới thanh trạng thái, tự chuyển sau vài giây, trượt có parallax, kéo xuống thì ảnh giãn ra, chạm ảnh thì mở địa điểm.
- **Đếm ngày.** Số ngày còn lại nằm trên đĩa mặt trời đỏ; đĩa nhô lên khi mở trang, có một vòng toả ra như mặt trời mọc.
- **Hành trình.** Năm thành phố là các ga trên một tuyến metro, mỗi đoạn dài theo số đêm, tên thành phố viết bằng kanji. Chạm một ga thì băng thẻ ngày cuộn tới ngày đầu của thành phố đó; ngược lại, cuộn băng thẻ thì ga tương ứng sáng lên.
- **Từng ngày.** Mỗi ngày một thẻ ảnh, có số ngày, kanji thành phố và một RouteSpark (đường đi thật của ngày, đúng màu từng tuyến). Chạm thẻ thì thẻ phóng to thành trang ngày (zoom transition).
- **Đặt chỗ.** Mỗi lượt đặt chỗ là một tấm vé có cuống ghi ngày mở bán và nhãn đếm ngược.
- **Những bữa đáng nhớ.** Ảnh quán theo thứ tự ngày, kèm món đặc trưng.
- **Một câu mỗi ngày.** Câu đổi theo ngày; chạm câu để hiện toàn màn hình, có nút phát âm.
- **Trước khi đi.** Checklist đánh dấu được, lưu trên máy.
- **Cả chuyến bằng con số.** Các con số đếm lên khi cuộn tới.
- **Fuji lúc hoàng hôn.** Thẻ dẫn tới cẩm nang Fuji và camera Tìm Fuji.
- **Chạy thử một ngày.**

Trong chuyến:
- **Đầu trang.** Kanji thành phố và một dải vạch, mỗi vạch là một điểm dừng: điểm đã ghé tô đỏ, điểm kế tiếp nhấp nháy.
- **Thẻ điểm tiếp theo.** Ảnh lớn, tên đặt trên ảnh, giờ rời đi to màu đỏ.
- **Timeline đường ray.** Dùng chung cho trang ngày. Theo cách web vẽ: mỗi chặng là một vạch dày đúng màu tuyến (đứt quãng trên nước và cáp treo, chấm chấm khi đi bộ); mỗi điểm dừng là một nút đánh số theo màu loại; ga là vòng rỗng.

## Liquid Glass

Theo [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) và [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/):

- **Kính cho điều khiển, không cho nội dung.** Tab bar, toolbar, nút nổi trên bản đồ và camera, nút hành động dùng Liquid Glass; nội dung nằm trên thẻ của nền grouped. Nút kính dùng `.glass`/`.glassProminent`, không vẽ kính lên nhãn; các mảnh kính đứng gần nhau nằm chung một `GlassEffectContainer`.
- **Nổi và co lại.** Tab bar thu nhỏ khi cuộn xuống, thanh phụ đổi bố cục khi nằm gọn trong tab bar (`tabViewBottomAccessoryPlacement`). Nút "+" của Chi tiêu và nút micro của Nghe là `safeAreaBar`, không phải overlay: nội dung cuộn xuống dưới chúng và mờ dần ở đó.
- **Biến hình.** Nút "Theo dõi chuyến" thành "Đang theo dõi" tại chỗ (`glassEffectID`); trên camera Fuji, viên mây và viên địa hình mọc ra từ viên khoảng cách khi có dữ liệu; chip chọn ngày trên bản đồ là nút kính nên menu ngày mọc ra từ nó.
- **Trình bày theo ngữ cảnh.** Mọi sheet mọc ra từ đúng nút hay dòng đã mở nó và thu về đó khi đóng (`matchedTransitionSource` + `navigationTransition(.zoom)`, `Design/Presentation.swift`); thẻ câu nói toàn màn hình mọc ra từ dòng câu. Sheet mở từ sheet thì chồng lên (ghi món từ màn quét menu, quét menu từ thẻ quán), đóng là về chỗ cũ.
- **Toolbar.** Nghe và Cài đặt là hai nhóm kính riêng (`ToolbarSpacer(.fixed)`); nút ẩn đi thì bỏ hẳn item (iOS không có `ToolbarContent.hidden`) để thanh biến hình chứ không để lại ô trống. Trên trang bìa, thanh không có tiêu đề; khi ảnh bìa cuộn khỏi màn hình, dấu Hinomaru và chữ JP27 hiện vào giữa thanh.
- **Ảnh đầu trang.** Ảnh của trang địa điểm kéo dài, soi gương và làm mờ, lên dưới thanh trên cùng (`backgroundExtensionEffect`).
- **Mép cuộn mềm.** iOS 27 đổi mặc định của mép trên từ `.soft` (mờ dần) sang `.hard` (một dải mờ có vạch kẻ). App đặt lại `.soft` cho mọi mép, ở gốc tab bar và ở từng sheet (`progressiveEdges()`). Lệnh này chỉ được biên dịch bằng Xcode 27 (Swift 6.4): app build bằng SDK iOS 26 mà chạy trên iOS 27 chỉ được mép mềm dưới thanh trạng thái, trông tệ hơn dải mặc định. Trên iOS 26, `.soft` vốn là mặc định.

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
| Dự báo mây theo giờ | WeatherKit hourly ở đỉnh Fuji và ở chỗ đứng, ra khả năng thấy núi từng giờ; bản ký không có WeatherKit lấy từ Open-Meteo |
| Nhật ký tự động | `CLVisit` ghi nơi đã ghé, khớp với điểm trong lịch; PhotoKit lấy ảnh theo giờ và nơi chụp; mỗi tối một trang: đã ghé, trễ bao nhiêu, bỏ chỗ nào, ghé thêm đâu, heatmap đường đã đi, số bước |
| Nghe rồi dịch | SpeechAnalyzer + SpeechTranscriber tiếng Nhật trên máy, Translation sang tiếng Việt; câu nào giống câu "bạn có thể nghe" trong sổ câu thì hiện luôn câu đáp |

## Pin và quyền riêng tư

Vị trí chỉ chạy liên tục khi app đang mở, khi đang đi tàu (Live Activity) hoặc khi đang chạy cho kịp một chuyến; còn lại chỉ có visit và geofence, do hệ thống đánh thức app. Mọi thứ nằm trên máy: không có máy chủ, không có tài khoản. Quyền được xin lúc cần tới (vị trí luôn bật cho geofence và nhật ký, ảnh cho nhật ký, micro cho nghe dịch, báo thức cho xuống ga).

## Kiểm tra trên máy thật

Phần lõi đã được test; phần giao diện và các framework hệ thống chỉ build được bằng Xcode. Những API mới của iOS 18–26 nên soát đầu tiên nếu Xcode báo lỗi: `AlarmManager.AlarmConfiguration` và `AlarmPresentation.Alert` (`Services/AlarmService.swift`), `CLMonitor` (`Services/LocationService.swift`), `SpeechTranscriber`/`SpeechAnalyzer` (`Features/Talk/TalkListener.swift`), `RecognizeTextRequest` và `NormalizedRect.toImageCoordinates` (`Features/Talk/MenuScanView.swift`), `BillboardComponent` (`Features/Fuji/FujiFinderView.swift`), `tabViewBottomAccessoryPlacement` (`Features/Today/NowAccessory.swift`), `Button(role: .close/.confirm)` không nhãn, `MLNSymbolStyleLayer.text` của MapLibre (`Design/TripMap.swift`), `matchedTransitionSource` trên nút toolbar và trên thanh phụ, `scrollEdgeEffectStyle` đặt ở gốc `TabView` có lan xuống từng tab và từng sheet không (`Design/Presentation.swift`), `safeAreaBar`, `ToolbarSpacer`, `ToolbarContent.hidden` và `backgroundExtensionEffect` trên `TabView` dạng trang (`Features/Plan/PlaceView.swift`). Những chỗ nên thử sớm: thông báo Time Sensitive (cần capability), geofence khi khoá màn hình, Live Activity cập nhật trong lúc đi tàu, gói ngôn ngữ Nhật–Việt của Translation và SpeechTranscriber (tải một lần khi có mạng), gói bản đồ offline (style lấy từ `https://jpy27.delphyra.tech/map/`, cần deploy site trước). "Chạy thử" trong Cài đặt dời đồng hồ của app tới bất kỳ lúc nào trong chuyến để tập dượt trước tháng 10/2027.
