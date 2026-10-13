// Curated places on the route. Facts gathered on 13/10/2026; prices are 2027 targets.
// Coordinates for restaurants, sights and hotels are completed (and images attached)
// from the research files in ./research via ./catalog.ts.

export type Kind = 'stay' | 'food' | 'sight' | 'shop' | 'station';
export type Area =
  | 'tokyo'
  | 'hakone'
  | 'tokaido'
  | 'ise'
  | 'toba'
  | 'shima'
  | 'kyoto'
  | 'nara'
  | 'osaka'
  | 'kawaguchiko';

/** plan = in the day plan; along = on the way, a few minutes; detour = worth a side trip; alt = alternative plan */
export type Role = 'plan' | 'along' | 'detour' | 'alt';

export interface PlaceBase {
  id: string;
  name: string;
  ja?: string;
  kind: Kind;
  area: Area;
  lat?: number;
  lng?: number;
  role?: Role;
  /** what to order / what it is, short */
  dish?: string;
  /** per person, Vietnamese style "¥1.400–1.700" */
  price?: string;
  note?: string;
  tips?: string;
  closed?: string;
  pay?: 'cash' | 'card' | 'mixed';
  tabelog?: string;
  official?: string;
  review?: string;
}

const tb = (path: string) => `https://tabelog.com/${path}/`;

export const PLACES: PlaceBase[] = [
  // ——— Stays ———
  {
    id: 'resol-akihabara',
    name: 'Hotel RESOL Akihabara',
    ja: 'ホテルリソル秋葉原',
    kind: 'stay',
    area: 'tokyo',
    lat: 35.696739,
    lng: 139.773928,
    note: 'Twin 17 m², hai giường 100 cm, bồn tắm riêng. JR Akihabara 3 phút, Iwamotochō 1 phút.',
    tips: 'Đừng nhầm với RESOL STAY Akihabara — cơ sở khác.',
    official: 'https://www.resol-hotel.jp/akihabara/rooms/',
    review: 'https://4travel.jp/dm_hotel-11753604',
  },
  {
    id: 'mizunoto',
    name: 'Hakone Kowakudani Onsen Mizunoto',
    ja: '箱根小涌谷温泉 水の音',
    kind: 'stay',
    area: 'hakone',
    lat: 35.239094,
    lng: 139.050262,
    note: 'Phòng 水花の庄 温泉露天風呂付洋室 35 m², bồn ngoài trời dùng nước onsen thật, hai bữa.',
    tips: 'Tên phòng phải có chữ 温泉. Shuttle từ ga Kowakudani 14–17h, mỗi 10–15 phút.',
    official: 'https://dormy-hotels.com/resort/hotels/mizunoto/rooms/',
    review: 'https://4travel.jp/travelogue/11981020',
  },
  {
    id: 'era-ise',
    name: 'Comfort Hotel ERA Ise',
    ja: 'コンフォートホテルERA伊勢',
    kind: 'stay',
    area: 'ise',
    lat: 34.489777,
    lng: 136.709564,
    note: 'Twin 22–24 m², hai giường 123 cm. Ga Iseshi 3 phút, Gekū 5–8 phút.',
    tips: 'Bữa sáng ¥1.800/người, 6:30–9:30. Đi bằng Kintetsu nhớ ra đúng lối phía Gekū.',
    official: 'https://www.choice-hotels.jp/era/ise/rooms/',
  },
  {
    id: 'cross-kyoto',
    name: 'Cross Hotel Kyoto',
    ja: 'クロスホテル京都',
    kind: 'stay',
    area: 'kyoto',
    lat: 35.008294,
    lng: 135.769995,
    note: 'Standard Twin 25 m², giường 100 × 200 cm, tắm và WC tách riêng. Sát Sanjō, Pontochō, sông Kamo.',
    tips: 'Standard không đồng nghĩa view sông.',
    official: 'https://cross-kyoto.orixhotelsandresorts.com/contents/standard/',
    review: 'https://4travel.jp/travelogue/11799311',
  },
  {
    id: 'resol-kyoto',
    name: 'Hotel RESOL Kyoto Kawaramachi Sanjō',
    ja: 'ホテルリソル京都 河原町三条',
    kind: 'stay',
    area: 'kyoto',
    lat: 35.00787,
    lng: 135.769669,
    role: 'alt',
    note: 'Phương án rẻ hơn: Twin 20 m², ¥16.000/đêm, cùng khu ăn tối.',
    official: 'https://www.resol-hotel.jp/kyoto-k/rooms/',
    review: 'https://4travel.jp/dm_hotel-11713366',
  },
  {
    id: 'forza-osaka',
    name: 'Hotel Forza Osaka Namba Dōtonbori',
    ja: 'ホテルフォルツァ大阪なんば道頓堀',
    kind: 'stay',
    area: 'osaka',
    lat: 34.668694,
    lng: 135.503571,
    note: 'Forza Double 18 m², giường 160 cm. Lobby tầng 3, ngay khu Dōtonbori.',
    tips: 'Nankai Namba (ra KIX) cách 12–15 phút đi bộ. Xin tầng cao, xa thang máy.',
    official: 'https://www.hotelforza.jp/osakanamba/rooms/',
    review: 'https://4travel.jp/dm_hotel-11872817/tips',
  },

  // ——— Food: Tokyo ———
  {
    id: 'tsumugi', name: 'Ramen Tsumugi', ja: 'らーめん紬麦', kind: 'food', area: 'tokyo',
    dish: 'Chūka soba nước trong', price: '¥1.400–1.700',
    note: 'Nước dùng thanh, sợi mì là điểm nhấn — bữa đầu nhẹ bụng sau chuyến bay.',
    closed: 'Chủ nhật, lễ, vài thứ Bảy', tabelog: tb('tokyo/A1310/A131001/13120606'),
  },
  {
    id: 'yamabe', name: 'Tonkatsu Yamabe Okachimachi', ja: 'とんかつ やまべ 御徒町店', kind: 'food', area: 'tokyo',
    dish: 'Set rosu hoặc hire katsu', price: '¥1.300–1.800',
    note: 'Bình dân, tiện đường, có cơm và bắp cải thêm thoải mái.',
    pay: 'cash', tips: 'Không nhận đặt chỗ.', tabelog: tb('tokyo/A1311/A131101/13138428'),
  },
  {
    id: 'kayaba', name: 'Kayaba Coffee', ja: 'カヤバ珈琲', kind: 'food', area: 'tokyo',
    dish: 'Sandwich trứng và cà phê', price: '¥1.800–2.200',
    note: 'Quán cà phê trong nhà gỗ năm 1938 ở Yanaka, tầng hai trải tatami.',
    closed: 'Thứ Hai', tabelog: tb('tokyo/A1311/A131104/13019585'),
  },
  {
    id: 'nezu-taiyaki', name: 'Nezu no Taiyaki', ja: '根津のたいやき', kind: 'food', area: 'tokyo',
    dish: 'Taiyaki vỏ mỏng nhân đậu đỏ', price: '¥250–300 một chiếc',
    note: 'Nướng từng chiếc một; thường hết hàng khoảng 12:30.',
    closed: 'Cuối tuần, lễ', pay: 'cash', tabelog: tb('tokyo/A1311/A131106/13003570'),
  },
  {
    id: 'owariya', name: 'Owariya Honten', ja: '尾張屋 本店', kind: 'food', area: 'tokyo',
    dish: 'Soba tempura tôm lớn', price: '¥2.200–2.800',
    note: 'Quán soba từ thời Edo cạnh Sensō-ji; có khách quay lại hơn chục lần.',
    closed: 'Thứ Sáu', pay: 'cash', tabelog: tb('tokyo/A1311/A131102/13003714'),
  },
  {
    id: 'umezono', name: 'Umezono Asakusa', ja: '梅園 浅草本店', kind: 'food', area: 'tokyo',
    dish: 'Anmitsu hoặc awa-zenzai', price: '¥1.100–1.500',
    note: 'Tiệm ngọt truyền thống từ 1854 — chỗ ngồi nghỉ chân sau Sensō-ji.',
    tabelog: tb('tokyo/A1311/A131102/13003670'),
  },
  {
    id: 'tamai', name: 'Nihonbashi Tamai Honten', ja: '日本橋 玉ゐ 本店', kind: 'food', area: 'tokyo',
    dish: 'Hộp anago 中箱, nửa hấp nửa nướng', price: '¥4.400–5.000',
    note: 'Lươn biển anago mềm, ăn kèm dashi chan vào cơm ở nửa sau.',
    tips: 'Đặt bàn tối, có phụ thu tối khoảng ¥400/người.', tabelog: tb('tokyo/A1302/A130202/13019904'),
  },
  {
    id: 'sushi-ten', name: 'SUSHI TOKYO TEN Shinjuku', ja: 'SUSHI TOKYO TEN、新宿', kind: 'food', area: 'tokyo',
    dish: "Chef's Choice Lunch ¥5.500", price: '¥5.500–6.000',
    note: 'Bữa sushi chính của chuyến đi, trong NEWoMan Shinjuku.',
    tips: 'Đặt qua ResReserve, chọn đúng course lunch ¥5.500 (có course khác giá ¥9.900).',
    tabelog: tb('tokyo/A1304/A130403/13193560'),
    official: 'https://res-reserve.com/en/restaurants/sushi-tokyo-ten-shinjuku',
  },
  {
    id: 'toritake', name: 'Toritake Sōhonten', ja: '鳥竹 総本店', kind: 'food', area: 'tokyo',
    dish: 'Yakitori xiên lớn, cơm gà', price: '¥4.000–5.000',
    note: 'Quán yakitori lâu đời ở Shibuya, xiên to — gọi ít trước rồi thêm.',
    tips: 'Có khói và thường đông.', tabelog: tb('tokyo/A1303/A130301/13001702'),
  },
  {
    id: 'numazuko', name: 'Numazukō Shinjuku', ja: '沼津港 新宿本店', kind: 'food', area: 'tokyo', role: 'alt',
    dish: 'Sushi băng chuyền gọi theo đĩa', price: '¥3.000–4.000',
    note: 'Thay TEN nếu muốn tự chọn món, không cần đặt trước.', tabelog: tb('tokyo/A1304/A130401/13004192'),
  },

  // ——— Food: Hakone, Shizuoka, Kawaguchiko ———
  {
    id: 'bakery-table', name: 'Bakery & Table Hakone', ja: 'ベーカリー&テーブル箱根', kind: 'food', area: 'hakone',
    dish: 'Bánh mì, brunch nhẹ cạnh hồ', price: '¥1.500–2.000',
    note: 'Ngay bến Moto-Hakone; tầng trên nhìn ra hồ Ashi.', tabelog: tb('kanagawa/A1410/A141001/14051671'),
  },
  {
    id: 'kaizan', name: 'Kaizan · Kashi no Ichi', ja: '海山 (河岸の市 まぐろ館)', kind: 'food', area: 'tokaido',
    dish: 'Cơm cá ngừ, set tôm chiên', price: '¥2.500–3.500',
    note: 'Chợ cá cảng Shimizu, cách ga 3 phút — hợp ngày chuyển vùng.', tabelog: tb('shizuoka/A2201/A220102/22024359'),
  },
  {
    id: 'kurasawaya', name: 'Kurasawaya, Yui', ja: 'くらさわや', kind: 'food', area: 'tokaido', role: 'alt',
    dish: 'Tôm sakura-ebi chiên', price: '¥3.000–4.000',
    note: 'Đặc sản Yui, cách ga 20 phút đi bộ — chỉ khi đổi hẳn bữa trưa ngày 5.',
    tabelog: tb('shizuoka/A2201/A220102/22000573'),
  },
  {
    id: 'hoto-fudo', name: 'Hōtō Fudō Kawaguchiko North', ja: 'ほうとう不動 河口湖北本店', kind: 'food', area: 'kawaguchiko', role: 'alt',
    dish: 'Hōtō — mì dẹt hầm rau bí', price: '¥1.500–2.000',
    note: 'Chỉ dùng cho phương án đi Kawaguchiko thay ngày 3.', pay: 'cash',
    tabelog: tb('yamanashi/A1903/A190303/19000116'),
  },

  // ——— Food: Ise, Toba, Shima ———
  {
    id: 'butasute', name: 'Butasute Gekū-mae', ja: '豚捨 外宮前店', kind: 'food', area: 'ise',
    dish: 'Gyūdon bò Ise', price: '¥1.800–2.500',
    note: 'Gần Gekū và khách sạn. Bò Ise khác bò Matsusaka.',
    closed: 'Thứ Tư, thứ Năm', tips: 'Tối đóng sớm, gọi món cuối khoảng 19h.', tabelog: tb('mie/A2403/A240301/24011334'),
  },
  {
    id: 'fukusuke', name: 'Fukusuke', ja: 'ふくすけ', kind: 'food', area: 'ise',
    dish: 'Ise udon', price: '¥900–1.400',
    note: 'Sợi rất mềm, nước sốt đậm — món địa phương, khác hẳn udon dai kiểu Sanuki.',
    tips: 'Cuối tuần nên ăn trước 12h.', tabelog: tb('mie/A2403/A240301/24000009'),
  },
  {
    id: 'akafuku', name: 'Akafuku Honten', ja: '赤福 本店', kind: 'food', area: 'ise',
    dish: 'Mochi đậu đỏ và trà', price: '¥400–600',
    note: 'Ăn tại chỗ bên sông Isuzu. Bánh tươi hạn ngắn, không mua mang về.',
    tabelog: tb('mie/A2403/A240301/24000008'),
  },
  {
    id: 'manpuku', name: 'Manpuku Shokudō', ja: 'まんぷく食堂', kind: 'food', area: 'ise',
    dish: 'Cơm gà karaage', price: '¥1.000–1.300',
    note: 'Quán cơm bình dân gần Ujiyamada, phần lớn, nhiều khách quen.',
    pay: 'cash', closed: 'Không cố định', tabelog: tb('mie/A2403/A240301/24000115'),
  },
  {
    id: 'sazanami-toba', name: 'Sazanami, Toba', ja: '漣', kind: 'food', area: 'toba',
    dish: 'Set tôm chiên xẻ bướm', price: '¥3.300–4.000',
    note: 'Tôm chiên to bản, gần ga Toba.',
    closed: 'Thứ Ba', tips: 'Hàng 20–30 phút. Set 大海老 giá khác hẳn set thường.', tabelog: tb('mie/A2403/A240302/24000445'),
  },
  {
    id: 'sazanami-shokudo', name: 'Sazanami Shokudō, Kashikojima', ja: 'さざ波食堂', kind: 'food', area: 'shima', role: 'alt',
    dish: 'Món hải sản theo menu', price: '¥2.000–3.000',
    note: 'Bên mặt nước vịnh Ago — cho phương án Kashikojima.', tabelog: tb('mie/A2403/A240303/24021124'),
  },

  // ——— Food: Kyoto ———
  {
    id: 'menami', name: 'Menami', ja: '御料理めなみ', kind: 'food', area: 'kyoto',
    dish: 'Obanzai, rau và món theo mùa', price: '¥8.000–10.000',
    note: 'Bữa nâng cấp ở Kyoto, gần khách sạn. Có otoshi khoảng ¥550.',
    closed: 'Thứ Tư', tips: 'Đặt bàn và báo giờ đến thực tế.', tabelog: tb('kyoto/A2601/A260201/26001266'),
  },
  {
    id: 'yorozuya', name: 'Gion Yorozuya', ja: '祇をん萬屋', kind: 'food', area: 'kyoto',
    dish: 'Udon hành Kujō và gừng', price: '¥1.800–2.400',
    note: 'Bát udon phủ kín hành xanh Kyoto, ngay Gion.', pay: 'cash', closed: 'Không cố định',
    tabelog: tb('kyoto/A2601/A260301/26000254'),
  },
  {
    id: 'komori', name: 'Gion Komori', ja: 'ぎをん小森', kind: 'food', area: 'kyoto',
    dish: 'Warabi mochi, parfait', price: '¥1.900–2.400',
    note: 'Trà quán trong nhà machiya bên kênh Shirakawa.', tabelog: tb('kyoto/A2601/A260301/26000280'),
  },
  {
    id: 'menzo', name: 'Yamamoto Menzō', ja: '山元麺蔵', kind: 'food', area: 'kyoto',
    dish: 'Udon, gà chiên, tempura ngưu bàng', price: '¥1.800–2.400',
    note: 'Udon nổi tiếng nhất Kyoto, gần Heian Jingū.', pay: 'cash',
    tips: 'Đặt chỗ mở lúc 0h giờ Nhật, ba ngày trước (22h tối 21/10 giờ Việt Nam).',
    tabelog: tb('kyoto/A2601/A260301/26002504'),
    official: 'https://www.tablecheck.com/ja/shops/yamamotomenzou/reserve',
  },
  {
    id: 'yoshimura', name: 'Arashiyama Yoshimura', ja: '嵐山よしむら', kind: 'food', area: 'kyoto',
    dish: 'Soba tempura', price: '¥2.800–3.500',
    note: 'Cửa sổ tầng hai nhìn thẳng cầu Togetsukyō.', tips: 'Không nhận đặt bàn.',
    tabelog: tb('kyoto/A2601/A260403/26000403'),
  },
  {
    id: 'torisei', name: 'Torisei Honten', ja: '鳥せい 本店', kind: 'food', area: 'kyoto',
    dish: 'Yakitori, một lượt sake Fushimi', price: '¥3.500–4.500',
    note: 'Quán của hãng sake Yamamoto Honke, trong khu kho rượu Fushimi.',
    closed: 'Thứ Hai', tabelog: tb('kyoto/A2601/A260601/26001213'),
  },
  {
    id: 'tonkatsu-yamamoto', name: 'Tonkatsu Yamamoto', ja: 'とんかつ 山本', kind: 'food', area: 'kyoto', role: 'alt',
    dish: 'Tonkatsu hire', price: '¥2.500–4.500',
    note: 'Phương án ngày mưa quanh khu City Hall.', pay: 'cash', closed: 'Chủ nhật',
    tabelog: tb('kyoto/A2601/A260202/26006075'),
  },

  // ——— Food: Nara, Osaka ———
  {
    id: 'awa', name: 'AWA Naramachi', ja: '粟 ならまち店', kind: 'food', area: 'nara',
    dish: 'Lunch 収穫祭御膳 ¥3.800', price: '¥4.000–4.500',
    note: 'Rau truyền thống Yamato, có phần thịt bò — hợp người ít ăn cá.',
    closed: 'Thứ Ba', tips: 'Bắt buộc đặt trước.', tabelog: tb('nara/A2901/A290101/29001643'),
  },
  {
    id: 'hosekibako', name: 'Kakigōri Hōsekibako', ja: 'かき氷 ほうせき箱', kind: 'food', area: 'nara',
    dish: 'Kakigōri đá bào', price: '¥1.800–2.200',
    note: 'Tiệm đá bào nổi tiếng nhất Nara.',
    tips: 'Mở đặt chỗ lúc 21h giờ Nhật hôm trước (19h Việt Nam).', tabelog: tb('nara/A2901/A290101/29011038'),
  },
  {
    id: 'fukutaro', name: 'Fukutarō Honten', ja: '福太郎 本店', kind: 'food', area: 'osaka',
    dish: 'Okonomiyaki, negiyaki', price: '¥2.500–3.500',
    note: 'Đi bộ về khách sạn được. Ngày thường chỉ mở chiều tối.', tabelog: tb('osaka/A2701/A270202/27002665'),
  },
  {
    id: 'horai-551', name: '551 Hōrai Honten', ja: '551蓬莱 本店', kind: 'food', area: 'osaka',
    dish: 'Butaman, dimsum, cơm mì', price: '¥1.500–2.200',
    note: 'Nhà hàng ngồi ở tầng trên, hàng mua mang về ở dưới — nhìn đúng hàng.',
    closed: 'Thứ Ba', tabelog: tb('osaka/A2701/A270202/27001312'),
  },
  {
    id: 'hanadako', name: 'Hanadako', ja: 'はなだこ', kind: 'food', area: 'osaka',
    dish: 'Takoyaki negi-mayo', price: '¥700–900',
    note: 'Chỉ ghé khi chọn cụm Umeda; đứng ăn, hàng khoảng 20 phút.', tabelog: tb('osaka/A2701/A270101/27012248'),
  },
  {
    id: 'tahei', name: 'Yakiniku Tahei', ja: '焼肉 多平', kind: 'food', area: 'osaka',
    dish: 'Harami, lưỡi bò, cơm', price: '¥6.000–8.000',
    note: 'Thịt ngon với cơm, quán nhiều khói.',
    pay: 'cash', closed: 'Thứ Tư', tips: 'Bàn hai người khó đặt, nên tới sớm.', tabelog: tb('osaka/A2701/A270202/27005087'),
  },

  // ——— Shops ———
  { id: 'maruzen-nihonbashi', name: 'Maruzen Nihonbashi', ja: '丸善 日本橋店', kind: 'shop', area: 'tokyo', lat: 35.682, lng: 139.7745, note: 'Văn phòng phẩm, sổ, bút.' },
  { id: 'nakagawa-masashichi-nara', name: 'Nakagawa Masashichi Nara', ja: '中川政七商店 奈良本店', kind: 'shop', area: 'nara', lat: 34.6793, lng: 135.8277, note: 'Khăn kaya fukin và đồ gia dụng thủ công.' },
  { id: 'ichizawa', name: 'Ichizawa Shinzaburō Hanpu', ja: '一澤信三郎帆布', kind: 'shop', area: 'kyoto', role: 'along', lat: 35.007759, lng: 135.777603, note: 'Túi canvas may tay; mẫu 148 khoảng ¥16.500. Nghỉ thứ Ba.' },
  { id: 'ippodo-kyoto', name: 'Ippodo Kyoto Honten', ja: '一保堂茶舗 京都本店', kind: 'shop', area: 'kyoto', lat: 35.014042, lng: 135.767441, note: 'Hōjicha 極上 100 g khoảng ¥756.' },
  { id: 'doguyasuji', name: 'Sennichimae Dōguyasuji', ja: '千日前道具屋筋商店街', kind: 'shop', area: 'osaka', lat: 34.663935, lng: 135.503517, note: 'Phố đồ bếp: bát, đũa, dao.' },
  { id: 'takashimaya-osaka', name: 'Takashimaya Osaka', ja: '高島屋 大阪店', kind: 'shop', area: 'osaka', lat: 34.664, lng: 135.5017, note: 'Tầng hầm thực phẩm: hộp bánh có hạn dùng dài.' },
  { id: 'loft-umeda', name: 'Loft Hanshin Umeda', ja: 'ロフト 阪神梅田本店', kind: 'shop', area: 'osaka', lat: 34.701165, lng: 135.498607, note: 'Tầng 6 Hanshin Umeda Honten.' },
  { id: 'hands-shinsaibashi', name: 'Hands Shinsaibashi', ja: 'ハンズ 心斎橋店', kind: 'shop', area: 'osaka', role: 'alt', lat: 34.674038, lng: 135.501312, note: 'Trong Shinsaibashi PARCO.' },
  { id: 'anello-shinsaibashi', name: 'anello Shinsaibashi', ja: 'anello 心斎橋筋店', kind: 'shop', area: 'osaka', role: 'alt', lat: 34.676441, lng: 135.501389, note: 'CROSS BOTTLE khoảng ¥6.490.' },

  // ——— Sights in the plan (details and images completed from research) ———
  { id: 'manseibashi', name: 'Manseibashi', ja: '万世橋', kind: 'sight', area: 'tokyo', lat: 35.697193, lng: 139.769898 },
  { id: 'kanda-myojin', name: 'Kanda Myōjin', ja: '神田明神', kind: 'sight', area: 'tokyo', lat: 35.70194, lng: 139.767739 },
  { id: 'yanaka-ginza', name: 'Yanaka', ja: '谷中', kind: 'sight', area: 'tokyo', lat: 35.7277, lng: 139.7666 },
  { id: 'nezu-shrine', name: 'Nezu Jinja', ja: '根津神社', kind: 'sight', area: 'tokyo', lat: 35.719973, lng: 139.760662 },
  { id: 'sensoji', name: 'Sensō-ji', ja: '浅草寺', kind: 'sight', area: 'tokyo', lat: 35.714765, lng: 139.796655 },
  { id: 'sumida-river', name: 'Sông Sumida', ja: '隅田川', kind: 'sight', area: 'tokyo', lat: 35.710107, lng: 139.798931 },
  { id: 'nihonbashi', name: 'Cầu Nihonbashi', ja: '日本橋', kind: 'sight', area: 'tokyo', lat: 35.684068, lng: 139.774503 },
  { id: 'meiji-jingu', name: 'Meiji Jingū', ja: '明治神宮', kind: 'sight', area: 'tokyo', lat: 35.676398, lng: 139.699326 },
  { id: 'omotesando', name: 'Omotesandō', ja: '表参道', kind: 'sight', area: 'tokyo', lat: 35.6672, lng: 139.7085 },
  { id: 'shibuya-crossing', name: 'Giao lộ Shibuya', ja: '渋谷スクランブル交差点', kind: 'sight', area: 'tokyo', lat: 35.659495, lng: 139.700498 },
  { id: 'onshi-hakone-park', name: 'Onshi Hakone Park', ja: '恩賜箱根公園', kind: 'sight', area: 'hakone', lat: 35.196324, lng: 139.025957 },
  { id: 'hakone-sekisho', name: 'Trạm gác Hakone Sekisho', ja: '箱根関所', kind: 'sight', area: 'hakone', role: 'along', lat: 35.192206, lng: 139.026353 },
  { id: 'cedar-avenue', name: 'Hàng tuyết tùng Tōkaidō cũ', ja: '旧街道杉並木', kind: 'sight', area: 'hakone', role: 'along', lat: 35.1975, lng: 139.0292 },
  { id: 'hakone-shrine', name: 'Hakone Jinja', ja: '箱根神社', kind: 'sight', area: 'hakone', role: 'along', lat: 35.203973, lng: 139.025583 },
  { id: 'owakudani', name: 'Ōwakudani', ja: '大涌谷', kind: 'sight', area: 'hakone', lat: 35.244418, lng: 139.019576 },
  { id: 'shimizu-port', name: 'Cảng Shimizu', ja: '清水港', kind: 'sight', area: 'tokaido', lat: 35.0205, lng: 138.4925 },
  { id: 'ise-geku', name: 'Ise Gekū', ja: '伊勢神宮 外宮', kind: 'sight', area: 'ise', lat: 34.487352, lng: 136.703698 },
  { id: 'sengukan', name: 'Sengūkan', ja: 'せんぐう館', kind: 'sight', area: 'ise', lat: 34.486873, lng: 136.706717 },
  { id: 'ise-naiku', name: 'Ise Naikū', ja: '伊勢神宮 内宮', kind: 'sight', area: 'ise', lat: 34.4549, lng: 136.7259 },
  { id: 'uji-bridge', name: 'Cầu Uji', ja: '宇治橋', kind: 'sight', area: 'ise', lat: 34.4589, lng: 136.7243 },
  { id: 'okage-yokocho', name: 'Okage Yokochō', ja: 'おかげ横丁', kind: 'sight', area: 'ise', lat: 34.462449, lng: 136.722912 },
  { id: 'ise-kawasaki', name: 'Phố kho Kawasaki', ja: '伊勢河崎', kind: 'sight', area: 'ise', lat: 34.496939, lng: 136.717526 },
  { id: 'toba-marine-terminal', name: 'Bến Toba Marine Terminal', ja: '鳥羽マリンターミナル', kind: 'sight', area: 'toba', lat: 34.490423, lng: 136.84494 },
  { id: 'toshijima-wagu', name: 'Làng chài Wagu, Tōshijima', ja: '答志島 和具', kind: 'sight', area: 'toba', lat: 34.5275, lng: 136.8858 },
  { id: 'toshijima-toshi', name: 'Làng chài Tōshi, Tōshijima', ja: '答志島 答志', kind: 'sight', area: 'toba', lat: 34.5243, lng: 136.8738 },
  { id: 'kiyomizudera', name: 'Kiyomizu-dera', ja: '清水寺', kind: 'sight', area: 'kyoto', lat: 34.994856, lng: 135.785046 },
  { id: 'sannenzaka', name: 'Sannenzaka', ja: '三年坂', kind: 'sight', area: 'kyoto', lat: 34.998239, lng: 135.77991 },
  { id: 'wargo-gion', name: 'wargo Kyoto Gion (thuê kimono)', ja: 'wargo 京都祇園店', kind: 'shop', area: 'kyoto', lat: 35.0039, lng: 135.7713 },
  { id: 'yasaka-shrine', name: 'Yasaka Jinja', ja: '八坂神社', kind: 'sight', area: 'kyoto', lat: 35.003603, lng: 135.778261 },
  { id: 'gion-shirakawa', name: 'Gion Shirakawa', ja: '祇園白川', kind: 'sight', area: 'kyoto', lat: 35.00505, lng: 135.77412 },
  { id: 'okazaki', name: 'Kênh Okazaki', ja: '岡崎疏水', kind: 'sight', area: 'kyoto', lat: 35.0137, lng: 135.7845 },
  { id: 'otagi-nenbutsuji', name: 'Otagi Nenbutsu-ji', ja: '愛宕念仏寺', kind: 'sight', area: 'kyoto', lat: 35.03116, lng: 135.661234 },
  { id: 'saga-toriimoto', name: 'Phố cổ Saga-Toriimoto', ja: '嵯峨鳥居本', kind: 'sight', area: 'kyoto', lat: 35.0262, lng: 135.6655 },
  { id: 'adashino', name: 'Adashino Nenbutsu-ji', ja: '化野念仏寺', kind: 'sight', area: 'kyoto', lat: 35.026916, lng: 135.664627 },
  { id: 'bamboo-grove', name: 'Rừng tre Sagano', ja: '竹林の小径', kind: 'sight', area: 'kyoto', lat: 35.0171, lng: 135.6718 },
  { id: 'togetsukyo', name: 'Cầu Togetsukyō', ja: '渡月橋', kind: 'sight', area: 'kyoto', lat: 35.012871, lng: 135.677762 },
  { id: 'fushimi-sake', name: 'Khu kho sake Fushimi', ja: '伏見 酒蔵', kind: 'sight', area: 'kyoto', lat: 34.9318, lng: 135.7619 },
  { id: 'fushimi-inari', name: 'Fushimi Inari Taisha', ja: '伏見稲荷大社', kind: 'sight', area: 'kyoto', lat: 34.9671, lng: 135.7727 },
  { id: 'todaiji', name: 'Tōdai-ji', ja: '東大寺', kind: 'sight', area: 'nara', lat: 34.689, lng: 135.8398 },
  { id: 'kasuga-taisha', name: 'Kasuga Taisha', ja: '春日大社', kind: 'sight', area: 'nara', lat: 34.681275, lng: 135.848432 },
  { id: 'naramachi', name: 'Naramachi', ja: 'ならまち', kind: 'sight', area: 'nara', lat: 34.6775, lng: 135.8298 },
  { id: 'hozenji', name: 'Hōzen-ji Yokochō', ja: '法善寺横丁', kind: 'sight', area: 'osaka', lat: 34.668, lng: 135.5026 },
  { id: 'nakazakicho', name: 'Nakazakichō', ja: '中崎町', kind: 'sight', area: 'osaka', lat: 34.7083, lng: 135.5048 },
  { id: 'kitano-tenmangu', name: 'Chợ phiên Kitano Tenmangū', ja: '北野天満宮', kind: 'sight', area: 'kyoto', role: 'alt', lat: 35.030475, lng: 135.734918 },
  { id: 'kashikojima', name: 'Kashikojima, vịnh Ago', ja: '賢島', kind: 'sight', area: 'shima', role: 'alt', lat: 34.3077, lng: 136.8205 },

  // ——— Stations and transfer points (MLIT N02 station positions) ———
  { id: 'haneda-t3', name: 'Sân bay Haneda T3', ja: '羽田空港第3ターミナル', kind: 'station', area: 'tokyo', lat: 35.54484, lng: 139.76807 },
  { id: 'st-shinagawa', name: 'Shinagawa', ja: '品川', kind: 'station', area: 'tokyo', lat: 35.62894, lng: 139.73942 },
  { id: 'st-akihabara', name: 'Akihabara', ja: '秋葉原', kind: 'station', area: 'tokyo', lat: 35.69808, lng: 139.77306 },
  { id: 'st-nippori', name: 'Nippori', ja: '日暮里', kind: 'station', area: 'tokyo', lat: 35.7276, lng: 139.77093 },
  { id: 'st-ueno-hirokoji', name: 'Ueno-hirokōji', ja: '上野広小路', kind: 'station', area: 'tokyo', lat: 35.70726, lng: 139.7729 },
  { id: 'st-asakusa', name: 'Asakusa', ja: '浅草', kind: 'station', area: 'tokyo', lat: 35.71072, lng: 139.79775 },
  { id: 'st-nihonbashi', name: 'Nihonbashi', ja: '日本橋', kind: 'station', area: 'tokyo', lat: 35.68195, lng: 139.77338 },
  { id: 'st-kanda', name: 'Kanda', ja: '神田', kind: 'station', area: 'tokyo', lat: 35.69414, lng: 139.77071 },
  { id: 'st-shinjuku', name: 'Shinjuku', ja: '新宿', kind: 'station', area: 'tokyo', lat: 35.68995, lng: 139.7006 },
  { id: 'st-shinjuku-odakyu', name: 'Shinjuku (Odakyu)', ja: '新宿', kind: 'station', area: 'tokyo', lat: 35.69136, lng: 139.69965 },
  { id: 'st-harajuku', name: 'Harajuku', ja: '原宿', kind: 'station', area: 'tokyo', lat: 35.67156, lng: 139.70275 },
  { id: 'st-shibuya', name: 'Shibuya', ja: '渋谷', kind: 'station', area: 'tokyo', lat: 35.65913, lng: 139.70277 },
  { id: 'st-hakone-yumoto', name: 'Hakone-Yumoto', ja: '箱根湯本', kind: 'station', area: 'hakone', lat: 35.23334, lng: 139.10361 },
  { id: 'moto-hakone-port', name: 'Bến Moto-Hakone', ja: '元箱根港', kind: 'station', area: 'hakone', lat: 35.200948, lng: 139.030531 },
  { id: 'togendai', name: 'Tōgendai', ja: '桃源台', kind: 'station', area: 'hakone', lat: 35.237912, lng: 138.995299 },
  { id: 'ubako', name: 'Ubako', ja: '姥子', kind: 'station', area: 'hakone', lat: 35.244487, lng: 139.006123 },
  { id: 'sounzan', name: 'Sōunzan', ja: '早雲山', kind: 'station', area: 'hakone', lat: 35.24631, lng: 139.03543 },
  { id: 'st-gora', name: 'Gōra', ja: '強羅', kind: 'station', area: 'hakone', lat: 35.25087, lng: 139.04826 },
  { id: 'st-kowakudani', name: 'Kowakudani', ja: '小涌谷', kind: 'station', area: 'hakone', lat: 35.2402, lng: 139.05356 },
  { id: 'st-odawara', name: 'Odawara', ja: '小田原', kind: 'station', area: 'tokaido', lat: 35.25717, lng: 139.15653 },
  { id: 'st-atami', name: 'Atami', ja: '熱海', kind: 'station', area: 'tokaido', lat: 35.10292, lng: 139.07658 },
  { id: 'st-numazu', name: 'Numazu', ja: '沼津', kind: 'station', area: 'tokaido', lat: 35.10302, lng: 138.86032 },
  { id: 'st-shimizu', name: 'Shimizu', ja: '清水', kind: 'station', area: 'tokaido', lat: 35.0242, lng: 138.48914 },
  { id: 'st-shizuoka', name: 'Shizuoka', ja: '静岡', kind: 'station', area: 'tokaido', lat: 34.97177, lng: 138.38892 },
  { id: 'st-nagoya', name: 'Nagoya', ja: '名古屋', kind: 'station', area: 'tokaido', lat: 35.17208, lng: 136.88033 },
  { id: 'st-kintetsu-nagoya', name: 'Kintetsu Nagoya', ja: '近鉄名古屋', kind: 'station', area: 'tokaido', lat: 35.16901, lng: 136.88374 },
  { id: 'st-iseshi', name: 'Iseshi', ja: '伊勢市', kind: 'station', area: 'ise', lat: 34.49214, lng: 136.70982 },
  { id: 'st-ujiyamada', name: 'Ujiyamada', ja: '宇治山田', kind: 'station', area: 'ise', lat: 34.48865, lng: 136.71404 },
  { id: 'gekumae-bus', name: 'Bến xe Gekū-mae', ja: '外宮前', kind: 'station', area: 'ise', lat: 34.48902, lng: 136.70496 },
  { id: 'naikumae-bus', name: 'Bến xe Naikū-mae', ja: '内宮前', kind: 'station', area: 'ise', lat: 34.45973, lng: 136.72295 },
  { id: 'st-toba', name: 'Toba', ja: '鳥羽', kind: 'station', area: 'toba', lat: 34.48736, lng: 136.84148 },
  { id: 'st-kintetsu-kyoto', name: 'Kyoto (Kintetsu)', ja: '京都', kind: 'station', area: 'kyoto', lat: 34.98459, lng: 135.75692 },
  { id: 'st-kyoto-karasuma', name: 'Kyoto (Karasuma Line)', ja: '京都', kind: 'station', area: 'kyoto', lat: 34.98692, lng: 135.75984 },
  { id: 'st-karasuma-oike', name: 'Karasuma Oike', ja: '烏丸御池', kind: 'station', area: 'kyoto', lat: 35.0109, lng: 135.75962 },
  { id: 'st-shiyakusho', name: 'Kyoto Shiyakusho-mae', ja: '京都市役所前', kind: 'station', area: 'kyoto', lat: 35.0109, lng: 135.7684 },
  { id: 'st-sanjo', name: 'Sanjō (Keihan)', ja: '三条', kind: 'station', area: 'kyoto', lat: 35.00902, lng: 135.77234 },
  { id: 'st-kiyomizu-gojo', name: 'Kiyomizu-Gojō', ja: '清水五条', kind: 'station', area: 'kyoto', lat: 34.99597, lng: 135.76845 },
  { id: 'st-gion-shijo', name: 'Gion-Shijō', ja: '祇園四条', kind: 'station', area: 'kyoto', lat: 35.00323, lng: 135.77196 },
  { id: 'st-higashiyama', name: 'Higashiyama', ja: '東山', kind: 'station', area: 'kyoto', lat: 35.00946, lng: 135.77976 },
  { id: 'st-kawaramachi', name: 'Kyoto-Kawaramachi', ja: '京都河原町', kind: 'station', area: 'kyoto', lat: 35.00378, lng: 135.76881 },
  { id: 'st-arashiyama', name: 'Arashiyama (Hankyu)', ja: '嵐山', kind: 'station', area: 'kyoto', lat: 35.01026, lng: 135.68174 },
  { id: 'otagi-bus', name: 'Bến xe Otagi-dera-mae', ja: '愛宕寺前', kind: 'station', area: 'kyoto', lat: 35.03085, lng: 135.66205 },
  { id: 'st-chushojima', name: 'Chūshojima', ja: '中書島', kind: 'station', area: 'kyoto', lat: 34.92661, lng: 135.75956 },
  { id: 'st-fushimi-inari', name: 'Fushimi-Inari (Keihan)', ja: '伏見稲荷', kind: 'station', area: 'kyoto', lat: 34.96844, lng: 135.76927 },
  { id: 'st-tambabashi', name: 'Tambabashi', ja: '丹波橋', kind: 'station', area: 'kyoto', lat: 34.93825, lng: 135.76539 },
  { id: 'st-kintetsu-tambabashi', name: 'Kintetsu-Tambabashi', ja: '近鉄丹波橋', kind: 'station', area: 'kyoto', lat: 34.93849, lng: 135.76642 },
  { id: 'st-kintetsu-nara', name: 'Kintetsu-Nara', ja: '近鉄奈良', kind: 'station', area: 'nara', lat: 34.68399, lng: 135.82714 },
  { id: 'st-osaka-namba', name: 'Ōsaka-Namba (Kintetsu)', ja: '大阪難波', kind: 'station', area: 'osaka', lat: 34.66705, lng: 135.49888 },
  { id: 'st-namba', name: 'Namba (Midōsuji)', ja: 'なんば', kind: 'station', area: 'osaka', lat: 34.66561, lng: 135.50027 },
  { id: 'st-umeda', name: 'Umeda', ja: '梅田', kind: 'station', area: 'osaka', lat: 34.70211, lng: 135.49803 },
  { id: 'st-nankai-namba', name: 'Nankai Namba', ja: '難波', kind: 'station', area: 'osaka', lat: 34.66347, lng: 135.50206 },
  { id: 'kix', name: 'Sân bay Kansai', ja: '関西空港', kind: 'station', area: 'osaka', lat: 34.43597, lng: 135.24349 },
];
