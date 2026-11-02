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
| **Bản đồ** | đang đi bộ, hoặc xem trước một ngày | dải ngày trượt ngang; lịch ngày trong bảng kéo, bản đồ chạy theo khi cuộn; chỗ rẽ sau mỗi điểm dừng |
| **Lịch trình** | xem trước, xem lại | 12 ngày theo nơi ngủ, ngày thay thế Kawaguchiko; Ăn uống, Chỗ ở, Trên tàu, Fuji, Đặt chỗ, Mua sắm, Ngân sách |
| **Sổ tay** | ở quầy, ở quán | 32 tình huống, câu riêng của chuyến, tên ga, nghe và dịch, quét menu, cẩm nang (vé, hành lý, hoàn thuế, onsen) |
| **Chi tiêu** | sau mỗi lần trả tiền | sổ chi theo ngày, ví tiền mặt và Suica, ngân sách so với thực chi, giỏ mua sắm |

Thanh phụ dưới tab bar (bottom accessory) chỉ hiện khi có chuyện đang diễn ra: chuyến tàu đang đi (ga kế, Fuji bên nào) hoặc đếm ngược tới lúc phải rời đi. Trước chuyến nó không hiện, vì chỉ lặp lại số ngày trang bìa đã có. Ẩn thanh phụ cần iOS 26.1 (`tabViewBottomAccessory(isEnabled:)`); trên 26.0 nó luôn hiện.

Glyph của tab: cổng torii cho Hôm nay (asset vẽ riêng, SF Symbols không có), `map`, một lộ trình nối hai điểm cho Lịch trình, あ trong bóng thoại cho Sổ tay (giống nút "Nói" của web), `wallet.bifold` cho Chi tiêu. Phương tiện: mũi Shinkansen cho Shinkansen, thuyền buồm cho tàu hải tặc hồ Ashi, đường hầm cho metro. Nút hệ thống (cài đặt, đóng, xoá) giữ glyph chuẩn của Apple.

## Bảng màu và trang bìa

Hinomaru: giấy trắng ấm (`Paper`, thẻ `Card`) và một màu đỏ cờ (`AccentColor`, #BC002D, sáng hơn khi tối nền). Đỏ chỉ dùng cho thứ cần thấy ngay: đếm ngược, giờ rời đi, trễ, điểm đã ghé (đóng như con dấu hanko). Sọc thứ hai là chàm (`Ai`); vàng (`Kin`) cho món đặc trưng, matcha cho đã đặt và tiến độ, hồng anh đào (`Sakura`) làm nền cho đỏ. Màu loại địa điểm lấy từ thuốc nhuộm truyền thống (hồng hồng cho ăn, chàm cho tham quan, tử đằng cho chỗ ở, đào cho mua sắm); mọi thứ di chuyển giữ màu của hãng tàu. Chữ Nhật làm hoạ tiết dùng Hiragino Mincho, con số dùng SF Rounded. Tất cả nằm trong `Design/Theme.swift` và các colorset.

Các ô biểu tượng của Sổ tay dùng màu truyền thống Nhật (日本の伝統色, `Iro` trong `Features/Talk/TalkShared.swift`): 朱 cho ăn uống, 藍 cho đi lại, 江戸紫 cho chỗ ở, 常磐 cho chùa và phố, 金茶 cho mua sắm, 紅 cho việc gấp, 紺青 cho Cẩm nang; đủ đậm để biểu tượng trắng đọc được ở cả nền sáng và tối.

Trước chuyến, tab Hôm nay là trang bìa (`Features/Today/TodayHome.swift`):
- **Ảnh bìa.** Mỗi ngày một ảnh chọn riêng cho bìa (`Resources/Cover`, danh sách trong `cover.json`): ảnh Commons cắt sẵn đúng 1290 × 1560, bằng số điểm ảnh của màn hình, không phóng to từ ảnh 800 px của site. Ngày nào chưa có ảnh bìa (ngày 12, hay ngày thay thế) thì dùng ảnh Commons sẵn có. Ảnh nằm trong app, chạy cả khi mất sóng; thẻ ngày và danh sách Lịch trình dùng chung bộ ảnh này. Ảnh tràn dưới thanh trạng thái, tự chuyển sau vài giây, trượt có parallax nhẹ, kéo xuống thì ảnh giãn ra, chạm ảnh thì mở địa điểm. Dưới tên địa điểm có tên tác giả và giấy phép (CC BY / BY-SA yêu cầu ghi), chạm vào thì mở trang ảnh trên Commons. Kéo trang xuống quá đầu thì ảnh phóng to theo, cùng với lớp sương dưới thanh trạng thái và lớp mờ ở chân ảnh (trước đây lớp sương đứng yên ở mép cũ của ảnh, cắt một vệt trắng ngang ảnh).
- **Đếm ngày.** Số ngày còn lại trên đĩa đỏ phẳng như lá cờ, cạnh "Tokyo → Osaka", ngày đi–về và số đêm. Đĩa đứng yên; chạm vào thì toả một vòng, rung nhẹ và đổi đơn vị (ngày, tuần, giờ).
- **Hành trình và từng ngày.** Năm thành phố là các ga trên một tuyến metro, mỗi đoạn dài theo số đêm, tên viết bằng kanji; ngay dưới là băng thẻ ngày (ảnh, số ngày, kanji, RouteSpark là đường đi thật của ngày). Tuyến metro là mục lục của băng thẻ nên không cần tiêu đề: chạm một ga thì băng thẻ cuộn tới ngày đầu của thành phố đó, cuộn băng thẻ thì ga tương ứng sáng lên. Chạm thẻ thì thẻ phóng to thành trang ngày.
- **Đặt chỗ.** Mỗi lượt đặt chỗ là một tấm vé: ngày mở bán trên cuống, đếm ngược trên thân; vé theo quy tắc thì ghi quy tắc.
- **Quán ăn.** Ảnh quán theo thứ tự ngày, kèm món.
- **Một câu tiếng Nhật.** Đổi theo ngày, có nút đổi câu và nút phát âm; chạm câu để hiện toàn màn hình.
- **Trước khi đi.** Checklist đánh dấu được, lưu trên máy.
- **Fuji.** Thẻ dẫn tới cẩm nang Fuji và camera Tìm Fuji.
- **Chạy thử một ngày trong chuyến.**

Tiêu đề mục chỉ đặt ở chỗ nội dung không tự nói được nó là gì; không có dòng phụ đề trang trí.

## Tab Bản đồ

Giống trang ngày của web (`daySync`), nhưng nằm trong tab Bản đồ (`Features/Map/MapTab.swift`):
- **Dải ngày.** Các ngày là những viên glass trượt ngang ở đầu bản đồ; ngày đang chọn màu đỏ và hiện tên. Ngày thay thế (Kawaguchiko) nằm cuối dải.
- **Bảng kéo.** Ba nấc. Nấc thấp nhất vẫn hiện tiến độ ngày: các điểm dừng xếp thành hàng, điểm đã ghé có dấu tích, điểm kế tiếp có vòng đỏ, điểm bản đồ đang xem được tô sáng; chạm một điểm thì bản đồ bay tới đó. Nội dung bảng được dựng một lần ở chiều cao lớn nhất, kéo chỉ đổi mép cắt nên không phải dựng lại. Kéo xuống quá đầu danh sách thì bảng hạ xuống nấc thấp nhất.
- **Bản đồ theo lịch.** Bảng giữa và bảng lớn chứa timeline của ngày (dùng chung đường ray với Lịch trình). Một đường đọc nằm ở một phần ba chiều cao danh sách; mục nào chạm đường đó thì bản đồ hiện mục ấy: chặng di chuyển thì vừa khung chặng và làm mờ các chặng khác, điểm dừng thì bay tới ở zoom 15,5. Khi bạn tự kéo hay zoom bản đồ, nó đứng yên 4 giây rồi mới bay tiếp. Đang ở đầu danh sách thì bản đồ hiện cả ngày.
- **Chỗ rẽ.** Ngay sau mỗi điểm dừng có một hàng viên nhỏ: các chỗ có thể rẽ, kèm số phút. Lấy từ dữ liệu: chỗ rẽ nghiên cứu cho ngày (`along`), quán ăn vặt gắn với điểm dừng (`near`), và các chỗ trong dữ liệu chưa ngày nào xếp lịch, cách điểm dừng một quãng đi bộ ngắn. Mỗi chỗ thuộc về điểm dừng gần nó nhất. Trên bản đồ chỉ có tên các chỗ rẽ của điểm đang đọc (hoặc của điểm mà chặng đang đọc dẫn tới). Chạm một chỗ (trên bản đồ hay ở hàng viên) thì vẽ đường tạm từ điểm dừng tới đó (đường rẽ đã nghiên cứu nếu có, không thì nét đứt thẳng) và hiện thẻ Đi bộ / Chi tiết / Ghi chi. Cuộn sang điểm khác thì đường tạm biến mất và các chỗ rẽ đổi theo điểm mới.
- **Sang ngày sau.** Cuối danh sách là thẻ ngày kế tiếp; kéo quá cuối (có rung nhẹ khi đủ xa) rồi thả, hoặc chạm thẻ, thì chuyển sang ngày sau.
- **Trong chuyến.** Mở đúng ngày hôm nay, ở điểm kế tiếp. Dòng đầu bảng là điểm kế tiếp, khoảng cách và nút Đi bộ, chỉ hiện khi bạn ở gần (trong vòng 30 km), nên ở nhà sẽ không thấy khoảng cách vô nghĩa.
- **Mượt khi kéo bảng.** Kéo bảng không làm bản đồ dựng lại khung: phần đệm của bản đồ cố định ở nấc giữa, và bản đồ chỉ bay sau khi bảng đã dừng (đang ở nấc lớn thì không bay). Các lớp tuyến, vùng sáng và ghim được tạo một lần; cuộn timeline chỉ thay dữ liệu hình của chúng (`MLNShapeSource.shape`), độ dày và độ mờ của từng chặng là thuộc tính của chặng. Đồng hồ của app chỉ ghi khi phút đổi, nên các màn hình không vẽ lại mỗi 20 giây; ảnh bìa trang chủ ngừng tự chuyển khi đã cuộn khỏi màn hình.

## Chi tiêu

Tab Chi tiêu (`Features/Spend/SpendTab.swift`) đọc từ trên xuống như một bản tóm tắt:
- **Vòng ngân sách.** Một vòng, mỗi khoản của ngân sách là một cung dài đúng tỉ lệ của nó (kiểu vòng của Screen Time và Dung lượng). Trước khi chi đồng nào, các cung tô đủ màu: đó là kế hoạch, giữa vòng là tổng dự tính và số đồng. Khi bắt đầu chi, cung thành rãnh mờ và tô dần theo tiền đã chi; giữa vòng là đã chi, trên tổng bao nhiêu và hôm nay bao nhiêu. Vòng tự vẽ một lần khi mở (trừ khi bật Giảm chuyển động). Dưới vòng là các viên của từng khoản: chạm một viên thì các cung khác mờ đi và giữa vòng đọc khoản đó (còn hay vượt bao nhiêu); chạm lại hoặc chạm giữa vòng để về tổng.
- **Hai ví.** Tiền mặt (chàm, chữ 円 chìm) và Suica (xanh, dấu không chạm) là hai tấm thẻ với số dư lớn; chạm thẻ thì sheet nạp hoặc rút mọc ra từ chính thẻ đó. Dưới hai thẻ là một dòng: mấy ngày tới cần bao nhiêu tiền mặt, nên rút thêm bao nhiêu ở ATM 7-Eleven, hoặc đã đủ.
- **Ngân sách và Mua sắm.** Hai ô dẫn sang trang chi tiết, kèm tổng ngân sách và số món đã mua.
- **Sổ chi.** Theo ngày, đầu mỗi ngày có tổng của ngày; vuốt để xoá.
- **Ghi chi.** Nút "+" trên thanh, sheet mọc ra từ viên kính của nút.

Mọi sheet nhập tiền (ghi chi, rút tiền, nạp Suica, "Đã mua") dùng bàn phím số vẽ ngay trong sheet (`SpendKeypad`, có phím 000 và rung nhẹ mỗi lần bấm), không bật bàn phím hệ thống. Bàn phím hệ thống trồi lên đúng lúc sheet đang phóng ra từ nút là thứ làm hiệu ứng bị khựng; giờ sheet phóng ra một mạch và đứng yên ở độ cao cuối.

## Ghi chi

Màn ghi chi (`Features/Spend/ExpenseEditor.swift`): số tiền lớn ở trên kèm số đồng, một hàng bảy biểu tượng khoản chi có màu (tên khoản hiện ở dưới), cách trả, rồi một thẻ gồm Ở đâu, Tính vào ngày nào và Ghi chú. Bàn phím số nằm dưới cùng, nhường chỗ khi đang gõ ghi chú. Khoản chi không còn gắn cứng vào điểm trong lịch:
- **Ngày.** Chọn được ngày mà khoản chi được tính vào (ví dụ ghi bù hoá đơn tối qua). Mặc định là hôm nay; trước chuyến thì là ngày có địa điểm đó. Sổ chi xếp khoản chi theo ngày này.
- **Ở đâu.** Chọn theo ngày đã chọn: quanh bạn (các chỗ trong dữ liệu cách bạn dưới 300 m), các điểm trong lịch của ngày, các chỗ rẽ của ngày (giống tab Bản đồ). Có ô tìm trong mọi chỗ đã lưu; chỗ không có trong dữ liệu thì gõ tên vào (lưu ở `Expense.placeName`).

## Hôm nay, trong chuyến

- **Đầu trang.** Kanji thành phố và một dải vạch, mỗi vạch là một điểm dừng: điểm đã ghé tô đỏ, điểm kế tiếp nhấp nháy.
- **Thẻ điểm tiếp theo.** Ảnh lớn, tên đặt trên ảnh, giờ rời đi to màu đỏ.
- **Timeline đường ray.** Dùng chung cho trang ngày. Theo cách web vẽ: mỗi chặng là một vạch dày đúng màu tuyến (đứt quãng trên nước và cáp treo, chấm chấm khi đi bộ); mỗi điểm dừng là một nút đánh số theo màu loại; ga là vòng rỗng.

## Liquid Glass

Theo [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) và [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/):

- **Kính cho điều khiển, không cho nội dung.** Tab bar, toolbar, nút nổi trên bản đồ và camera, nút hành động dùng Liquid Glass; nội dung nằm trên thẻ của nền grouped. Nút kính dùng `.glass`/`.glassProminent`, không vẽ kính lên nhãn; các mảnh kính đứng gần nhau nằm chung một `GlassEffectContainer`.
- **Nổi và co lại.** Tab bar thu nhỏ khi cuộn xuống và mở lại ngay khi cuộn lên. iOS 26 làm vậy sẵn; iOS 27 chỉ mở lại khi đã cuộn tới đầu trang, nên mỗi trang báo hướng cuộn (`tabBarFollowsScroll()`, có sẵn trong `screen()` và `paperList()`), và khi hướng là lên thì tab bar được đặt `.never` (mở ra), cuộn xuống lại thì trả về `.onScrollDown`. Thanh phụ đổi bố cục khi nằm gọn trong tab bar (`tabViewBottomAccessoryPlacement`). Nút micro của Nghe là `safeAreaBar`, không phải overlay: nội dung cuộn xuống dưới chúng và mờ dần ở đó.
- **Biến hình.** Nút "Theo dõi chuyến" thành "Đang theo dõi" tại chỗ (`glassEffectID`); trên camera Fuji, viên mây và viên địa hình mọc ra từ viên khoảng cách khi có dữ liệu; chip chọn ngày trên bản đồ là nút kính nên menu ngày mọc ra từ nó.
- **Trình bày theo ngữ cảnh.** Mọi sheet mọc ra từ đúng nút hay dòng đã mở nó và thu về đó khi đóng (`matchedTransitionSource` + `navigationTransition(.zoom)`, `Design/Presentation.swift`); thẻ câu nói toàn màn hình mọc ra từ dòng câu. Sheet mở từ sheet thì chồng lên (ghi món từ màn quét menu, quét menu từ thẻ quán), đóng là về chỗ cũ. Với nút trên thanh, nguồn biến hình là chính item của thanh (`SheetToolbarButton`, đặt `matchedTransitionSource` lên `ToolbarItem`), không phải nút bên trong: sheet mọc ra từ viên kính và thu về đúng viên kính đó, như app của Apple.
- **Toolbar.** Nghe và dịch ở góc trên bên trái, Cài đặt ở góc trên bên phải, cân hai bên thanh; nút ẩn đi thì bỏ hẳn item (iOS không có `ToolbarContent.hidden`) để thanh biến hình chứ không để lại ô trống. Trên trang bìa, thanh không có tiêu đề; khi ảnh bìa cuộn khỏi màn hình, dấu Hinomaru và chữ JP27 hiện vào giữa thanh. Nút đóng của sheet (`CloseButton`, chỉ có khi trang đang là sheet) luôn nằm ngoài cùng bên phải: trang đặt nó cuối cùng, sau một `ToolbarSpacer(.fixed)` nếu có nút riêng (Ghi chi, Bản đồ).
- **Ảnh đầu trang.** Trang địa điểm, ngày, chỗ ở và trang "Đang ở quán" mở bằng ảnh tràn lên tận mép trên, dưới cả thanh trạng thái, không có dải thanh nào (`DetailHero` và `detailPage(title:)` trong `Design/Components.swift`). Tên đặt ở chân ảnh trên một lớp mờ dần (vật liệu mờ được che bằng gradient, cộng một lớp tối nhẹ để chữ trắng đọc được). Khi ảnh cuộn khỏi, mép mềm của thanh hiện lại và tên nhỏ hiện vào giữa thanh. Trang không có ảnh thì giữ tiêu đề thường.
- **Mép cuộn mềm.** iOS 27 đổi mặc định của mép trên từ `.soft` (mờ dần) sang `.hard` (một dải mờ có vạch kẻ). App đặt lại `.soft` cho mọi mép, ở gốc tab bar và ở từng sheet (`progressiveEdges()`). Lệnh này chỉ được biên dịch bằng Xcode 27 (Swift 6.4): app build bằng SDK iOS 26 mà chạy trên iOS 27 chỉ được mép mềm dưới thanh trạng thái, trông tệ hơn dải mặc định. Trên iOS 26, `.soft` vốn là mặc định.

## Trang địa điểm kiểu album

Các điểm là một chuyến đi chơi chứ không phải chỗ ghé qua (mọi điểm tham quan, cửa hàng, chỗ ở, ga có ảnh; và những bữa đặc biệt: đã đặt bàn, từ ¥4.000 một người, hoặc Tabelog từ 3,75) mở bằng trang theo kiểu album của Apple Music (`PlanAmbientPage` trong `Features/Plan/PlaceView.swift`). Quán ăn vặt và bữa thường vẫn giữ trang thường.
- **Nền một màu lấy từ ảnh.** App đọc màu ở phần chân ảnh (dải 38 % dưới cùng, các hàng sát đáy nặng gấp đôi), chỉnh lại độ bão hoà và độ sáng thành màu nền cả trang (`AmbientTone`, `AmbientCanvas` trong `Services/Media.swift`). Ảnh đầu tiên quyết định trang sáng hay tối; vuốt sang ảnh khác thì chỉ đổi sắc, nền chuyển màu êm.
- **Ảnh tan vào nền.** Ảnh chiếm 60 % màn hình, dưới cả thanh trạng thái, đặt lên một bản mờ của chính nó: sắc nét ở trên, mờ dần chỗ đặt chữ, rồi tan hẳn vào màu nền ở dưới. Một lớp tối nhẹ ở mép trên giữ thanh trạng thái và nút của thanh đọc được trên nền trời trắng.
- **Chữ và nút theo nền.** Tên, tên tiếng Nhật, các dòng thông tin và hàng nút nằm giữa, chỗ ảnh tan: nút Bản đồ tròn, nút Đi bộ là viên đặc màu chữ, bên phải là câu nói ở quán, kịch bản câu ở chùa, hoặc ngày trong lịch. Trang đặt `colorScheme` theo nền (chữ tối trên nền nhạt, chữ trắng trên nền sẫm) nên kiểu chữ, thẻ và nút của hệ thống tự đổi theo; thẻ thành một lớp mờ của màu nền.

## Theo dõi trong chuyến

- **Vị trí quyết định điểm đang ở, không phải đồng hồ.** `Itinerary.cursor` tìm trong các điểm chưa ghé, từ sau điểm đã đánh dấu cuối cùng tới chuyến cố định kế tiếp: đang đứng trong vòng `Presence` của điểm nào thì lịch đứng ở điểm gần nhất trong số đó, dù đồng hồ của lịch đã qua. Ở xa mọi điểm thì đồng hồ quyết định như cũ. Điểm đã bỏ và điểm buổi sáng đã qua lâu không kéo lịch lùi lại.
- **Một định nghĩa cho "đang ở đây".** `Presence` (TripKit) là vòng của mỗi chỗ: 250 m cho điểm tham quan (sân chùa, công viên rộng), 220 m cho ga (lối ra rải cả một khối nhà), 150 m cho quán, cửa hàng, khách sạn (trong phố GPS lệch 50–100 m). Đánh dấu khi ghé, vị trí trong lịch, nhật ký và geofence đều dùng nó; giữa nhiều chỗ cùng chứa một điểm thì chỗ gần nhất thắng, không phải chỗ đứng trước trong lịch.
- **Một lần ghé đánh dấu một điểm, một lần.** Lần ghé được gán cho điểm gần nhất của hôm nay (kể cả điểm đã đánh dấu: ghé lại điểm đã đánh dấu thì không đánh dấu thêm gì), ngay lần báo đầu; lần báo thứ hai (lúc rời đi) chỉ điền giờ rời. Trước đây lần báo thứ hai tìm "điểm chưa đánh dấu đầu tiên trong 120 m" nên đánh dấu luôn hàng xóm: ngày 6 Fukusuke cách Okage Yokochō 24 m, Akafuku 51 m; ngày 2 Maruzen cách Tamai 87 m; ngày 8 Yorozuya cách Gion Tokuya 87 m.
- **Geofence.** Bỏ `CLMonitor`, dùng `CLCircularRegion` (`startMonitoring(for:)`, vẫn chạy được, Xcode chỉ báo deprecated), vòng theo `Presence`. Mỗi vòng chỉ báo một lần trong 20 phút. Đây cũng là bản sửa lỗi app crash liên tục sau khi chuyển quyền vị trí sang "Luôn luôn": trước đó `CLMonitor` được tạo ở mỗi lần mở app có quyền Luôn luôn.
- **Xin quyền Luôn luôn đúng lúc.** Trong chuyến, nếu chưa có quyền Luôn luôn thì trang Hôm nay có một thẻ giải thích và nút xin quyền (lần đầu xin ngay trong app, lần sau mở Cài đặt).
- **Tốc độ đi bộ.** Một đoạn đi bộ được đo từ lúc rời điểm trước (giờ rời của `CLVisit`, hoặc lúc xuống tàu) tới lúc tới điểm sau, không tính thời gian ngồi ở điểm trước. `PaceModel` bắt đầu từ một mức giả định nặng 45 phút, nên một đoạn chậm không quyết định cả chuyến.
- **Nhật ký.** iOS báo một lần dừng hai lần (lúc tới, rồi lúc tới kèm lúc đi); hai lần đó được gộp làm một (cùng giờ tới ±2 phút, cách nhau dưới 100 m). Mỗi lần dừng thuộc về điểm gần nó nhất; chỗ lịch quay lại hai lần (trả kimono ở wargo Gion) nhận các lần dừng theo thứ tự.
- **Tàu điện ngầm không phải chuyến cố định.** Mỗi tuyến có `every`, số phút giữa hai chuyến ban ngày (`src/data/lines.ts`). Tuyến từ 15 phút một chuyến trở xuống (metro, JR trong phố, Keihan, Hankyu, Hakone Tozan, cáp treo, xe buýt quanh hồ) là tuyến mềm: giờ ghi trong lịch chỉ là gợi ý, lịch sống tính chuyến kế tiếp cộng nửa khoảng cách giữa hai chuyến, không khuyên bỏ điểm để kịp nó, không có thông báo khẩn "Rời đi lúc…" và không có geofence ở ga. Chỉ chuyến có ghế đặt trước (Romancecar, Shinkansen, Shimakaze, Fuji Excursion) và tuyến thưa (thuyền hồ Ashi, phà Toba, xe buýt H, Kintetsu, JR Tōkaidō ngoài Tokyo) là cố định.
- **Live Activity** tự bật từ 20 phút trước giờ tàu tới 10 phút sau. Thông báo tới quán có nút **Đã tới**, đánh dấu điểm ngay trên màn hình khoá.
- **Báo thức dự phòng.** `WakePlanner` chọn chuyến: chỉ tàu ngồi lâu (từ 25 phút, tàu thường hoặc Shinkansen), không bao giờ thuyền, phà, xe buýt, cáp treo hay metro, vì báo thức AlarmKit kêu cả khi máy để im lặng. Báo thức đặt 4 phút trước giờ tới theo lịch, cho các chuyến của hôm nay và ngày mai (Romancecar 7:37 sáng ngày 4 có báo thức từ tối hôm trước). Chuyến ghi thời gian theo khoảng rộng hơn 10 phút ("55–80": tàu nhanh hay tàu chậm) không có báo thức theo lịch, vì 4 phút trước giờ tới sớm nhất là sớm nửa tiếng nếu đi tàu chậm; chuyến đó có báo thức theo tốc độ thật khi được theo dõi. Mỗi lần lịch đổi, các báo thức được đối chiếu lại: chuyến đã đi, ngày đã đổi sang phương án khác, báo thức đã tắt thì huỷ. Công tắc "Báo thức trước ga xuống" trong trang chuyến tắt thật (huỷ cả báo thức đã đặt) và được nhớ; mặc định bật cho các chuyến `WakePlanner` chọn, tắt cho phần còn lại.
- **Fuji.** Chỉ số tự tính từ mây không hiện như xác suất nữa: tiêu đề nói bằng lời ("nhiều khả năng thấy", "có thể thấy", "khó thấy").

## Sổ ghi chép và hai máy

- **Chỗ lưu cố định.** Sổ (SwiftData) nằm ở `Application Support/Trip.store` trong container của app, không còn trong App Group (tên App Group đổi theo cách ký, ký khác là mất sổ). Bản cũ trong App Group được chép sang một lần.
- **Không bao giờ âm thầm ghi vào bộ nhớ.** Nếu sổ không mở được, file cũ được để nguyên; từ đó app ghi vào một sổ phụ trên đĩa, báo ngay khi mở app và trong Cài đặt (kèm nút gửi file sổ cũ để cứu dữ liệu). Khi sổ chính mở lại được, sổ phụ được gộp vào rồi đổi tên cất đi, không xoá. Khi đổi model chỉ thêm thuộc tính optional hoặc có giá trị mặc định, trừ khi kèm `SchemaMigrationPlan`.
- **Hai máy, một sổ chi.** App không thể tự gửi hay tự nhận AirDrop (lúc nào cũng phải qua bảng chia sẻ và máy kia bấm nhận), nên hai máy nói chuyện thẳng với nhau: MultipeerConnectivity (cùng loại Wi‑Fi trực tiếp AirDrop dùng, không cần mạng) đồng bộ mỗi khi cả hai máy mở app ở gần nhau, và với máy có chip UWB, chạm đầu hai máy vào nhau (NearbyInteraction) thì đồng bộ ngay, kèm rung nhẹ (`Services/LedgerSync.swift`).
  - **Bật lần đầu.** Ở mỗi máy: Chi tiêu → ··· → Đồng bộ với máy kia → bật "Tự đồng bộ khi ở gần", đặt tên máy nếu muốn. Lúc này iOS mới hỏi quyền Mạng cục bộ (và Tương tác lân cận khi máy kia kết nối). Mở app ở cả hai máy gần nhau: mỗi máy hỏi "Ghép với <tên>?", bấm "Dùng chung", hoặc chạm hai máy vào nhau. Từ đó trở đi tự động; dưới hai ô Ngân sách và Mua sắm có một dòng "Đã đồng bộ với Lan lúc 21:04".
  - **Gộp hai chiều** (`LedgerMerge` trong TripKit, có test): mỗi khoản giữ bản sửa sau cùng (`updatedAt`), khoản xoá để lại "bia mộ" thắng mọi bản cũ hơn, hai máy ra cùng một sổ dù máy nào gộp trước. Khoản chi giờ sửa được (chạm vào dòng).
  - **Cùng một bữa ghi ở cả hai máy** (cùng chỗ, khoản, số tiền, ngày, cách nhau dưới 3 giờ) tự gộp làm một; khoản gần giống (cùng chỗ khác số tiền, hoặc không có chỗ mà cùng khoản và số tiền trong 30 phút) thì hỏi "Có thể ghi trùng"; khoản gộp nhầm khôi phục được ("Không phải trùng") và không bị hỏi lại.
  - Mỗi khoản nhớ máy đã ghi nó: ví tiền mặt và Suica của mỗi máy chỉ trừ khoản của máy đó, ngân sách tính cả hai. Đồng bộ chỉ chạy khi app đang mở ở cả hai máy.
  - **CSV vẫn còn**, làm dự phòng ("Dự phòng bằng file" trong menu), gộp theo cùng quy tắc; file CSV không mang theo khoản đã xoá.

## Fuji

Trang Fuji (`Features/Plan/FujiView.swift`, `Features/Fuji/FujiMap.swift`) mở bằng bản đồ 3D, như bản đồ của web:
- **Bản đồ địa hình thật.** MapLibre trên iOS không dựng được địa hình 3D, nên dùng bản đồ của Apple (`.hybrid(elevation: .realistic)`), nghiêng 58° như web: đỉnh núi, các chỗ ngắm tô tím khi thấy đỉnh và xám khi bị núi che, đường ngắm tới đỉnh nét liền khi thấy, nét đứt khi bị che. Chọn ngày (Cả vùng, Hakone ngày 4, Tōkaidō ngày 5, Kawaguchiko) thì camera bay ra sau các chỗ ngắm của ngày đó, nhìn về đỉnh.
- **Thứ tự trang.** Bản đồ ở đầu trang (chạm để mở toàn màn hình), kèm độ cao, số chỗ thấy đỉnh, khoảng cách từ bạn, nút "Bản đồ 3D" và "Tìm bằng camera"; rồi các chỗ ngắm của ngày đang chọn, mỗi chỗ một dòng ngắn (mũi tên chỉ về đỉnh, km, hướng, thấy bao nhiêu); rồi mây lúc này, khả năng tháng 10, phương án Kawaguchiko, ghi chú.
- **Bản đồ toàn màn hình** có la bàn, nút nghiêng, vị trí, thước tỉ lệ của hệ thống, và một dải thẻ chỗ ngắm đồng bộ với ghim.
- **Trang từng chỗ ngắm.** Đường ngắm trên địa hình; thấy bao nhiêu phần núi, núi to cỡ nào khi giơ thẳng tay, dùng ống kính nào của iPhone (cùng lời của web); khoảng cách, hướng, độ cao, khoảng cách tới sườn núi che; đường chân trời, ghi chú, ảnh, mây ở chỗ đó.
- **Không có mạng.** Bản đồ của Apple cần mạng; khi không có, một hình vẽ từ dữ liệu thay chỗ: đỉnh ở giữa, các chỗ ngắm đúng hướng và khoảng cách, vòng 10 km.
- **Ảnh.** Thẻ Fuji ở trang bìa là ảnh thật: Fuji trên vịnh Suruga nhìn từ đèo Satta, chỗ rẽ của ngày 5 (Alpsdake, CC BY-SA 4.0, Wikimedia Commons; `Resources/Cover/fuji-satta.jpg`), ghi nguồn ngay trên thẻ.

## Sáng, tối và Cài đặt

Mặc định app theo chế độ sáng, tối của iPhone; Cài đặt có thêm Sáng và Tối cố định (`Appearance` trong `Design/Theme.swift`). Lựa chọn được đặt lên cửa sổ (`overrideUserInterfaceStyle`) chứ không qua `preferredColorScheme`: quay về Tự động có hiệu lực ngay, và sheet, cảnh báo, bản đồ (đổi sang style tối) đều theo mà không cần truyền xuống. Mọi màu đều là colorset có biến thể tối; thẻ câu nói toàn màn hình cố ý giữ nền sáng để đưa cho người Nhật đọc.

Cài đặt xếp như Settings của iOS: đầu trang là chuyến đi (dấu Hinomaru, ngày đi–về, số đêm, các thành phố bằng kanji); rồi Giao diện với ba màn hình thu nhỏ (Tự động chia chéo sáng–tối); Quyền, mỗi dòng có ô biểu tượng màu; Chuyến đi (ngày thay thế, tốc độ đi bộ, chạy thử) và Dùng khi mất sóng, Nguồn: mỗi mục là một dòng hiện giá trị hiện tại, chạm vào mới mở trang riêng.

## Từng yêu cầu dùng gì

| Yêu cầu | Cách làm |
| --- | --- |
| Đánh dấu chỗ đã đi, món đã mua, ghi chi | SwiftData (`Checkmark`, `Purchase`, `Expense`, `Topup`, `ExpenseTombstone`), lưu ở `Application Support/Trip.store` của app; hai máy dùng chung sổ chi qua MultipeerConnectivity và NearbyInteraction, CSV làm dự phòng |
| Vị trí trong tương quan lịch | `Itinerary.project`: điểm đang ở theo vị trí (đang đứng trong vòng của điểm nào), không có thì theo giờ; điểm đang tới, khoảng cách và phút đi bộ theo tốc độ thật, chỗ rẽ của ngày xếp theo khoảng cách |
| Dùng khi mất sóng | toàn bộ dữ liệu và ảnh Commons nằm trong app; gói bản đồ offline MapLibre theo từng vùng; ảnh quán tải trước một lần; dự báo mây lưu lại lần gần nhất |
| Nhắc giờ bus, phà, tàu, Shinkansen | `ReminderPlanner` → thông báo **Time Sensitive** lúc phải rời đi (đã trừ thời gian đi bộ ra ga), chỉ cho chuyến cố định (ghế đặt trước hoặc tuyến thưa), không cho metro; tối đa 64 thông báo nên chỉ xếp hai ngày tới và xếp lại khi mở app, khi đổi vị trí lớn, và bằng BGAppRefresh |
| Live Activity khi đi tàu | ActivityKit + Dynamic Island: ga kế, số ga còn lại, giờ tới, "chuẩn bị xuống" sau ga áp chót, Fuji bên trái hay phải theo dữ liệu địa hình, nút đi bộ tới điểm kế tiếp |
| Đi bộ tới điểm kế | mở Apple Maps chế độ đi bộ — chỉ dùng Apple Maps cho việc dẫn đường từng ngã rẽ, thứ MapLibre không làm |
| Tới gần quán thì hiện món nên gọi | `CLCircularRegion` (geofence chạy nền, xoay vòng 20 vòng tròn theo lịch, 150 m cho quán, 220 m cho ga, mỗi vòng báo một lần trong 20 phút) → thông báo kèm món, cách trả tiền, dự kiến chi → thẻ tại quán: món, câu để nói, ghi chi thật |
| Dòng tiền | `CashPlan`: tiền mặt cần cho các quán chỉ nhận tiền mặt trong hai ngày tới, so với tiền đang có |
| Widget | WidgetKit: điểm tiếp theo, thời gian còn lại trước lúc rời đi, ảnh nền của điểm đó (ảnh thu nhỏ trong App Group); màn hình khoá có bản chữ |
| Quét menu | VisionKit để ngắm, Vision `RecognizeTextRequest` để đọc, Translation dịch offline; dòng nào trùng tên món trong `menus-*.json` thì gắn "nên gọi" và giá (`MenuMatcher`): so chữ viết, rồi so cách đọc romaji (CFStringTokenizer) để 天ぷら蕎麦 và 天ぷらそば là một món; dòng có 弁当 hay 持ち帰り thì không khớp với món ăn tại chỗ. "Ghi món này" ghi giá một phần |
| Báo thức xuống ga | AlarmKit, đặt lại khi giờ tới thay đổi theo vị trí thật; báo thức dự phòng theo giờ của lịch cho tàu ngồi lâu của hôm nay và ngày mai (`WakePlanner`), đối chiếu lại mỗi khi lịch đổi |
| Tính lại lịch khi trễ | `PlanEngine` là bản Swift của `check-plan.mjs` (test khớp từng dòng), chạy từ vị trí và giờ hiện tại; `Replanner` tìm ít điểm nhất cần bỏ (ưu tiên điểm tuỳ chọn, không bao giờ bỏ chỗ đã đặt) để kịp chuyến kế: "Trễ 12 phút cho bữa trưa đã đặt ở AWA 12:30 — bỏ Kasuga Taisha thì kịp". Chỉ tính cho chuyến và bàn không chờ ai; metro có chuyến kế sau vài phút nên không bao giờ là lý do bỏ điểm |
| Tốc độ đi bộ thật | CoreMotion: nhịp đi bộ từ `CMPedometer` lúc đang đi, cộng thời gian thật của các đoạn đã đi (tính từ lúc rời điểm trước); `PaceModel` bắt đầu từ một mức giả định rồi chỉnh mọi giờ đi bộ của lịch |
| Tìm Fuji bằng AR | ARKit (`gravityAndHeading`) + RealityKit đặt dấu theo hướng và góc cao của đỉnh (tính cả độ cong Trái Đất và khúc xạ); máy có LiDAR thì dựng lưới cảnh để nhà cửa gần che dấu đúng như che núi |
| Dự báo mây theo giờ | WeatherKit hourly ở đỉnh Fuji và ở chỗ đứng, ra khả năng thấy núi từng giờ, nói bằng lời chứ không bằng phần trăm; bản ký không có WeatherKit lấy từ Open-Meteo |
| Nhật ký tự động | `CLVisit` ghi nơi đã ghé (gộp lần báo tới và lần báo đi của cùng một lần dừng), khớp với điểm trong lịch; PhotoKit lấy ảnh theo giờ và nơi chụp; mỗi tối một trang: đã ghé, trễ bao nhiêu, bỏ chỗ nào, ghé thêm đâu, heatmap đường đã đi, số bước |
| Nghe rồi dịch | SpeechAnalyzer + SpeechTranscriber tiếng Nhật trên máy, Translation sang tiếng Việt; câu nào giống câu "bạn có thể nghe" trong sổ câu thì hiện luôn câu đáp |

## Pin và quyền riêng tư

Vị trí chỉ chạy liên tục khi app đang mở, khi đang đi tàu (Live Activity) hoặc khi đang chạy cho kịp một chuyến; còn lại chỉ có visit và geofence, do hệ thống đánh thức app. Mọi thứ nằm trên máy: không có máy chủ, không có tài khoản. Quyền được xin lúc cần tới (vị trí luôn bật cho geofence và nhật ký, ảnh cho nhật ký, micro cho nghe dịch, báo thức cho xuống ga).

## Kiểm tra trên máy thật

Phần lõi đã được test; phần giao diện và các framework hệ thống chỉ build được bằng Xcode. Những API mới của iOS 18–26 nên soát đầu tiên nếu Xcode báo lỗi: `AlarmManager.AlarmConfiguration` và `AlarmPresentation.Alert` (`Services/AlarmService.swift`), `CLCircularRegion` và `startMonitoring(for:)` (`Services/LocationService.swift`, chỉ cảnh báo deprecated), `ModelConfiguration(_:schema:url:)` (`Data/Records.swift`), `Transferable` với `DataRepresentation(exportedContentType:)` và `fileImporter` (`Features/Spend/SpendWallet.swift`, `SpendTab.swift`), `CFStringTokenizer` (`Packages/TripKit/.../MenuMatcher.swift`), `containerRelativeFrame` và đổi `colorScheme` trên trang album (`Features/Plan/PlaceView.swift`), `CIGaussianBlur` (`Services/Media.swift`), `SpeechTranscriber`/`SpeechAnalyzer` (`Features/Talk/TalkListener.swift`), `RecognizeTextRequest` và `NormalizedRect.toImageCoordinates` (`Features/Talk/MenuScanView.swift`), `BillboardComponent` (`Features/Fuji/FujiFinderView.swift`), `tabViewBottomAccessoryPlacement` (`Features/Today/NowAccessory.swift`), `Button(role: .close/.confirm)` không nhãn, `MLNSymbolStyleLayer.text` của MapLibre (`Design/TripMap.swift`), `matchedTransitionSource` trên nút toolbar và trên thanh phụ, `scrollEdgeEffectStyle` đặt ở gốc `TabView` có lan xuống từng tab và từng sheet không (`Design/Presentation.swift`), `safeAreaBar`, `ToolbarSpacer`, `ToolbarContent.hidden` và `backgroundExtensionEffect` trên `TabView` dạng trang (`Features/Plan/PlaceView.swift`), `MapCamera`, `.hybrid(elevation: .realistic)`, `MapPolyline` với `StrokeStyle` nét đứt, `MapCompass`/`MapPitchToggle`/`MapScaleView` theo `mapScope` (`Features/Fuji/FujiMap.swift`), `MCNearbyServiceAdvertiser`/`MCSession` và `NISession` với `NIDiscoveryToken` gửi qua `MCSession` (`Services/LedgerSync.swift`), `logoViewMargins` và `logoView.transform` của MapLibre (`Design/TripMap.swift`), `@Environment(TabBarScroll.self)` dạng optional và `onScrollGeometryChange` (`Design/Presentation.swift`), đổi qua lại `tabBarMinimizeBehavior` giữa `.never` và `.onScrollDown` có bung thanh tab ra ngay không (`App/JP27App.swift`), `URL.cachesDirectory` (`Services/OfflineMaps.swift`). Những chỗ nên thử sớm: thông báo Time Sensitive (cần capability), geofence khi khoá màn hình, Live Activity cập nhật trong lúc đi tàu, gói ngôn ngữ Nhật–Việt của Translation và SpeechTranscriber (tải một lần khi có mạng), gói bản đồ offline (style lấy từ `https://jpy27.delphyra.tech/map/`, cần deploy site trước; style ghim một phiên bản tile của OpenFreeMap, nên sau mỗi lần đổi phiên bản phải tải lại gói một lần). Mỗi lần mở app có mạng, app hỏi tile đầu tiên của phiên bản đã ghim; nếu nó trả 404 thì bản đồ chuyển sang phiên bản hiện tại của OpenFreeMap (TileJSON `https://tiles.openfreemap.org/planet`) cho tới khi phiên bản ghim trả lời lại. Không có mạng thì không hỏi gì và gói offline vẫn dùng như cũ. Khi đó nên đổi phiên bản ghim trong `src/lib/mapStyle.ts`, deploy lại và tải lại gói. Logo MapLibre trên bản đồ được thu nhỏ và nằm sát góc dưới bên phải; nút ghi nguồn (OpenStreetMap, OpenFreeMap) giữ ở góc dưới bên trái. "Chạy thử" trong Cài đặt dời đồng hồ của app tới bất kỳ lúc nào trong chuyến để tập dượt trước tháng 10/2027.
