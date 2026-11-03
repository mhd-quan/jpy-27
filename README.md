# JP27

Trang hành trình 12 ngày Tokyo → Osaka (18–29/10/2027) cho hai người, và app iPhone đi kèm (`ios/`, xem [ios/README.md](ios/README.md)): lịch từng ngày với bản đồ đi theo khi cuộn, món nên gọi và giá ở từng quán, ăn vặt dọc đường, chỗ ở và đường đi dạo quanh khách sạn, Fuji (kể cả một ngày Kawaguchiko thay ngày 3), từng chuyến tàu, kế hoạch mua sắm theo ngày, ngân sách và sổ tay có câu tiếng Nhật theo tình huống. Astro + TypeScript + CSS thuần, MapLibre GL cho bản đồ.

## Chạy

```sh
npm install
npm run dev          # http://localhost:4321/
npm run build        # dist/, trang tĩnh
```

Site chạy ở gốc tên miền `jpy27.delphyra.tech`, triển khai bằng Cloudflare Workers (chỉ phục vụ file tĩnh). `wrangler.jsonc` khai báo lệnh build và thư mục `dist/`; `npx wrangler deploy` sẽ build rồi đẩy lên. Tên miền gắn vào Worker trong Cloudflare: Settings → Domains & Routes → Add → Custom domain.

## Cấu trúc

```
src/
  data/
    days.ts          lịch 12 ngày và ngày thay thế (ALT_DAYS: Kawaguchiko): từng điểm dừng và từng chặng
    places.ts        danh sách địa điểm đã chọn (nơi ở, quán, điểm tham quan, ga)
    lines.ts         các tuyến tàu/xe với màu chính thức của từng hãng
    trip.ts          ngân sách, giỏ mua sắm, vé, câu tiếng Nhật, lịch đặt chỗ
    catalog.ts       gộp places.ts với dữ liệu nghiên cứu
    notes.ts         chữ của Sổ tay (vé, hành lý, onsen…), nhóm tình huống, chỗ đã đặt bàn — dùng chung site và app
    *.gen.ts         sinh ra bởi scripts/, không sửa tay
  lib/               map.ts (MapLibre), mapStyle.ts (basemap riêng), trip.ts (view model), geo.ts
  components/        MapView, Gallery, PlaceSheet, Panorama, RouteSpark, AlongItem, RideStrip, Nav (wordmark JP27: Anybody 150% / 900, vẽ thành đường nét)
  scripts/           daySync.ts và reading.ts (bản đồ theo đoạn đang đọc, tính cả bản đồ dính trên đầu khi dùng điện thoại)
  pages/             trang chủ, ngay/[n], fuji, fuji/kawaguchiko, tren-tau, an-uong, cho-o, mua-sam, ngan-sach, so-tay
scripts/             pipeline dữ liệu (bên dưới)
research/            dữ liệu nghiên cứu thô (JSON)
ios/                 app iPhone (SwiftUI, iOS 26): lõi TripKit, app, widget
```

## Dữ liệu và pipeline

| Bước | Lệnh | Kết quả |
| --- | --- | --- |
| Gộp nghiên cứu | `node scripts/merge-research.mjs` | `src/data/research.gen.ts` |
| Tự host ảnh Commons | `node scripts/localize-images.mjs` | `public/img/commons/*.webp`, `research/commons-map.json` |
| Hình học tuyến | `node scripts/build-geo.mjs` | `src/data/geo.gen.ts` |
| Đường rẽ tới các điểm gợi ý | `node scripts/build-detours.mjs` | `src/data/detours.gen.ts` |
| Phân tích Fuji | `node scripts/build-fuji.mjs` | `src/data/fuji.gen.ts` |
| Ga dọc từng chuyến tàu | `node scripts/build-rides.mjs` | `src/data/rides.gen.ts` |
| Đi dạo quanh khách sạn, Fuji từ ryokan | `node scripts/build-stays.mjs` | `src/data/stays.gen.ts`, `public/img/fuji-viewshed-mizunoto.png` |
| Đường đi bộ của các khung mua sắm | `node scripts/build-shopping.mjs` | `src/data/shopping.gen.ts` |
| Thời gian đi bộ có tính dốc | `node scripts/build-walk.mjs` | `src/data/walk.gen.ts` |
| Kiểm tra lịch có kịp giờ | `npm run check:plan` | báo những điểm dừng hoặc chuyến tàu lên lịch sớm hơn lúc tới được; có điểm trễ thì thoát với mã 1 |
| Dữ liệu cho app iPhone | `npm run ios:data` | `ios/JP27/Resources/Trip/*.json`, `ios/Shared/schedule.json`, `public/map/jp27-*.json` |

Thứ tự khi sửa dữ liệu: merge → localize → merge → geo → detours → rides → fuji → stays → shopping → walk → check:plan → ios:data. `npm run geo` chạy liền geo, detours và walk.

- **Đi bộ**: độ cao lấy mỗi 15 m trên Terrarium z14 (~10 m), làm mượt 105 m và bỏ dao động dưới 4 m (dữ liệu bề mặt thấy cả nhà và cầu vượt); tốc độ theo hàm Tobler nhân 0,78 — khoảng 3,9 km/h trên đường phẳng, chậm hơn khi leo hoặc xuống dốc gắt. Cộng 1 phút định hướng mỗi đoạn và thời gian từ sân ga ra đường ở các ga lớn (Shinjuku, Nagoya, Kyoto, Namba… 3–5 phút; đổi giữa hai ga tính một lần). Thời gian này hiện ở từng đoạn đi bộ, đường rẽ, đường dạo quanh khách sạn và khung mua sắm.
- **Kiểm tra lịch**: chạy đồng hồ qua từng ngày — đi bộ theo mô hình trên, tàu xe theo cận dưới của thời gian ghi trong lịch cộng thời gian chờ khi không có giờ chạy cụ thể, mỗi điểm dừng có thời gian ở tối thiểu theo loại (bữa chính 45–60 phút, đền chùa lớn 40–50, chỗ chụp ảnh 10–20). Một chặng đi bộ ghé qua nhiều điểm được tính dần theo từng điểm, và đoạn còn lại sau điểm cuối được cộng trước chuyến tàu kế tiếp. Trễ quá 1 phút với giờ tàu hay quá 2 phút với giờ một điểm dừng là trễ (`!`, script thoát với mã 1, CI dừng); một điểm dừng trễ không quá 2 phút in `≈`, còn dư dưới 3 phút in `~` (gửi đồ và nhận phòng không in hai dòng này). Thời gian ở, thời gian chờ và các ngưỡng này nằm ở `scripts/plan-rules.mjs`, dùng chung với app iPhone — app chạy cùng đồng hồ này bằng Swift để tính lại lịch khi đang trễ. Test của script: `node --test 'scripts/*.test.mjs'`.
- **Tính lại từ đầu**: geometry của chặng đã có trong `geo.gen.ts` được `build-geo.mjs` giữ lại (id chặng băm theo tuyến, hai đầu và điểm đi qua); `--fresh` cho `build-geo`, `build-detours`, `build-rides`, `build-stays` và `build-shopping` để tính lại hết. `check-plan.mjs` không nhận tham số.

`merge-research` ghi thêm `src/data/enrich.gen.ts` (câu tiếng Nhật, chỗ ở, Fuji, mua sắm, tàu) từ các file nghiên cứu:

| File | Nội dung |
| --- | --- |
| `research/menus-*.json` | món nên gọi và giá từng quán (tách ra phần `menu` của quán) |
| `research/snacks-*.json` | quán ăn vặt, đồ ngọt, chợ gắn với từng ngày; nguồn Tabelog hoặc mạng xã hội |
| `research/fuji-spots.json` | chỗ hay được đăng quanh Fuji; giờ tàu, xe cho ngày Kawaguchiko |
| `research/stays-around.json` | khu quanh khách sạn, đường đi dạo, chỗ cần thiết gần đó, Fuji quanh ryokan |
| `research/shopping-items.json`, `shopping-stores.json` | danh mục món có giá; cửa hàng và khung giờ mua theo ngày (chỉnh của người lập kế hoạch nằm ở `src/lib/shopping.ts`) |
| `research/shopping-cards.json` | thẻ từng cửa hàng: cửa hàng là gì (thành ghi chú của địa điểm), nên tìm gì, mẹo, ảnh Commons |
| `research/fuji-photos.json` | ảnh phong cảnh của từng chỗ ngắm Fuji (cho thẻ chỗ ngắm; thành ảnh của địa điểm khi địa điểm chưa có ảnh) |
| `research/trains-*.json` | cảnh hai bên, đổi tàu, lúc chuẩn bị xuống cho từng chuyến |
| `research/phrases.json` | sổ câu theo tình huống, có romaji |

- **Lọc chữ nghiên cứu** (`scripts/tidy.mjs`, chạy khi gộp): bỏ phần ghi nguồn trong câu ("(Wikipedia ja)", "theo Tabelog", "mẫu Yahoo 2/11/2026") và câu rào đón ("chưa kiểm chứng", "cần kiểm tra lại"), giữ hệ quả ("chưa rõ X, nên Y" còn "nên Y"). Nguồn hiện thành thẻ một chữ (Tabelog, Wikipedia, Web…) bấm vào là mở trang gốc (`src/lib/sources.ts`). `stays.gen.ts` cần mạng để dựng lại nên được lọc thêm lúc hiển thị.
- **Đường sắt** đi theo ray thật: đường ngắn nhất trên mạng ray của đúng hãng/tuyến trong 国土数値情報 鉄道データ (MLIT N02-23), tải tự động về `.cache/`.
- **Đi bộ, xe buýt, shuttle** theo đường thật từ OSRM (routing.openstreetmap.de, dữ liệu OpenStreetMap); phản hồi được cache.
- **Điểm gợi ý dọc đường** (mục "Trên đường đi"): chỉ tính từ những chỗ đang đi bộ (điểm dừng, khách sạn, các đoạn đi bộ), không tính đoạn ngồi tàu. Đường rẽ vào lấy từ OSRM đi bộ, hoặc đường ô tô khi đi bộ quá 2,5 km. Điểm ở xa thì xuất phát từ ga gần nhất trên chính tuyến tàu của ngày đó. Bỏ những chỗ phải đi xe quá 25 phút.
- **Phà, thuyền hồ Ashi** theo lộ trình vẽ tay trên mặt nước; **cáp treo** là các nhịp thẳng giữa ga.
- **Fuji**: đường ngắm từng điểm tới đỉnh trên dữ liệu độ cao Terrarium z12 (~30 m), có tính độ cong Trái Đất và khúc xạ; ra khoảng cách, hướng, phần núi lộ ra, kích thước biểu kiến, đường chân trời, và phía cửa sổ tàu thấy núi dọc Romancecar/Tōkaidō/Shinkansen/Fuji Excursion. Cầu được tính ở mặt cầu (cao hơn đáy thung lũng), cáp treo ở ga trên đỉnh. Quanh ryokan Mizunoto có thêm đường ngắm dọc từng tuyến đi dạo và bản đồ vùng nhìn thấy đỉnh (`scripts/fuji-tools.mjs` dùng chung).
- **Tàu**: ga dọc từng chặng lấy từ dữ liệu ga 国土数値情報 chiếu lên đường ray của chặng; tên tiếng Anh từ Wikidata (cache `.cache/wikidata-stations.json`). Tàu chạy suốt qua hai hãng (Fuji Excursion: JR Chūō → Fujikyu ở Ōtsuki) đi qua điểm `via`.
- **Quán ăn**: thông tin và ảnh người dùng từ trang Tabelog tiếng Anh (`research/food-tabelog.json`), ảnh được lọc và chú thích tiếng Việt (`research/captions.json`). Ảnh hiển thị trực tiếp từ Tabelog, ghi tên người chụp và liên kết nguồn.
- **Khách sạn**: ảnh từ website chính thức, liên kết trực tiếp.
- **Điểm tham quan**: `research/sights-*.json`, ảnh Wikimedia Commons (tự host, ghi tác giả và giấy phép).
- **Fuji khí hậu**: báo cáo 富士山観測の記録 của thành phố Fuji (1991–2025) và thông báo tuyết đầu mùa của Đài khí tượng Kōfu.

Bản đồ nền: vector tiles OpenFreeMap (OpenMapTiles), style riêng ở `src/lib/mapStyle.ts`, có chế độ sáng/tối và đổ bóng địa hình (AWS Terrain Tiles).

Nghiên cứu ngày 13/10/2026, bổ sung 31/10–1/11/2026 (món, ăn vặt, tàu, mua sắm, Fuji, chỗ ở). Giờ tàu là bảng giờ 2026; bảng giờ tháng 10/2027 cần kiểm lại. Giá phòng là mức nhắm khi đặt, chưa có đặt chỗ nào.
