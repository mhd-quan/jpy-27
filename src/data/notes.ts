// Handbook prose and lists shared by the site's Sổ tay page and the iOS app.

export interface Note {
  id: string;
  title: string;
  text: string;
}

export interface NoteGroup {
  id: string;
  title: string;
  notes: Note[];
}

export const NOTE_GROUPS: NoteGroup[] = [
  {
    id: 've',
    title: 'Vé và thẻ',
    notes: [
      {
        id: 'ic',
        title: 'Thẻ IC',
        text: 'Thẻ IC dùng cho JR trong vùng, metro, nhiều tàu tư và cửa hàng. Khi đi JR local qua ranh Suica–TOICA (Atami → Shizuoka ngày 5), mua vé giấy đúng chặng. Mỗi người một thẻ; điện thoại Android mua ngoài Nhật thường không hỗ trợ Mobile Suica.',
      },
      {
        id: 'taxi',
        title: 'Taxi',
        text: 'Không dùng taxi trong tuyến chính. Taxi ngắn để dành cho lúc trời xấu, chân mệt hoặc shuttle thay đổi. Night bus và tàu ngủ Sunrise không hợp tuyến này.',
      },
    ],
  },
  {
    id: 'hanh-ly',
    title: 'Hành lý và hoàn thuế',
    notes: [
      {
        id: 'forward',
        title: 'Gửi vali',
        text: 'Gửi một vali lớn dùng chung hai chặng: Tokyo → Ise (sáng ngày 3, nhận 22/10) và Kyoto → Osaka (sáng ngày 9, nhận 27/10). Cỡ 160 khoảng ¥3.000/chặng. Xác nhận khách sạn nhận kiện, ghi tên người đặt và ngày đến; giữ đồ cần dùng trong túi đi cùng.',
      },
      {
        id: 'tax',
        title: 'Hoàn thuế từ 1/11/2026',
        text: 'Trả giá có thuế ở cửa hàng, hoàn sau khi xác nhận hàng mang ra khỏi Nhật. Một hóa đơn phải đủ hàng để xác nhận — tách đồ mang về với đồ dùng trong chuyến. Thuế 10% tương ứng tối đa khoảng 9,09% giá gross trước phí.',
      },
      {
        id: 'weight',
        title: 'Cân hành lý',
        text: 'Giỏ mua sắm thêm khoảng 10–13 kg, chưa tính vali mới 3,3 kg. Mang túi gấp, zip bag, cân nhỏ; để trống một phần vali khi bay đi. Phí quá cân của hãng bay không nằm trong ngân sách này.',
      },
    ],
  },
  {
    id: 'onsen',
    title: 'Onsen',
    notes: [
      {
        id: 'mizunoto',
        title: 'Ở Mizunoto',
        text: 'Dùng phòng từ chiều: bồn riêng, đổi không gian ở bồn garden 貸切, ăn đúng lượt, rồi quay lại bồn tối hoặc sáng. Bồn garden miễn phí, ai tới khi trống dùng trước, không có khu vòi tắm đầy đủ — tắm sạch ở phòng trước.',
      },
      {
        id: 'public',
        title: 'Nhà tắm chung',
        text: 'Thường tách nam nữ. Tắm rửa trước khi ngâm, không để khăn xuống nước, nói nhỏ, không chụp người khác. Hỏi trước về hình xăm nếu có. Ngâm từng lượt ngắn, uống nước, tránh rượu trước khi tắm nóng.',
      },
      {
        id: 'roten',
        title: 'Bồn ngoài trời',
        text: '露天 nghĩa là ngoài trời, không hứa mọi góc đều kín. Kiểm tra rèm khi nhận phòng; thấy chưa yên tâm thì hỏi nhân viên.',
      },
    ],
  },
  {
    id: 'thoi-tiet',
    title: 'Lá đỏ và thời tiết',
    notes: [
      {
        id: 'foliage',
        title: 'Lá đỏ và thời tiết',
        text: 'Kyoto cuối tháng 10 thường chưa đỏ rực như ảnh tháng 11 — kỳ vọng cây xanh, vài mảng vàng đỏ sớm, và đổi màu rõ hơn ở vùng cao Hakone. Khoảng 18–29/10 tránh kỳ nghỉ Sports Day 11/10, Hakone rơi vào thứ Năm và Kyoto sau lễ Jidai Matsuri 22/10.',
      },
    ],
  },
];

export const noteGroup = (id: string) => NOTE_GROUPS.find((g) => g.id === id)!;

/** Station names worth knowing by sight: [romaji, kanji]. */
export const STATIONS_TO_KNOW: [string, string][] = [
  ['Iseshi', '伊勢市'],
  ['Ujiyamada', '宇治山田'],
  ['Toba', '鳥羽'],
  ['Kashikojima', '賢島'],
  ['Tambabashi', '丹波橋'],
  ['Chūshojima', '中書島'],
  ['Kowakudani', '小涌谷'],
  ['Kintetsu Nagoya', '近鉄名古屋'],
];

/** Scenario groups for the phrase launcher; ids come from research/phrases.json. */
export const SCENARIO_GROUPS: { title: string; ids: string[] }[] = [
  { title: 'Ăn uống', ids: ['table', 'order', 'shokken', 'ask-food', 'diet', 'izakaya', 'cafe', 'reserve', 'takeout', 'pay'] },
  { title: 'Đi lại', ids: ['ticket', 'platform', 'bus', 'taxi', 'ferry', 'locker', 'lost', 'directions'] },
  { title: 'Nơi ở', ids: ['checkin', 'forward', 'ryokan', 'onsen', 'room-problem', 'checkout'] },
  { title: 'Tham quan, mua sắm', ids: ['temple', 'kimono', 'shop', 'souvenir'] },
  { title: 'Chung, sức khoẻ', ids: ['greet', 'pharmacy', 'health', 'emergency'] },
];

/** Hotel hunting rules (Chỗ ở page). */
export const HUNT_STEPS: { title: string; text: string }[] = [
  { title: 'Giữ ryokan và Ise trước.', text: 'Tuyến phụ thuộc hai nơi này. Sau đó Kyoto, Tokyo, Osaka. Đặt loại có thể hủy khi lịch mở.' },
  { title: 'So cùng điều kiện.', text: 'Cùng ngày, hai người, cùng hạng phòng, cùng bữa ăn, cùng điều kiện hủy — trên trang chính thức, Booking hoặc Agoda, và Jalan.' },
  { title: 'Xem lại 90, 60, 30 ngày trước.', text: 'Đọc review mới nhất đúng cơ sở. Khi thấy early booking hoặc 連泊, tính tổng sau thuế cả 11 đêm.' },
  { title: 'Không đặt phòng một người.', text: 'Mỗi phòng tính cho hai người; phải có phòng tắm và WC riêng, không hút thuốc.' },
];

/** Places that hold a reservation: the replanner never drops them and treats their time as fixed. */
export const RESERVED = ['sushi-ten', 'menami', 'menzo', 'awa', 'hosekibako', 'wargo-gion'];
