import type { LineKey } from './lines.ts';

/** [lat, lng] */
export type LatLng = [number, number];

export interface Leg {
  id: string;
  line: LineKey;
  from: string;
  to: string;
  /** waypoints for routed legs (walk, bus, shuttle): place ids or [lat, lng] */
  via?: (string | LatLng)[];
  /** explicit path for water and aerial legs, [lat, lng] */
  path?: LatLng[];
  min?: string;
  note?: string;
}

export interface Stop {
  type: 'stop';
  at?: string;
  place?: string;
  title: string;
  text?: string;
  /** yen for two people */
  cost?: number;
  optional?: boolean;
}

export interface Move {
  type: 'move';
  at?: string;
  leg: Leg;
}

export type Item = Stop | Move;

export interface Meals {
  b: number;
  l: number;
  d: number;
  s: number;
}

export interface Day {
  n: number;
  date: string;
  dow: string;
  title: string;
  route: string;
  stay?: string;
  lead: string;
  walk?: string;
  meals: Meals;
  items: Item[];
  /** what to cut first when tired or late */
  trims: string[];
  alt?: { title: string; text: string; places: string[] };
}

type LegOpts = Partial<Omit<Leg, 'id' | 'line' | 'from' | 'to'>>;

// Stable id: the same line between the same points (and waypoints) shares geometry.
const hash = (s: string) => {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) >>> 0;
  return h.toString(36);
};
const leg = (line: LineKey, from: string, to: string, opts: LegOpts = {}, at?: string): Move => ({
  type: 'move',
  at,
  leg: { id: `${line}.${from}.${to}.${hash(JSON.stringify([opts.via ?? [], opts.path ?? []]))}`, line, from, to, ...opts },
});
const walk = (from: string, to: string, opts: LegOpts = {}, at?: string) => leg('walk', from, to, opts, at);
const stop = (at: string | undefined, place: string | undefined, title: string, text?: string, cost?: number, optional?: boolean): Stop => ({
  type: 'stop',
  at,
  place,
  title,
  text,
  cost,
  optional,
});

export const DAYS: Day[] = [
  {
    n: 1,
    date: '2027-10-18',
    dow: 'Thứ Hai',
    title: 'Đến Tokyo',
    route: 'Haneda → Akihabara',
    stay: 'resol-akihabara',
    walk: '4–6 km',
    meals: { b: 0, l: 2800, d: 3000, s: 1200 },
    lead: 'Hạ cánh Haneda buổi sáng hoặc đầu giờ chiều. Ngày đầu chỉ nhận phòng, đi bộ ven sông Kanda và ăn hai bữa gần khách sạn.',
    items: [
      leg('keikyu', 'haneda-t3', 'st-shinagawa', { min: '15–20', note: 'Hai người khoảng ¥1.500 cả chặng tới Akihabara. Tính 2–3 giờ từ lúc xuống máy bay tới khách sạn.' }, '11:00'),
      leg('keihinTohoku', 'st-shinagawa', 'st-akihabara', { min: '20' }),
      walk('st-akihabara', 'resol-akihabara', { min: '3' }),
      stop('12:00', 'resol-akihabara', 'Gửi hành lý', 'Nhận phòng từ 15h. Mỗi người một thẻ IC (Welcome Suica hoặc Suica trên iPhone), nạp khoảng ¥3.000.'),
      walk('resol-akihabara', 'tsumugi', { min: '5' }),
      stop('12:30', 'tsumugi', 'Ramen nước trong ở Tsumugi', 'Nếu nhập cảnh trễ, ăn nhẹ ở ga và để Tsumugi cho buổi tối — đừng kéo vali vào hàng chờ.', 2800),
      walk('tsumugi', 'resol-akihabara', { min: '5' }),
      stop('15:00', 'resol-akihabara', 'Nhận phòng, tắm, nghỉ'),
      walk('resol-akihabara', 'kanda-myojin', { via: ['manseibashi', [35.6993, 139.7677]], min: '30–45' }),
      stop('16:00', 'manseibashi', 'Manseibashi và sông Kanda', 'Qua cây cầu gạch đỏ mAAch ecute, đi dọc sông Kanda rồi rẽ vào ngõ Kanda.'),
      stop('16:45', 'kanda-myojin', 'Kanda Myōjin', 'Còn sức thì lên đền, nhìn ánh chiều trên mái đỏ.', undefined, true),
      walk('kanda-myojin', 'yamabe', { min: '15–20' }),
      stop('18:00', 'yamabe', 'Tonkatsu ở Yamabe', 'Bữa bình dân có cơm, bắp cải ăn thêm thoải mái.', 3000),
      walk('yamabe', 'resol-akihabara', { min: '15' }),
    ],
    trims: [
      'Bay đến tối: chỉ nhận phòng và ăn một bữa gần khách sạn.',
      'Đáp Narita: Keisei Skyliner tới Ueno rồi JR, thêm khoảng ¥4.000–5.000 cho hai người.',
    ],
  },
  {
    n: 2,
    date: '2027-10-19',
    dow: 'Thứ Ba',
    title: 'Yanaka, Asakusa, Nihonbashi',
    route: 'Phía đông bắc Tokyo',
    stay: 'resol-akihabara',
    walk: '8–10 km',
    meals: { b: 3800, l: 4400, d: 9000, s: 2400 },
    lead: 'Một vòng phía đông bắc theo cụm, không chạy qua Shibuya giữa hai bữa. Sáng ở khu phố cũ Yanaka, trưa Asakusa, tối ăn anago ở Nihonbashi.',
    items: [
      walk('resol-akihabara', 'st-akihabara', { min: '3' }, '7:50'),
      leg('yamanote', 'st-akihabara', 'st-nippori', { min: '7' }),
      walk('st-nippori', 'kayaba', { via: [[35.7262, 139.7696], [35.7236, 139.7712]], min: '12', note: 'Đi xuyên hàng cây nghĩa trang Yanaka.' }),
      stop('8:30', 'kayaba', 'Sáng ở Kayaba Coffee', 'Sandwich trứng và cà phê trong nhà gỗ năm 1938. Quán nghỉ thứ Hai nên để sang hôm nay.', 3800),
      walk('kayaba', 'nezu-taiyaki', { via: ['yanaka-ginza', [35.7243, 139.7652], [35.7213, 139.7637]], min: '40–60' }),
      stop('9:30', 'yanaka-ginza', 'Yanaka', 'Phố dân cư với chùa nhỏ, tiệm thủ công, mèo. Đi chậm, đừng vào ngõ có biển riêng tư.'),
      stop('10:15', 'nezu-taiyaki', 'Taiyaki ở Nezu', 'Nướng từng chiếc, có thể hết sớm.', undefined, true),
      walk('nezu-taiyaki', 'nezu-shrine', { min: '5' }),
      stop('10:30', 'nezu-shrine', 'Nezu Jinja', 'Hàng cổng torii đỏ nhỏ và hiên gỗ sơn son, vắng hơn Fushimi Inari nhiều.'),
      walk('nezu-shrine', 'st-ueno-hirokoji', { via: [[35.7148, 139.7663], [35.7118, 139.7699]], min: '20', note: 'Qua bờ hồ Shinobazu. Hoặc Chiyoda Line Nezu → Yushima rồi đi bộ.' }),
      leg('ginza', 'st-ueno-hirokoji', 'st-asakusa', { min: '6' }),
      walk('st-asakusa', 'owariya', { min: '5' }),
      stop('12:30', 'owariya', 'Soba tempura ở Owariya', 'Quán từ thời Edo cạnh Sensō-ji.', 4400),
      walk('owariya', 'sumida-river', { via: ['sensoji'], min: '20' }),
      stop('13:30', 'sensoji', 'Sensō-ji', 'Cổng Kaminarimon, chính điện, rồi rẽ vào các phố phía sau Nakamise cho bớt đông.'),
      stop('14:45', 'sumida-river', 'Bờ sông Sumida', 'Đứng trên cầu Azuma nhìn Skytree bên kia sông.'),
      walk('sumida-river', 'umezono', { min: '6' }),
      stop('15:15', 'umezono', 'Umezono', 'Anmitsu hoặc awa-zenzai nếu muốn ngồi nghỉ; chọn phần nhỏ sau bữa soba.', undefined, true),
      walk('umezono', 'st-asakusa', { min: '5' }),
      leg('ginza', 'st-asakusa', 'st-nihonbashi', { min: '15' }, '16:00'),
      walk('st-nihonbashi', 'tamai', { via: ['maruzen-nihonbashi', 'nihonbashi'], min: '15' }),
      stop('16:30', 'maruzen-nihonbashi', 'Maruzen và cầu Nihonbashi', 'Ghé nếu thích đồ viết, rồi ra cây cầu mốc số 0 của các con đường Nhật.', undefined, true),
      stop('18:00', 'tamai', 'Anago ở Tamai', 'Gọi hộp 中箱, phối nửa hấp nửa nướng, cuối bữa chan dashi vào cơm. Anago là lươn biển, khác unagi.', 9000),
      walk('tamai', 'st-nihonbashi', { min: '4' }),
      leg('ginza', 'st-nihonbashi', 'st-kanda', { min: '4' }),
      walk('st-kanda', 'resol-akihabara', { min: '10' }),
    ],
    trims: ['Mệt thì bỏ Maruzen hoặc Umezono, giữ thời gian nghỉ.', 'Không cần cố ăn đủ cả taiyaki lẫn món ngọt.'],
  },
  {
    n: 3,
    date: '2027-10-20',
    dow: 'Thứ Tư',
    title: 'Sushi, Harajuku, Shibuya',
    route: 'Phía tây Tokyo',
    stay: 'resol-akihabara',
    walk: '7–9 km',
    meals: { b: 1400, l: 11400, d: 8200, s: 1000 },
    lead: 'Sáng gửi vali đi Ise, trưa ăn bữa sushi chính của chuyến đi, chiều đi bộ từ Meiji Jingū xuống Shibuya.',
    items: [
      stop('8:00', 'resol-akihabara', 'Gửi một vali lớn đi Ise', 'Gửi tới Comfort Hotel ERA Ise, giao ngày 22/10, khoảng ¥3.000–3.300 mỗi chặng. Giữ quần áo hai đêm và thuốc trong túi nhỏ.'),
      walk('resol-akihabara', 'st-akihabara', { min: '3' }),
      leg('chuoSobu', 'st-akihabara', 'st-shinjuku', { min: '17' }, '9:00'),
      walk('st-shinjuku', 'sushi-ten', { min: '5' }),
      stop('11:00', 'sushi-ten', 'Sushi lunch ở TEN', "Chef's Choice Lunch ¥5.500/người, đặt qua ResReserve. Hủy sát ngày mất trọn tiền course.", 11400),
      walk('sushi-ten', 'st-shinjuku', { min: '5' }),
      leg('yamanote', 'st-shinjuku', 'st-harajuku', { min: '4' }),
      walk('st-harajuku', 'toritake', { via: ['meiji-jingu', [35.6699, 139.7032], 'omotesando', [35.6655, 139.7065], [35.6621, 139.7031]], min: '3–4 giờ, tính cả dừng' }),
      stop('13:00', 'meiji-jingu', 'Meiji Jingū', 'Lối sỏi dưới rừng cây giữa thành phố; vào từ cổng Harajuku.'),
      stop('14:30', 'omotesando', 'Omotesandō và Cat Street', 'Tối đa 60–90 phút cho UNIQLO/GU hoặc một tiệm secondhand. Đừng mang giày mới đi ngay cả ngày.'),
      stop('17:30', 'toritake', 'Yakitori ở Toritake', 'Xiên to, gọi ít lượt đầu rồi thêm. Có khói, đừng mặc áo mới.', 8200),
      walk('toritake', 'st-shibuya', { min: '4' }),
      leg('ginza', 'st-shibuya', 'st-kanda', { min: '25' }),
      walk('st-kanda', 'resol-akihabara', { min: '10' }),
    ],
    trims: [
      'Không muốn course toàn hải sản: thay TEN bằng Numazukō, gọi theo đĩa, rẻ hơn ¥3.000–5.000.',
      'Nếu Fuji quan trọng hơn Tokyo: đổi cả ngày thành Kawaguchiko (xem trang Fuji).',
    ],
  },
  {
    n: 4,
    date: '2027-10-21',
    dow: 'Thứ Năm',
    title: 'Hakone và một đêm onsen',
    route: 'Shinjuku → Hồ Ashi → Kowakudani',
    stay: 'mizunoto',
    walk: '4–6 km, có dốc',
    meals: { b: 1400, l: 3000, d: 0, s: 800 },
    lead: 'Một vòng Hakone bằng tàu, xe buýt, thuyền, cáp treo và tàu leo núi — nhưng mục tiêu là vào ryokan lúc 15h. Bữa tối đã nằm trong giá phòng.',
    items: [
      walk('resol-akihabara', 'st-akihabara', { min: '3' }, '6:30'),
      leg('chuoSobu', 'st-akihabara', 'st-shinjuku', { min: '17' }),
      leg('romancecar', 'st-shinjuku-odakyu', 'st-hakone-yumoto', { min: '85–95', note: 'Hakone Freepass 2 ngày ¥7.100/người, phụ phí Romancecar khoảng ¥1.200/người — hai khoản riêng.' }, '7:30'),
      leg('tozanBus', 'st-hakone-yumoto', 'onshi-hakone-park', { via: [[35.2297, 139.0915], [35.2086, 139.0617], [35.2056, 139.0397], 'moto-hakone-port', [35.1985, 139.0283]], min: '40', note: 'Tuyến H của Hakone Tozan Bus, trong Freepass. Đừng lên nhầm Izu Hakone Bus.' }, '9:30'),
      stop('10:00', 'onshi-hakone-park', 'Onshi Hakone Park', 'Đài quan sát nhìn hồ Ashi, Fuji hiện phía tây bắc nếu trời trong.'),
      walk('onshi-hakone-park', 'bakery-table', { via: ['hakone-sekisho', [35.1955, 139.0270], 'cedar-avenue'], min: '25' }),
      stop('11:00', 'bakery-table', 'Bánh mì ở Bakery & Table', 'Ăn trưa nhẹ cạnh hồ; không cần chờ chỗ ngâm chân nếu đông.', 3000),
      walk('bakery-table', 'moto-hakone-port', { min: '2' }),
      leg('ashiCruise', 'moto-hakone-port', 'togendai', {
        path: [
          [35.2009, 139.0303], [35.2018, 139.0225], [35.205, 139.015], [35.21, 139.007], [35.215, 138.999],
          [35.22, 138.9955], [35.225, 138.9958], [35.23, 138.9945], [35.2345, 138.9935], [35.2372, 138.995],
        ],
        min: '40',
      }, '11:30'),
      leg('hakoneRopeway', 'togendai', 'owakudani', { path: [[35.237912, 138.995299], [35.244487, 139.006123], [35.244418, 139.019576]], min: '25', note: 'Gió mạnh hoặc khí núi lửa thì ropeway dừng — đi xe thay thế theo thông báo.' }),
      stop('12:30', 'owakudani', 'Ōwakudani', 'Thung lũng khói lưu huỳnh; trứng đen kuro-tamago. Fuji ở phía tây bắc nếu trời quang.'),
      leg('hakoneRopeway', 'owakudani', 'sounzan', { path: [[35.244418, 139.019576], [35.246383, 139.035603]], min: '10' }),
      leg('hakoneCable', 'sounzan', 'st-gora', { min: '10' }),
      leg('hakoneTozan', 'st-gora', 'st-kowakudani', { min: '8' }, '14:00'),
      leg('shuttle', 'st-kowakudani', 'mizunoto', { min: '5', note: 'Shuttle của khách sạn 14–17h, mỗi 10–15 phút. Đi bộ 15 phút nhưng dốc.' }),
      stop('15:00', 'mizunoto', 'Nhận phòng Mizunoto', 'Thử bồn onsen riêng, nghỉ. Xin lượt ăn tối sớm khoảng 17:30; chọn course nướng nếu có. Tối dạo quanh khuôn viên rồi về phòng.'),
    ],
    trims: [
      'Ropeway dừng: đi xe thay thế, bỏ bớt phần hồ, đừng tìm taxi đuổi lịch.',
      'Trời xấu: nửa vòng rồi về sớm vẫn là một ngày tốt — căn phòng này đáng dùng trọn buổi chiều.',
    ],
  },
  {
    n: 5,
    date: '2027-10-22',
    dow: 'Thứ Sáu',
    title: 'Dọc Tōkaidō tới Ise',
    route: 'Hakone → Shimizu → Nagoya → Ise',
    stay: 'era-ise',
    walk: '3–4 km',
    meals: { b: 0, l: 6200, d: 4200, s: 800 },
    lead: 'Ngày chuyển vùng dài nhất, 8–10 giờ. Đoạn tàu thường dọc Tōkaidō để nhìn Fuji và biển, trưa ăn cá ngừ ở cảng Shimizu, rồi Shinkansen và Kintetsu xuống Ise.',
    items: [
      stop('7:30', 'mizunoto', 'Ăn sáng, trả phòng', 'Hỏi trước xe ra ga buổi sáng; không có thì đi bộ 15 phút xuống dốc với túi nhỏ.'),
      walk('mizunoto', 'st-kowakudani', { min: '15' }),
      leg('hakoneTozan', 'st-kowakudani', 'st-odawara', { min: '60–90 tính cả chờ', note: 'Tàu leo núi đổi chiều ba lần trên dốc; đổi tàu ở Hakone-Yumoto.' }),
      leg('tokaido', 'st-odawara', 'st-shimizu', { min: '2 giờ 30', note: 'Mua vé giấy cho chặng qua ranh Suica–TOICA ở Atami. Ngồi bên phải để nhìn Fuji; bên trái là biển đoạn Atami và Yui. Thường đổi tàu ở Atami, Numazu.' }, '9:30'),
      walk('st-shimizu', 'kaizan', { min: '3' }),
      stop('12:00', 'kaizan', 'Cá ngừ ở cảng Shimizu', 'Một người chọn cơm cá ngừ, người kia set tôm chiên. Ăn trong khoảng một giờ.', 6200),
      walk('kaizan', 'st-shimizu', { min: '3' }),
      leg('tokaido', 'st-shimizu', 'st-shizuoka', { min: '12' }, '13:00'),
      leg('shinkansen', 'st-shizuoka', 'st-nagoya', { min: '55–80', note: 'Hikari hoặc Kodama, ghế reserved khoảng ¥6.470/người.' }),
      walk('st-nagoya', 'st-kintetsu-nagoya', { min: '10' }),
      leg('kintetsu', 'st-kintetsu-nagoya', 'st-iseshi', { min: '80–90', note: '¥1.740 + ¥1.340 limited express mỗi người. Lên tàu đi Iseshi/Ujiyamada/Toba/Kashikojima, đừng lên tàu đi Osaka.' }, '15:30'),
      walk('st-iseshi', 'era-ise', { min: '3' }),
      stop('17:30', 'era-ise', 'Nhận phòng ERA Ise', 'Vali gửi từ Tokyo đã chờ ở đây.'),
      walk('era-ise', 'butasute', { min: '6' }),
      stop('18:00', 'butasute', 'Gyūdon ở Butasute', 'Gọi món cuối khoảng 19h.', 4200),
      walk('butasute', 'era-ise', { min: '6' }),
    ],
    trims: [
      'Muốn nhanh hơn: Odawara → Nagoya bằng Shinkansen, ít đổi tàu, thêm khoảng ¥5.000–7.000 cho hai người.',
      'Lỡ nối tàu: ăn tối ở Nagoya, đừng giữ bàn có phí hủy cho bữa này.',
    ],
  },
  {
    n: 6,
    date: '2027-10-23',
    dow: 'Thứ Bảy',
    title: 'Ise Jingū và phố Kawasaki',
    route: 'Gekū → Naikū → Kawasaki',
    stay: 'era-ise',
    walk: '7–9 km',
    meals: { b: 1400, l: 2200, d: 2400, s: 2000 },
    lead: 'Cuối tuần có nhiều khách Nhật đi lễ, nên vào đền sớm và ăn lệch giờ đông. Chiều về phố kho bên sông Seta.',
    items: [
      walk('era-ise', 'ise-geku', { min: '8' }, '7:00'),
      stop('7:30', 'ise-geku', 'Gekū buổi sáng', 'Đường sỏi, cây tuyết tùng, không khí sáng sớm. Đi một vòng gọn.'),
      walk('ise-geku', 'sengukan', { min: '5' }),
      stop('9:00', 'sengukan', 'Sengūkan', 'Bảo tàng về cách dựng lại đền mỗi 20 năm. ¥300/người, bỏ nếu chỉ muốn dạo.', 600, true),
      walk('sengukan', 'gekumae-bus', { min: '5' }),
      leg('mieBus', 'gekumae-bus', 'naikumae-bus', { min: '20–35', note: 'Xem chuyến hiện hành; hai chiều khoảng ¥2.000 cho hai người.' }, '9:45'),
      walk('naikumae-bus', 'ise-naiku', { via: ['uji-bridge'], min: '15' }),
      stop('10:15', 'ise-naiku', 'Naikū và cầu Uji', 'Nơi thờ tự: đọc biển, không chụp khu cấm, không chen hàng nghi lễ.'),
      walk('ise-naiku', 'fukusuke', { via: ['uji-bridge'], min: '15' }),
      stop('11:30', 'fukusuke', 'Ise udon ở Fukusuke', 'Sợi mềm, sốt đậm — món địa phương, không phải udon nấu quá tay.', 2200),
      stop('12:00', 'okage-yokocho', 'Okage Yokochō và Oharai-machi', 'Phố gỗ trước đền: croquette, đồ gỗ, khăn, bùa. Lúc dùng phần tiền goshuin và omamori.'),
      walk('fukusuke', 'akafuku', { min: '3' }),
      stop('13:00', 'akafuku', 'Akafuku tại chỗ', 'Mochi đậu đỏ với trà bên sông Isuzu.', undefined, true),
      walk('akafuku', 'naikumae-bus', { min: '8' }),
      leg('mieBus', 'naikumae-bus', 'gekumae-bus', { min: '20–35' }, '14:00'),
      walk('gekumae-bus', 'ise-kawasaki', { via: ['era-ise'], min: '20', note: 'Ghé khách sạn nghỉ một lúc.' }),
      stop('15:30', 'ise-kawasaki', 'Phố kho Kawasaki', 'Nhà kho thương nhân bên sông Seta. Có thể chỉ đi bộ và ngồi uống nước; tiệm nhỏ có thể đóng sớm.'),
      walk('ise-kawasaki', 'manpuku', { min: '20' }),
      stop('18:00', 'manpuku', 'Cơm gà karaage ở Manpuku', 'Chỉ nhận tiền mặt, nghỉ không cố định. Nếu đóng, ăn món cơm quanh ga.', 2400),
      walk('manpuku', 'era-ise', { min: '10' }),
    ],
    trims: ['Xuống sức sau Naikū: bỏ Sengūkan hoặc rút ngắn Kawasaki.', 'Giữ thời gian mua đồ ở đây — nhiều thứ không có ở Osaka.'],
  },
  {
    n: 7,
    date: '2027-10-24',
    dow: 'Chủ Nhật',
    title: 'Toba, đảo Tōshijima, Shimakaze',
    route: 'Ise → Toba → Kyoto',
    stay: 'cross-kyoto',
    walk: '5–7 km',
    meals: { b: 3600, l: 6600, d: 16000, s: 800 },
    lead: 'Một buổi sáng ở làng chài trên đảo, trưa tôm chiên ở Toba, chiều lên tàu ngắm cảnh Shimakaze về Kyoto. Đảo phụ thuộc thời tiết và giờ phà.',
    items: [
      stop('6:30', 'era-ise', 'Buffet sáng ERA, trả phòng', undefined, 3600),
      walk('era-ise', 'st-iseshi', { min: '3' }),
      leg('kintetsu', 'st-iseshi', 'st-toba', { min: '15–25', note: '¥390/người. Không cần limited express cho đoạn này.' }, '7:15'),
      stop('7:45', 'st-toba', 'Gửi vali vào locker', 'Mang túi nhẹ, nước và một món ăn vặt.'),
      walk('st-toba', 'toba-marine-terminal', { min: '10' }),
      leg('tobaFerry', 'toba-marine-terminal', 'toshijima-wagu', {
        path: [[34.49042, 136.84494], [34.496, 136.852], [34.504, 136.864], [34.511, 136.878], [34.5165, 136.8905], [34.52274, 136.89897]],
        min: '20–25',
        note: '¥550/người/chiều. Trước khi lên phà xác nhận cảng về, chuyến về và một chuyến sau đó.',
      }, '8:15'),
      stop('8:45', 'toshijima-wagu', 'Làng chài Wagu', 'Nhà chen sát nhau, ngõ hẹp, bến cá. Không đứng chắn cửa hay chụp người dân.'),
      walk('toshijima-wagu', 'toshijima-toshi', { min: '20–30' }),
      stop('10:00', 'toshijima-toshi', 'Làng Tōshi', 'Đi bộ giữa hai làng là phần hay nhất của đảo.'),
      leg('tobaFerry', 'toshijima-toshi', 'toba-marine-terminal', {
        path: [[34.53039, 136.903], [34.5268, 136.9068], [34.5212, 136.9025], [34.516, 136.888], [34.51, 136.876], [34.503, 136.863], [34.4955, 136.8515], [34.49042, 136.84494]],
        min: '15–20',
      }, '11:15'),
      walk('toba-marine-terminal', 'sazanami-toba', { min: '8' }),
      stop('12:00', 'sazanami-toba', 'Tôm chiên ở Sazanami', 'Gọi set thường. Hàng quá dài thì giới hạn 30 phút, đổi sang bento để không lỡ tàu.', 6600),
      walk('sazanami-toba', 'st-toba', { min: '8' }),
      leg('shimakaze', 'st-toba', 'st-kintetsu-kyoto', { min: '2 giờ 10', note: '¥2.740 + ¥1.640 + ¥1.050 mỗi người; chỉ hơn tàu thường ¥2.100 cho hai người. Hết chỗ thì đi limited express thường.' }, '15:20'),
      walk('st-kintetsu-kyoto', 'st-kyoto-karasuma', { min: '5' }),
      leg('karasuma', 'st-kyoto-karasuma', 'st-karasuma-oike', { min: '6' }, '17:45'),
      leg('tozai', 'st-karasuma-oike', 'st-shiyakusho', { min: '2' }),
      walk('st-shiyakusho', 'cross-kyoto', { min: '5' }),
      stop('18:30', 'cross-kyoto', 'Nhận phòng Cross Hotel'),
      walk('cross-kyoto', 'menami', { min: '4' }),
      stop('19:30', 'menami', 'Tối ở Menami', 'Bữa nâng cấp ở Kyoto: obanzai và món theo mùa. Đặt bàn, báo giờ đến thực tế.', 16000),
    ],
    trims: [
      'Gió mạnh hoặc giờ phà không khớp: bỏ đảo, đi bộ khu cảng Toba rồi ăn trưa.',
      'Không thêm Aquarium, Mikimoto hay ama ở Osatsu vào buổi này.',
    ],
    alt: {
      title: 'Thay bằng vịnh Ago ở Shima',
      text: 'Kintetsu Iseshi → Kashikojima (50–70 phút, ¥820/người), thuyền Espana trên vịnh Ago 50 phút (¥1.900/người), trưa ở Sazanami Shokudō, rồi Shimakaze từ Kashikojima khoảng 14:50. Thêm khoảng ¥3.000–5.000 cho hai người.',
      places: ['kashikojima', 'sazanami-shokudo'],
    },
  },
  {
    n: 8,
    date: '2027-10-25',
    dow: 'Thứ Hai',
    title: 'Kyoto phía đông và kimono',
    route: 'Kiyomizu → Gion → Okazaki',
    stay: 'cross-kyoto',
    walk: '8–10 km',
    meals: { b: 1400, l: 3600, d: 4400, s: 3800 },
    lead: 'Lên Kiyomizu-dera lúc còn mang giày đi bộ, rồi thuê kimono dạo phần phẳng của Gion. Chiều ăn udon muộn ở Okazaki thay bữa tối.',
    items: [
      walk('cross-kyoto', 'st-sanjo', { min: '5' }, '7:00'),
      leg('keihan', 'st-sanjo', 'st-kiyomizu-gojo', { min: '4' }),
      walk('st-kiyomizu-gojo', 'kiyomizudera', { via: [[34.9967, 135.7745], [34.9958, 135.7804]], min: '20–30, lên dốc' }),
      stop('7:45', 'kiyomizudera', 'Kiyomizu-dera', 'Sân khấu gỗ nhìn xuống thành phố trước giờ đông. ¥500/người.', 1000),
      walk('kiyomizudera', 'wargo-gion', { via: ['sannenzaka', [35.0003, 135.7787], [35.0021, 135.7754]], min: '30' }),
      stop('9:30', 'wargo-gion', 'Thuê kimono ở wargo Gion', 'Gói web từ ¥3.300/người. Mở 10h; slot sớm hơn phải đặt trước. Mang giày riêng để thay lúc trả.', 10000),
      walk('wargo-gion', 'yorozuya', { via: ['yasaka-shrine', [35.0046, 135.7766], 'gion-shirakawa'], min: '60–90 tính cả dừng' }),
      stop('10:30', 'yasaka-shrine', 'Yasaka Jinja và Gion Shirakawa', 'Đi các đường được phép, chụp bằng điện thoại, không đuổi theo maiko.'),
      stop('12:00', 'yorozuya', 'Udon hành Kujō ở Yorozuya', undefined, 3600),
      walk('yorozuya', 'komori', { min: '5' }),
      stop('13:00', 'komori', 'Warabi mochi ở Komori', 'Còn no hoặc hàng dài thì bỏ, giữ tiền.', 3800, true),
      walk('komori', 'wargo-gion', { min: '6' }),
      stop('14:30', 'wargo-gion', 'Trả kimono, nghỉ'),
      walk('wargo-gion', 'menzo', { via: [[35.0067, 135.7773], [35.0089, 135.7807], [35.0128, 135.7822]], min: '25', note: 'Hoặc Keihan tới Sanjō, Tōzai tới Higashiyama rồi đi bộ 10 phút.' }),
      stop('16:00', 'menzo', 'Udon ở Yamamoto Menzō', 'Đặt slot khoảng 16h; có đặt vẫn có thể chờ 20–30 phút. Trả tiền mặt.', 4400),
      walk('menzo', 'st-higashiyama', { via: ['okazaki'], min: '20' }),
      stop('17:00', 'okazaki', 'Dạo kênh Okazaki', 'Không cần bữa tối thứ hai sau udon muộn.'),
      leg('tozai', 'st-higashiyama', 'st-shiyakusho', { min: '4' }),
      walk('st-shiyakusho', 'cross-kyoto', { min: '5' }),
    ],
    trims: ['Kimono khó chịu hoặc mưa: rút còn 2–3 giờ.', 'Không lấy được chỗ Menzō: đừng xếp hàng 90 phút, ăn quanh khách sạn.'],
    alt: {
      title: 'Chợ phiên Kitano Tenmangū ngày 25',
      text: 'Ngày 25 hằng tháng có chợ đồ cũ, đồ dùng ở Kitano Tenmangū. Nếu thích chợ hơn kimono, thay buổi sáng Kiyomizu + kimono bằng chợ khoảng 9–12h; bus 10 từ khu Sanjō/City Hall (35–50 phút). Vẫn giữ Menzō lúc 16h.',
      places: ['kitano-tenmangu'],
    },
  },
  {
    n: 9,
    date: '2027-10-26',
    dow: 'Thứ Ba',
    title: 'Saga, Arashiyama và kho sake Fushimi',
    route: 'Arashiyama → Fushimi',
    stay: 'cross-kyoto',
    walk: '8–11 km',
    meals: { b: 1400, l: 5600, d: 7000, s: 1000 },
    lead: 'Đi bus lên ngôi chùa có 1.200 tượng đá ở Otagi, rồi đi bộ xuống dốc qua phố cổ Saga-Toriimoto, rừng tre, cầu Togetsukyō. Chiều sang khu sake Fushimi.',
    items: [
      stop('7:00', 'cross-kyoto', 'Gửi vali Kyoto → Osaka', 'Gửi tới Hotel Forza, giao ngày 27/10. Giữ túi cho đêm cuối ở Kyoto.'),
      walk('cross-kyoto', 'st-kawaramachi', { min: '8' }),
      leg('hankyu', 'st-kawaramachi', 'st-arashiyama', { min: '40–50, đổi tàu ở Katsura' }, '7:30'),
      leg('kyotoBus', 'st-arashiyama', 'otagi-bus', { via: [[35.0153, 135.6773], [35.0214, 135.6720], [35.0262, 135.6655]], min: '25', note: 'Kyoto Bus 94 hướng Kiyotaki. Chuyến thưa; chờ quá 25–30 phút thì đi bộ lên khoảng một giờ.' }),
      stop('9:00', 'otagi-nenbutsuji', 'Otagi Nenbutsu-ji', '1.200 tượng rakan phủ rêu, mỗi tượng một nét mặt. ¥1.000/người, 9–16h.', 2000),
      walk('otagi-nenbutsuji', 'togetsukyo', { via: ['saga-toriimoto', 'adashino', [35.0216, 135.6698], 'bamboo-grove'], min: '45–75, xuống dốc' }),
      stop('10:00', 'saga-toriimoto', 'Phố cổ Saga-Toriimoto', 'Nhà mái tranh, quán trà, nhịp chậm hẳn khu gần cầu.'),
      stop('10:45', 'bamboo-grove', 'Rừng tre Sagano', 'Đi một đoạn, không cần chờ ảnh vắng người.'),
      stop('11:15', 'togetsukyo', 'Cầu Togetsukyō'),
      walk('togetsukyo', 'yoshimura', { min: '2' }),
      stop('11:30', 'yoshimura', 'Soba ở Yoshimura', 'Tempura soba khoảng ¥2.560. Bàn cửa sổ nhìn cầu không chắc có.', 5600),
      walk('yoshimura', 'st-arashiyama', { min: '8' }),
      leg('hankyu', 'st-arashiyama', 'st-kawaramachi', { min: '40' }, '14:00'),
      walk('st-kawaramachi', 'st-gion-shijo', { min: '7–10' }),
      leg('keihan', 'st-gion-shijo', 'st-chushojima', { min: '15' }),
      walk('st-chushojima', 'torisei', { via: ['fushimi-sake', [34.9317, 135.7596]], min: '40–60 tính cả dừng' }),
      stop('15:30', 'fushimi-sake', 'Khu kho sake Fushimi', 'Kênh đào, nhà kho mái đen, Teradaya. Khu này khác Fushimi Inari, không đi bộ qua lại được.'),
      stop('17:30', 'torisei', 'Yakitori ở Torisei', 'Một lượt sake Fushimi nếu uống.', 7000),
      walk('torisei', 'st-chushojima', { min: '8' }),
      leg('keihan', 'st-chushojima', 'st-sanjo', { min: '20' }),
      walk('st-sanjo', 'cross-kyoto', { min: '5' }),
    ],
    trims: ['Mưa: bỏ Otagi, dạo Teramachi và Nishiki, giữ Fushimi nếu trời ổn.'],
  },
  {
    n: 10,
    date: '2027-10-27',
    dow: 'Thứ Tư',
    title: 'Fushimi Inari, Nara, rồi Osaka',
    route: 'Kyoto → Nara → Osaka',
    stay: 'forza-osaka',
    walk: '10–14 km',
    meals: { b: 1400, l: 8000, d: 5400, s: 4000 },
    lead: 'Fushimi Inari lúc 7h khi cổng còn vắng, Nara vào giữa buổi, trưa đã đặt ở Naramachi, chiều xuống Osaka ăn okonomiyaki.',
    items: [
      walk('cross-kyoto', 'st-sanjo', { min: '5' }, '6:45'),
      leg('keihan', 'st-sanjo', 'st-fushimi-inari', { min: '10', note: 'Lên tàu local — limited express không dừng ga này.' }),
      walk('st-fushimi-inari', 'st-fushimi-inari', { via: ['fushimi-inari', [34.96673, 135.775097], [34.9666, 135.7787], [34.96673, 135.775097], 'fushimi-inari'], min: '60' }),
      stop('7:15', 'fushimi-inari', 'Fushimi Inari Taisha', 'Đi hết đoạn Senbon Torii và lên vừa phải; đừng đặt mục tiêu leo tới đỉnh.'),
      leg('keihan', 'st-fushimi-inari', 'st-tambabashi', { min: '5' }, '8:30'),
      walk('st-tambabashi', 'st-kintetsu-tambabashi', { min: '3' }),
      leg('kintetsu', 'st-kintetsu-tambabashi', 'st-kintetsu-nara', { min: '50–70, đổi ở Yamato-Saidaiji', note: 'Dùng thẻ IC, không cần limited express. Khoảng ¥1.600 cho hai người.' }),
      walk('st-kintetsu-nara', 'kasuga-taisha', { via: [[34.6852, 135.8337], 'todaiji', [34.6851, 135.8449]], min: '60 tính cả dừng' }),
      stop('10:00', 'todaiji', 'Tōdai-ji', 'Tượng Đại Phật trong điện gỗ. ¥800/người. Đừng dành cả giờ chụp hươu.', 1600),
      stop('11:15', 'kasuga-taisha', 'Kasuga Taisha', 'Hàng nghìn đèn lồng đá. Vòng ngoài miễn phí, phần trong ¥700/người.', 1400, true),
      walk('kasuga-taisha', 'awa', { via: [[34.6800, 135.8380]], min: '25–35' }),
      stop('12:30', 'awa', 'Lunch rau Yamato ở AWA', 'Đã đặt. 収穫祭御膳 ¥3.800/người.', 8000),
      walk('awa', 'hosekibako', { via: ['nakagawa-masashichi-nara', 'naramachi'], min: '20' }),
      stop('14:00', 'nakagawa-masashichi-nara', 'Nakagawa Masashichi', 'Khăn kaya fukin, đồ gia dụng thủ công.'),
      stop('15:00', 'hosekibako', 'Đá bào Hōsekibako', 'Lạnh, không thích đá bào hoặc không có slot thì bỏ.', 4000, true),
      walk('hosekibako', 'st-kintetsu-nara', { min: '12' }),
      leg('kintetsu', 'st-kintetsu-nara', 'st-osaka-namba', { min: '35–45', note: 'Rapid Express, khoảng ¥1.400 cho hai người.' }, '16:00'),
      walk('st-osaka-namba', 'forza-osaka', { min: '8' }),
      stop('17:00', 'forza-osaka', 'Nhận phòng Forza', 'Vali gửi từ Kyoto đã tới.'),
      walk('forza-osaka', 'fukutaro', { min: '6' }),
      stop('17:30', 'fukutaro', 'Okonomiyaki ở Fukutarō', 'Hàng có thể lâu; quá mệt thì ăn món tương tự gần khách sạn.', 5400),
    ],
    trims: [
      'Muốn nhẹ hơn: bỏ phần trong Kasuga hoặc đá bào, Nara vẫn trọn.',
      'Triển lãm Shōsōin thường rơi vào cuối tháng 10 — đông hơn, nhưng đừng thêm vào ngày này.',
    ],
  },
  {
    n: 11,
    date: '2027-10-28',
    dow: 'Thứ Năm',
    title: 'Osaka: ăn và mua sắm',
    route: 'Namba ↔ Umeda',
    stay: 'forza-osaka',
    walk: '6–9 km',
    meals: { b: 1400, l: 3600, d: 14000, s: 1400 },
    lead: 'Ngày mua sắm có chủ đích: đồ bếp ở Dōguyasuji, hộp bánh ở Takashimaya, một cụm chính buổi chiều. Về khách sạn cất đồ trước bữa thịt nướng.',
    items: [
      walk('forza-osaka', 'doguyasuji', { via: ['hozenji'], min: '10' }, '8:00'),
      stop('8:15', 'hozenji', 'Hōzen-ji Yokochō', 'Ngõ đá và tượng Fudō phủ rêu, yên nhất vào sáng sớm.'),
      stop('9:00', 'doguyasuji', 'Dōguyasuji', 'Một hai món bếp dùng thật. Dao chỉ mua khi biết loại thép và cách bảo quản.'),
      walk('doguyasuji', 'horai-551', { min: '6' }),
      stop('11:15', 'horai-551', '551 Hōrai', 'Ăn ngồi ở nhà hàng tầng trên. Nghỉ thứ Ba.', 3600),
      walk('horai-551', 'takashimaya-osaka', { min: '5' }),
      stop('12:00', 'takashimaya-osaka', 'Takashimaya, tầng thực phẩm', 'Hộp bánh hạn dài mua cuối chuyến; so một hộp lớn với nhiều gói nhỏ.'),
      walk('takashimaya-osaka', 'st-namba', { min: '4' }),
      leg('midosuji', 'st-namba', 'st-umeda', { min: '8' }, '13:00'),
      walk('st-umeda', 'nakazakicho', { via: ['loft-umeda', [34.7046, 135.4990]], min: '15–20 tính đường' }),
      stop('13:15', 'loft-umeda', 'Loft Umeda', 'Tầng 6 Hanshin Umeda Honten — không phải địa chỉ Loft Chayamachi cũ.'),
      stop('14:30', 'hanadako', 'Takoyaki Hanadako', 'Snack khi đã ở Umeda.', 1400, true),
      stop('15:00', 'nakazakicho', 'Nakazakichō', 'Ngõ nhà cũ với cà phê nhỏ, 15–20 phút.', undefined, true),
      walk('nakazakicho', 'st-umeda', { min: '12' }),
      leg('midosuji', 'st-umeda', 'st-namba', { min: '8' }, '16:00'),
      walk('st-namba', 'forza-osaka', { min: '8' }),
      stop('16:30', 'forza-osaka', 'Cất đồ, cân thử hành lý'),
      walk('forza-osaka', 'tahei', { min: '6' }),
      stop('17:15', 'tahei', 'Yakiniku ở Tahei', 'Tiền mặt, nhiều khói, hai người khó đặt bàn — tới sớm.', 14000),
    ],
    trims: [
      'Ưu tiên quần áo và mỹ phẩm: thay cụm Umeda bằng Shinsaibashi – Amerikamura (UNIQLO/GU, secondhand, Hands trong PARCO).',
      'Tối chỉ mua phần còn thiếu trong danh sách; kiểm hóa đơn hoàn thuế, hạn dùng, chất lỏng, cân.',
    ],
  },
  {
    n: 12,
    date: '2027-10-29',
    dow: 'Thứ Sáu',
    title: 'Ra sân bay Kansai',
    route: 'Namba → KIX',
    walk: '1–2 km',
    meals: { b: 1400, l: 2400, d: 0, s: 400 },
    lead: 'Giờ đi theo chuyến bay thực tế. Có mặt sân bay khoảng ba giờ trước giờ bay, thêm thời gian cho thủ tục hoàn thuế.',
    items: [
      walk('forza-osaka', 'st-nankai-namba', { min: '12–15' }),
      leg('nankai', 'st-nankai-namba', 'kix', { min: '45–50', note: 'Airport Express không giữ chỗ, ¥2.200 cho hai người. Rapi:t nhanh hơn, có ghế reserved, đắt hơn.' }),
      stop(undefined, 'kix', 'Sân bay Kansai', 'Hệ thống hoàn thuế mới: có thể phải trình hàng trước khi ký gửi. Tiêu nốt số dư Welcome Suica — thẻ không hoàn tiền.'),
    ],
    trims: ['Chuyến bay sớm: mua đồ ăn sáng từ tối hôm trước.'],
  },
];

export const legsOf = (day: Day): Leg[] => day.items.filter((i): i is Move => i.type === 'move').map((i) => i.leg);
export const allLegs = (): Leg[] => DAYS.flatMap(legsOf);
export const foodTotal = (m: Meals) => m.b + m.l + m.d + m.s;
