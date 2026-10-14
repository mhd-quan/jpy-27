// Money, shopping, passes, phrases and the booking calendar.
// All yen amounts are for two people unless stated. Research date: 13/10/2026.

export const TRIP = {
  title: 'Nhật Bản 2027',
  start: '2027-10-18',
  end: '2027-10-29',
  nights: 11,
  people: 2,
  researched: '13/10/2026',
  rate: 175, // VND per yen, planning assumption
};

export interface BudgetLine {
  id: string;
  label: string;
  yen: number;
  note: string;
  color: string;
}

export const BUDGET: BudgetLine[] = [
  { id: 'hotel', label: 'Khách sạn thành phố', yen: 161_000, note: '10 đêm: Tokyo 45.000, Ise 22.000, Kyoto 66.000, Osaka 28.000', color: '#3A6FD9' },
  { id: 'ryokan', label: 'Ryokan Hakone', yen: 74_000, note: 'Phòng onsen riêng, hai bữa', color: '#8A5CD0' },
  { id: 'food', label: 'Ăn ngoài', yen: 172_000, note: 'Không tính lại hai bữa trong ryokan', color: '#E9792B' },
  { id: 'shop', label: 'Mua sắm và quà', yen: 130_000, note: 'Giỏ theo số lượng, gồm một vali mới', color: '#D23A3A' },
  { id: 'move', label: 'Di chuyển', yen: 72_200, note: 'Một đoạn Shinkansen, có Shimakaze', color: '#1E8A55' },
  { id: 'ticket', label: 'Vé tham quan, kimono', yen: 17_000, note: 'Kimono hai người, đền chùa có thu phí', color: '#0E9FB0' },
  { id: 'extra', label: 'Chi phí phụ', yen: 18_000, note: 'Thuế lưu trú, gửi vali, eSIM, giặt, locker', color: '#8E8E93' },
  { id: 'reserve', label: 'Dự phòng', yen: 40_000, note: 'Tỷ giá, thời tiết, phát sinh thật — giữ tới đêm cuối', color: '#C7C7CC' },
];

export const RATE_SCENARIOS = [
  { rate: 165, note: 'Giữ nguyên kế hoạch, không tự nâng hạng phòng.' },
  { rate: 175, note: 'Kế hoạch chính.' },
  { rate: 180, note: 'Đổi Cross sang RESOL Kyoto, bớt khoảng ¥18.000.' },
  { rate: 190, note: 'RESOL Kyoto, phòng Mizunoto cơ bản, bỏ một đôi giày và một quần GU — bớt khoảng ¥53.000.' },
];

export const SAVINGS = [
  { id: 'resol', label: 'Kyoto: Cross → RESOL', yen: 18_000 },
  { id: 'mizunoto', label: 'Ryokan: phòng cơ bản, dùng bồn garden', yen: 18_000 },
  { id: 'asics', label: 'Bỏ đôi ASICS', yen: 14_000 },
  { id: 'gu', label: 'Bỏ một quần GU', yen: 3_000 },
];

export interface ShopItem {
  id: string;
  name: string;
  qty: number;
  unit: number;
  where: string;
  group: 'wear' | 'beauty' | 'gift' | 'temple' | 'home';
}

export const SHOPPING: ShopItem[] = [
  { id: 'airism', name: 'UNIQLO AIRism cotton', qty: 4, unit: 2_000, where: 'Harajuku ngày 3 hoặc Shinsaibashi ngày 11', group: 'wear' },
  { id: 'gu-pants', name: 'Quần GU cơ bản hoặc jean', qty: 2, unit: 3_000, where: 'Thử tại cửa hàng lớn', group: 'wear' },
  { id: 'gu-top', name: 'Áo GU casual', qty: 2, unit: 1_500, where: 'Cùng lượt mua quần', group: 'wear' },
  { id: 'socks', name: 'Tất', qty: 6, unit: 400, where: 'UNIQLO, GU, MUJI', group: 'wear' },
  { id: 'onitsuka', name: 'Onitsuka Tiger MEXICO 66', qty: 1, unit: 17_000, where: 'Cửa hàng chính hãng Tokyo hoặc Osaka', group: 'wear' },
  { id: 'asics', name: 'ASICS đi bộ/chạy', qty: 1, unit: 14_000, where: 'ABC-MART hoặc ASICS, thử đúng mẫu', group: 'wear' },
  { id: 'anello', name: 'anello CROSS BOTTLE', qty: 1, unit: 7_000, where: 'anello Shinsaibashi hoặc LINKS UMEDA', group: 'wear' },
  { id: 'melano', name: 'Melano CC Premium 20 ml', qty: 4, unit: 1_800, where: 'Drugstore, đúng bản Premium', group: 'beauty' },
  { id: 'anessa', name: 'Anessa Perfect UV Milk 60 ml', qty: 2, unit: 3_500, where: 'Drugstore', group: 'beauty' },
  { id: 'fino', name: 'Fino hair mask 230 g', qty: 2, unit: 1_200, where: 'Drugstore, hũ nặng', group: 'beauty' },
  { id: 'canmake', name: 'CANMAKE Cream Cheek', qty: 2, unit: 800, where: 'Drugstore hoặc Loft có tester', group: 'beauty' },
  { id: 'dhc', name: 'DHC lip cream', qty: 2, unit: 800, where: 'Drugstore', group: 'beauty' },
  { id: 'yokumoku', name: 'Hộp bánh Yoku Moku', qty: 4, unit: 2_200, where: 'Takashimaya Osaka, cuối chuyến', group: 'gift' },
  { id: 'snacks', name: 'KitKat, bánh gạo chia bạn bè', qty: 4, unit: 1_000, where: 'Siêu thị hoặc Donki', group: 'gift' },
  { id: 'hojicha', name: 'Ippodo hōjicha 100 g', qty: 6, unit: 900, where: 'Kyoto, gần khách sạn', group: 'gift' },
  { id: 'fukin', name: 'Khăn kaya fukin Nakagawa Masashichi', qty: 6, unit: 700, where: 'Naramachi ngày 10', group: 'gift' },
  { id: 'goshuincho', name: 'Sổ goshuin', qty: 2, unit: 2_000, where: 'Đền chùa thực sự ghé', group: 'temple' },
  { id: 'goshuin', name: 'Goshuin', qty: 8, unit: 500, where: 'Bốn lượt mỗi người', group: 'temple' },
  { id: 'omamori', name: 'Omamori', qty: 4, unit: 1_000, where: 'Ise, Kyoto hoặc Nara', group: 'temple' },
  { id: 'bowl', name: 'Bát, gốm nhỏ dùng được', qty: 2, unit: 1_200, where: 'Dōguyasuji', group: 'home' },
  { id: 'stationery', name: 'Văn phòng phẩm, đồ tiện dụng', qty: 3, unit: 1_000, where: 'Maruzen, Hands, Loft', group: 'home' },
  { id: 'suitcase', name: 'Vali S 35–41 lít', qty: 1, unit: 12_000, where: 'Donki Osaka, so cỡ và cân', group: 'home' },
];

export const SHOP_GROUPS: Record<ShopItem['group'], string> = {
  wear: 'Quần áo, giày, túi',
  beauty: 'Mỹ phẩm',
  gift: 'Quà ăn được, trà, khăn',
  temple: 'Đền chùa',
  home: 'Đồ dùng',
};

export const TRANSPORT_LINES = [
  { label: 'Haneda → Akihabara', yen: 1_500 },
  { label: 'Nội đô Tokyo ba ngày', yen: 3_200 },
  { label: 'Hakone Freepass 2 ngày', yen: 14_200 },
  { label: 'Phụ phí Romancecar', yen: 2_400 },
  { label: 'JR local Odawara → Shizuoka', yen: 4_000 },
  { label: 'Shinkansen Shizuoka → Nagoya', yen: 13_000 },
  { label: 'Kintetsu, vé cơ bản ba chặng', yen: 9_800 },
  { label: 'Kintetsu limited express', yen: 6_000 },
  { label: 'Nâng lên Shimakaze', yen: 2_200 },
  { label: 'Xe buýt Mie Kotsu', yen: 2_000 },
  { label: 'Phà Tōshijima', yen: 2_200 },
  { label: 'Kyoto: subway, Keihan, Hankyu, bus', yen: 5_000 },
  { label: 'Kintetsu Tambabashi → Nara', yen: 1_600 },
  { label: 'Kintetsu Nara → Namba', yen: 1_400 },
  { label: 'Osaka Metro', yen: 1_500 },
  { label: 'Nankai Namba → KIX', yen: 2_200 },
];

export const PASSES = [
  {
    name: 'Hakone Freepass 2 ngày',
    verdict: 'Mua',
    text: '¥7.100/người từ Shinjuku: bus, thuyền, ropeway, cáp kéo, tàu leo núi. Phụ phí Romancecar khoảng ¥1.200/người trả riêng.',
  },
  {
    name: 'Welcome Suica hoặc Suica iPhone',
    verdict: 'Mua',
    text: 'Không cọc, dùng 28 ngày, không hoàn số dư. Không phải pass: không gồm limited express, Shinkansen, phà.',
  },
  {
    name: 'JR Pass toàn quốc',
    verdict: 'Bỏ',
    text: 'Bản 7 ngày ¥50.000/người, quá xa phần JR thực dùng — chỉ một đoạn Shinkansen ngắn.',
  },
  {
    name: 'Kintetsu Pass 5 ngày',
    verdict: 'Bỏ',
    text: '¥4.900/người, gần như hòa vốn; hết hạn 26/10, trước ngày đi Nara.',
  },
];

export const PHRASES = [
  { use: 'Xin bàn', ja: '二人です。', vi: 'Chúng tôi hai người.' },
  { use: 'Hỏi chờ', ja: '待ち時間はどのくらいですか。', vi: 'Cần đợi khoảng bao lâu?' },
  { use: 'Thanh toán thẻ', ja: 'カードは使えますか。', vi: 'Có dùng thẻ được không?' },
  { use: 'Món chín', ja: '生より、焼いた料理が好きです。', vi: 'Tôi thích món nướng hơn món sống.' },
  { use: 'Mua vé đi Ise', ja: '伊勢市まで、特急券と乗車券を二人分お願いします。', vi: 'Cho hai vé cơ bản và limited express tới Iseshi.' },
  { use: 'Hỏi phà', ja: '鳥羽に戻る船は、何時で、どの港からですか。', vi: 'Tàu về Toba lúc nào, từ cảng nào?' },
  { use: 'Bồn onsen', ja: 'この部屋の露天風呂は温泉ですか。', vi: 'Bồn ngoài trời phòng này có phải onsen không?' },
  { use: 'Bồn riêng', ja: '二人で使える貸切風呂はありますか。', vi: 'Có bồn riêng cho hai người không?' },
  { use: 'Tổng tiền phòng', ja: '二人一泊二食で、税金を含めた総額はいくらですか。', vi: 'Hai người, một đêm hai bữa, gồm thuế là bao nhiêu?' },
  { use: 'Gửi vali', ja: '予約名と到着日を書いて、ホテルへ荷物を送れますか。', vi: 'Có thể gửi hành lý tới khách sạn với tên đặt và ngày đến không?' },
];

export interface Booking {
  /** exact opening time in Japan time, only when the rule pins it down */
  at?: string;
  title: string;
  text: string;
  rule: string;
}

export const BOOKINGS: Booking[] = [
  { title: 'Giữ ryokan và phòng Ise', rule: 'Ngay khi khách sạn mở lịch tháng 10/2027', text: 'Đặt loại có thể hủy. Mizunoto: tên phòng có 温泉, hai bữa. Sau đó Kyoto, Tokyo, Osaka.' },
  { title: 'Theo dõi giá phòng', rule: '90, 60 và 30 ngày trước', text: 'So cùng ngày, hai người, cùng hạng phòng, cùng điều kiện hủy.' },
  { title: 'Bàn ăn đặt trước', rule: '60–30 ngày trước, theo cửa sổ của từng quán', text: 'SUSHI TOKYO TEN lunch ¥5.500 (ResReserve), Menami, AWA Naramachi.' },
  { title: 'Vé JR và Shimakaze', rule: 'Khoảng một tháng trước', text: 'Ghế reserved Shinkansen Shizuoka → Nagoya ngày 22/10; Shimakaze Toba → Kyoto ngày 24/10, giữ tàu thường làm phương án.' },
  { at: '2027-10-22T00:00:00+09:00', title: 'Đặt Yamamoto Menzō', rule: '0h giờ Nhật, ba ngày trước', text: 'Cho ngày 25/10 — tức 22h tối 21/10 giờ Việt Nam. Hủy trong 12 giờ mất ¥1.000/người.' },
  { at: '2027-10-26T21:00:00+09:00', title: 'Đặt Hōsekibako', rule: '21h giờ Nhật, tối hôm trước', text: 'Cho ngày 27/10 — 19h giờ Việt Nam. Đúng chi nhánh 29011038.' },
];

export const CHECKS = [
  { when: 'Khi chốt vé bay', text: 'Giờ đến, Haneda hay Narita, giờ đi KIX, số kiện và cân hành lý.' },
  { when: 'Khi đặt phòng', text: 'Đúng hai người, Twin/Double, không hút thuốc, bữa ăn, tổng gồm thuế, thuế lưu trú, hạn hủy.' },
  { when: 'Tuần đi', text: 'Lịch nghỉ mới của quán, slot Hōsekibako, vận hành Hakone, dự báo Fuji, giờ phà, tình hình Shōsōin.' },
  { when: 'Trước mỗi lần gửi vali', text: 'Khách sạn nhận kiện, tên người đặt, ngày nhận, đồ giữ lại trong túi.' },
  { when: 'Trước khi mua lớn', text: 'Thử size, đúng mã, giữ hóa đơn, đánh dấu phần còn lại trong giỏ.' },
  { when: 'Trước khi ra KIX', text: 'Quy trình hoàn thuế mới, hàng cần trình, terminal, giờ check-in.' },
];

export const yen = (n: number) => `¥${n.toLocaleString('vi-VN')}`;
export const vndMillions = (yenAmount: number, rate = TRIP.rate) =>
  `${((yenAmount * rate) / 1e6).toLocaleString('vi-VN', { maximumFractionDigits: 1 })} triệu`;

export interface StayPlan {
  id: string;
  nights: string;
  dates: string;
  target: number;
  range: string;
  room: string;
  good: string;
  know: string;
  switchAt: string;
}

export const STAYS: StayPlan[] = [
  {
    id: 'resol-akihabara',
    nights: '3 đêm',
    dates: '18 – 21/10',
    target: 15_000,
    range: '¥13.000–18.000',
    room: 'Twin 17 m², hai giường 100 cm, unit bath, washlet, tủ lạnh, ấm nước.',
    good: 'Business hotel tầm trung, sạch, khu tương đối yên. Tiện đi Shinjuku, Ueno và ga Tokyo.',
    know: 'Phòng nhỏ: cất vali sau khi lấy đồ, không mở hai vali lớn cùng lúc. Chọn Twin thay Moderate 14 m² nếu giá gần nhau.',
    switchAt: 'Trên ¥18.000/đêm thì so khách sạn gần ga quanh Kanda hoặc Ueno.',
  },
  {
    id: 'mizunoto',
    nights: '1 đêm',
    dates: '21 – 22/10',
    target: 74_000,
    range: 'tối đa ¥80.000',
    room: '水花の庄 温泉露天風呂付洋室 35 m², hai giường 105 × 195 cm, bồn ngoài trời nước onsen thật, hai bữa.',
    good: 'Cải tạo 2025, có bồn riêng trong phòng và các bồn garden 貸切 miễn phí theo lượt trống. Shuttle từ ga Kowakudani.',
    know: 'Resort nhiều phòng: không có nakai riêng, ăn theo lượt ở nhà hàng. Thuế tắm ¥150/người tính riêng.',
    switchAt: 'Trên ¥80.000: chọn 水月の庄 和洋室 46 m² khoảng ¥56.000–64.000, dùng bồn garden.',
  },
  {
    id: 'era-ise',
    nights: '2 đêm',
    dates: '22 – 24/10',
    target: 11_000,
    range: '¥9.000–13.000',
    room: 'Twin 22–24 m², hai giường khoảng 123 cm, phòng tắm riêng.',
    good: 'Rộng hơn Tokyo, ngay trước ga Iseshi, đi bộ tới Gekū. Library café để ngồi uống trà.',
    know: 'Bữa sáng ¥1.800/người, không còn miễn phí. Giờ buffet đông có thể phải chờ.',
    switchAt: 'Trên ¥13.000: đổi ngày hoặc so phòng không bữa quanh ga.',
  },
  {
    id: 'cross-kyoto',
    nights: '3 đêm',
    dates: '24 – 27/10',
    target: 22_000,
    range: '¥20.000–25.000',
    room: 'Standard Twin 25 m², giường 100 × 200 cm, bồn tắm, bồn rửa và WC tách nhau.',
    good: 'Hạng nâng cấp của chuyến. Đi bộ về sau bữa tối ở Pontochō, Kiyamachi, sông Kamo; có bồn tắm rộng sau ngày đi bộ.',
    know: 'Standard không đồng nghĩa view sông; vài cửa sổ nhìn ra công trình bên cạnh.',
    switchAt: 'Trên ¥25.000: dùng RESOL Kyoto Kawaramachi Sanjō, ¥16.000/đêm, cùng khu.',
  },
  {
    id: 'forza-osaka',
    nights: '2 đêm',
    dates: '27 – 29/10',
    target: 14_000,
    range: '¥12.000–17.000',
    room: 'Forza Double 18 m², giường 160 cm, unit bath.',
    good: 'Ngay khu Dōtonbori, tiện về cất đồ mua sắm. Hōzenji 3–5 phút, Dōguyasuji 8–10 phút.',
    know: 'Phố đông có thể ồn. Nankai Namba để ra KIX cách 12–15 phút đi bộ. Ảnh phòng Triple không phải phòng Double.',
    switchAt: 'Có thể trả thêm một chút để giữ vị trí — đỡ bước đi trong ngày mua sắm.',
  },
];
