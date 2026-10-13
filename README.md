# Nhật Bản 2027

Trang hành trình 12 ngày Tokyo → Osaka (18–29/10/2027) cho hai người: lịch từng ngày với bản đồ đi theo khi cuộn, nơi ăn có ảnh món, chỗ ở, Fuji, ngân sách và sổ tay. Astro + TypeScript + CSS thuần, MapLibre GL cho bản đồ.

## Chạy

```sh
npm install
npm run dev          # http://localhost:4321/.nb2027/
npm run build        # dist/, trang tĩnh
```

Site được build cho đường dẫn `delphyra.tech/.nb2027/`. Muốn phục vụ từ gốc tên miền: `BASE_PATH=/ npm run build`.

## Cấu trúc

```
src/
  data/
    days.ts          lịch 12 ngày: từng điểm dừng và từng chặng (tuyến, ga đi/đến, thời gian, ghi chú)
    places.ts        danh sách địa điểm đã chọn (nơi ở, quán, điểm tham quan, ga)
    lines.ts         các tuyến tàu/xe với màu chính thức của từng hãng
    trip.ts          ngân sách, giỏ mua sắm, vé, câu tiếng Nhật, lịch đặt chỗ
    catalog.ts       gộp places.ts với dữ liệu nghiên cứu
    *.gen.ts         sinh ra bởi scripts/, không sửa tay
  lib/               map.ts (MapLibre), mapStyle.ts (basemap riêng), trip.ts (view model), geo.ts
  components/        MapView, Gallery, PlaceSheet, Panorama, RouteSpark, AlongItem, Nav
  pages/             trang chủ, ngay/[n], fuji, an-uong, cho-o, ngan-sach, so-tay
scripts/             pipeline dữ liệu (bên dưới)
research/            dữ liệu nghiên cứu thô (JSON)
```

## Dữ liệu và pipeline

| Bước | Lệnh | Kết quả |
| --- | --- | --- |
| Gộp nghiên cứu | `node scripts/merge-research.mjs` | `src/data/research.gen.ts` |
| Tự host ảnh Commons | `node scripts/localize-images.mjs` | `public/img/commons/*.webp`, `research/commons-map.json` |
| Hình học tuyến | `node scripts/build-geo.mjs` | `src/data/geo.gen.ts` |
| Phân tích Fuji | `node scripts/build-fuji.mjs` | `src/data/fuji.gen.ts` |

Thứ tự khi sửa dữ liệu: merge → localize → merge → geo → fuji.

- **Đường sắt** đi theo ray thật: đường ngắn nhất trên mạng ray của đúng hãng/tuyến trong 国土数値情報 鉄道データ (MLIT N02-23), tải tự động về `.cache/`.
- **Đi bộ, xe buýt, shuttle** theo đường thật từ OSRM (routing.openstreetmap.de, dữ liệu OpenStreetMap); phản hồi được cache.
- **Phà, thuyền hồ Ashi** theo lộ trình vẽ tay trên mặt nước; **cáp treo** là các nhịp thẳng giữa ga.
- **Fuji**: đường ngắm từng điểm tới đỉnh trên dữ liệu độ cao Terrarium z12 (~30 m), có tính độ cong Trái Đất và khúc xạ; ra khoảng cách, hướng, phần núi lộ ra, kích thước biểu kiến, đường chân trời, và phía cửa sổ tàu thấy núi dọc Romancecar/Tōkaidō/Shinkansen.
- **Quán ăn**: thông tin và ảnh người dùng từ trang Tabelog tiếng Anh (`research/food-tabelog.json`), ảnh được lọc và chú thích tiếng Việt (`research/captions.json`). Ảnh hiển thị trực tiếp từ Tabelog, ghi tên người chụp và liên kết nguồn.
- **Khách sạn**: ảnh từ website chính thức, liên kết trực tiếp.
- **Điểm tham quan**: `research/sights-*.json`, ảnh Wikimedia Commons (tự host, ghi tác giả và giấy phép).
- **Fuji khí hậu**: báo cáo 富士山観測の記録 của thành phố Fuji (1991–2025) và thông báo tuyết đầu mùa của Đài khí tượng Kōfu.

Bản đồ nền: vector tiles OpenFreeMap (OpenMapTiles), style riêng ở `src/lib/mapStyle.ts`, có chế độ sáng/tối và đổ bóng địa hình (AWS Terrain Tiles).

Nghiên cứu ngày 13/10/2026. Giá phòng là mức nhắm khi đặt, chưa có đặt chỗ nào.
