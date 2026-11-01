// Build-time view model for the shopping page: slots tied to days, stores as catalog places,
// and the item catalogue linked to the slots where each item can be bought.
import { SHOP_PLAN, SHOP_ITEMS } from '../data/enrich.gen.ts';
import { SHOP_ROUTES } from '../data/shopping.gen.ts';
import { WALK_SHOPS } from '../data/walk.gen.ts';
import { SHOPPING, BUDGET } from '../data/trip.ts';
import { DAYS } from '../data/days.ts';
import { hasPlace, place, type Place } from './trip.ts';

export interface Slot {
  id: string;
  day: number;
  start?: string;
  end?: string;
  city?: string;
  area?: string;
  after?: string;
  before?: string;
  stores: Place[];
  focus?: string;
  why?: string;
  skipIf?: string | null;
  route?: { p: string[]; km: number; min: number };
}

export interface Item {
  id: string;
  name: string;
  ja?: string | null;
  brand?: string;
  yen?: number | null;
  yenNote?: string | null;
  why?: string;
  tip?: string | null;
  where: string[];
  weightG?: number | null;
  src?: string;
  category: string;
}

/** Chain names as the item research writes them → the store research's chain ids. */
export function chainKey(raw: string): string {
  const s = raw.toLowerCase().replace(/[\s._]+/g, '-');
  const table: [RegExp, string][] = [
    [/uniqlo/, 'uniqlo'],
    [/^gu$|^gu-|g\.u/, 'gu'],
    [/muji|無印/, 'muji'],
    [/workman/, 'workman'],
    [/shimamura|しまむら/, 'shimamura'],
    [/3coins|3-coins|three-coins/, '3coins'],
    [/daiso|standard-products|threeppy|seria|can-do/, 'daiso'],
    [/donki|don-quijote|don-quixote|ドン/, 'donki'],
    [/matsu|kiyoshi|sundrug|welcia|tsuruha|sugi|cocokara|drug/, 'drugstore'],
    [/loft/, 'loft'],
    [/hands/, 'hands'],
    [/yodobashi/, 'yodobashi'],
    [/bic/, 'bic'],
    [/takashimaya|mitsukoshi|daimaru|hankyu|hanshin|isetan|depachika|depart/, 'depachika'],
    [/kappabashi|doguyasuji|dōguyasuji|kitchen/, 'kitchen'],
    [/2nd-street|second-street|book-?off|kindal|vintage|thrift|used/, 'vintage'],
    [/pokemon|pokémon|nintendo|mandarake|super-potato|gachapon|tamiya|animate|hobby|kiddy/, 'hobby'],
    [/anello|porter|links-umeda/, 'bags'],
    [/onitsuka|asics|abc-mart|moonstar/, 'shoes'],
    [/maruzen/, 'maruzen'],
    [/nakagawa|kamawanu|eirakuya|ippodo|shoyeido|craft|tenugui|furoshiki/, 'craft'],
    [/kitkat|chocolatory|tokyo-station|airport|kix|duty/, 'other'],
  ];
  for (const [re, k] of table) if (re.test(s)) return k;
  return s;
}

const plan = SHOP_PLAN as { stores: any[]; slots: any[]; rules?: string[]; sources?: string[] };
const itemsRaw = SHOP_ITEMS as { categories: any[]; chains: any[]; taxFree?: string; sources?: string[] };

// Planner's edits on top of the store research (kept here so research/ stays as collected):
// a third slot on arrival night and a second Ise drugstore run are too much; the Asakusa block is
// really two things — Nakamise while at Sensō-ji, and Kappabashi only if it replaces Sumida + Umezono.
// Hakone-Yumoto has no time on day 4: the train arrives 9:22 and the bus leaves minutes later.
// Times follow the re-timed plan (scripts/check-plan.mjs).
const DROP = new Set(['slot-1-3', 'slot-6-2', 'slot-4-1']);
const PATCH: Record<string, Record<string, unknown>> = {
  'slot-2-1': { start: '13:45', end: '14:30', area: 'Nakamise, Asakusa', stores: ['sh-nakamise'], focus: 'Omamori và quà nhỏ nhẹ dọc Nakamise trong lúc đi Sensō-ji; rẽ vào các phố phía sau cho bớt đông.', skipIf: null },
  'slot-2-2': { start: '16:35' },
  'slot-2-3': { stores: ['sh-hands-be-atre-akiba', 'sh-donki-akihabara', 'sh-matsukiyo-iwamotocho', 'sh-yodobashi-akiba', 'sh-daiso-yodobashi-akiba', 'sh-muji-akiba-trim'] },
  'slot-8-3': { stores: ['sh-daimaru-kyoto', 'sh-ippodo-daimaru-kyoto', 'sh-hands-kyoto', 'sh-muji-kyoto-bal', 'sh-teramachi-kyogoku'] },
  'slot-11-3': { stores: ['sh-hands-shinsaibashi', 'sh-muji-shinsaibashi-parco', 'sh-anello-shinsaibashi', 'sh-donki-dotonbori-midosuji'] },
  'slot-9-1': { start: '13:30', end: '14:30', why: 'Ăn trưa ở Yoshimura xong khoảng 12:50 thì đi Hankyu sớm hơn lịch, khoảng 13:00: có gần một giờ ở Shijō trước khi sang Fushimi.', skipIf: 'Muốn dạo Arashiyama tới 14:00 như lịch.' },
  'slot-10-1': { focus: 'Khăn kaya fukin ×6 (khoảng ¥550 mỗi chiếc, giá 2026), đồ gia dụng nhỏ làm tay.' },
  'slot-5-1': { start: '12:15', end: '12:50', after: 'kaizan', before: 'st-shimizu' },
  'slot-6-1': { start: '12:25' },
  'slot-7-1': { start: '14:00', end: '15:00' },
  'slot-8-2': { focus: 'Ippodo hōjicha gói 80 g ×6 (khoảng ¥1.080 mỗi gói, giá 2026); thử trà ở phòng trà Kaboku nếu còn chỗ.' },
  'slot-11-2': { start: '13:35', end: '14:30' },
};
// Shorter reasons: store hours already show on each store, so the reason keeps only what the
// plan depends on (luggage, the next fixed time, the order to walk in).
const TEXT: Record<string, Record<string, unknown>> = {
  'slot-1-1': { why: '18/10 là thứ Hai, 2k540 vẫn mở.', skipIf: 'Phải bỏ Kanda Myōjin mới đủ 90 phút; giữ Kanda Myōjin thì chỉ ghé 2k540 và Ameyoko, hoặc bỏ cả khung nếu quá mệt vì bay.' },
  'slot-1-2': { why: 'Vali lớn đi Ise sáng ngày 3, nên mua tối nay hoặc tối mai. UNIQLO và GU cùng tòa, vài bước từ Yamabe.' },
  'slot-2-1': { why: undefined },
  'slot-2-2': { why: 'Mitsukoshi đóng 19:00, nên ghé trước bữa tối ở Tamai.' },
  'slot-2-3': { why: 'Ngay cạnh hotel. Mua tối nay để kịp bỏ vào vali gửi trước 8:00 ngày 3.' },
  'slot-3-1': { why: 'Sushi lúc 11:00, còn khoảng 50 phút. Từ đây đồ mua nằm trong túi mang theo, vali lớn đã đi Ise.' },
  'slot-3-2': { why: 'Theo thứ tự Meiji Jingū → UNIQLO Harajuku → Omotesandō → 3COINS → Cat Street → GU, Loft, PARCO ở Udagawachō, rồi Toritake lúc 17:30.' },
  'slot-3-3': { why: 'Về Kanda bằng Ginza Line mất 25 phút, nên chọn một điểm là đủ.' },
  'slot-5-1': { why: 'Cạnh Kaizan, 3 phút từ ga Shimizu.', skipIf: 'Bỏ nếu lịch tàu dày.' },
  'slot-5-2': { why: 'Đổi từ JR sang Kintetsu mất 15–20 phút đi bộ.' },
  'slot-5-3': { why: 'Đi 10 phút từ Butasute hoặc ERA Ise.' },
  'slot-6-1': { why: 'Nằm giữa Fukusuke và Akafuku, không thêm quãng đường.' },
  'slot-7-2': { why: 'Cách hotel vài phút; Menami lúc 19:30 nên chỉ còn khoảng 40 phút.' },
  'slot-8-1': { why: 'Thứ Hai mở, thứ Ba (ngày 9) đóng.' },
  'slot-8-2': { why: 'Honten đóng 17:00. Rời Ippodo trước 15:30 để tới Yamamoto Menzō trước 16:00.' },
  'slot-8-3': { why: 'Tối ngày 8 không có bữa tối cố định. Mua chừng mực vì vali còn đi Osaka sáng mai.' },
  'slot-9-2': { why: 'Matsumoto Kiyoshi Kiyamachi nằm trên đường về từ Sanjō.' },
  'slot-10-1': { why: 'Hōsekibako 15:00 là mốc cố định, giữ đúng giờ.' },
  'slot-10-3': { why: 'Mua đồ nhỏ tối nay để ngày 11 dành cho đồ nặng.' },
  'slot-11-1': { why: 'Vali đã ở hotel, cân thử lúc 16:55, nên đồ nặng mua từ đây. 551 Hōrai nằm giữa Dōguyasuji và Takashimaya.' },
  'slot-11-2': { why: 'Hankyu và Loft đóng 20:00 nên không gấp.' },
  'slot-11-3': { why: 'Tahei 17:15 xong khoảng 18:45. Mua vali S trước khi cân thử hành lý ngày mai.' },
  'slot-12-1': { focus: 'Chốt cân vali, mua nốt đồ cần thiết trước khi ra Nankai Namba.', why: 'Giữ biên lai tax-free cùng một chỗ.' },
  'slot-12-2': { focus: 'Quà còn thiếu và đồ cần qua hải quan tax-free.', why: 'Hàng tax-free phải qua hải quan trước khi ký gửi, nên đến sớm.' },
};
const EXTRA: any[] = [
  {
    id: 'slot-2-1b',
    day: 2,
    start: '14:30',
    end: '15:45',
    city: 'Tokyo',
    area: 'Kappabashi',
    after: 'sensoji',
    before: 'st-asakusa',
    stores: ['sh-kappabashi'],
    focus: 'Phố đồ bếp: bát nhỏ, đũa, mẫu đồ ăn nhựa. Chỉ xem và mua món nhẹ; đồ gốm nặng để Dōguyasuji ngày 11.',
    why: 'Thay cho bờ sông Sumida và Umezono nếu thích đồ bếp hơn; cách Sensō-ji khoảng 15 phút đi bộ.',
    skipIf: 'Giữ Sumida và Umezono như lịch.',
  },
];
export const SLOTS: Slot[] = [...plan.slots.filter((s) => !DROP.has(s.id)).map((s) => ({ ...s, ...(PATCH[s.id] ?? {}), ...(TEXT[s.id] ?? {}) })), ...EXTRA]
  .map((s) => ({
    ...s,
    day: Number(s.day),
    stores: (s.stores ?? []).filter(hasPlace).map(place),
    route: SHOP_ROUTES[s.id] && { ...SHOP_ROUTES[s.id], min: WALK_SHOPS[s.id]?.min ?? SHOP_ROUTES[s.id].min },
  }))
  .filter((s) => s.day >= 1 && s.day <= DAYS.length)
  .sort((a, b) => a.day - b.day || String(a.start).localeCompare(String(b.start)));

export const STORES: Place[] = plan.stores.filter((s) => hasPlace(s.id)).map((s) => place(s.id));

export const CATEGORIES: { id: string; vi: string; items: Item[] }[] = itemsRaw.categories.map((c) => ({
  id: c.id,
  vi: c.vi,
  items: (c.items ?? []).map((it: any) => ({ ...it, where: (it.where ?? []).map(String), category: c.id })),
}));
export const CHAINS = itemsRaw.chains ?? [];
export const TAX_FREE = itemsRaw.taxFree ?? null;
export const RULES = plan.rules ?? [];

// Which stores sell an item. A brand with its own shop on the route (Ippodo, Nakagawa Masashichi,
// anello, Onitsuka Tiger…) is bought there and nowhere else; otherwise chains match by kind.
const storeKey = (st: Place) => {
  const k = chainKey(st.store?.chain ?? st.category ?? '');
  if (k !== 'other' && k !== 'craft' && k !== 'street' && k !== 'market') return k;
  const byName = chainKey(`${st.id} ${st.name}`);
  if (/links-umeda|anello/i.test(st.id + st.name)) return 'bags';
  if (/abc-mart|onitsuka|asics/i.test(st.id + st.name)) return 'shoes';
  return byName;
};
const brandToken = (it: Item) =>
  (it.brand ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, ' ')
    .trim()
    .split(/\s+/)[0] ?? '';
const ownShop = (it: Item) => {
  const t = brandToken(it);
  return t.length >= 4 ? STORES.filter((st) => `${st.id} ${st.name}`.toLowerCase().includes(t)) : [];
};
// sweets sold only in their home region (no Tokyo Banana in Osaka department stores)
const TOKYO_ONLY = /tokyo banana|東京ばな奈|shiroi koibito|白い恋人/i;
function sells(st: Place, it: Item, slot?: Slot) {
  if (slot && TOKYO_ONLY.test(`${it.name} ${it.ja ?? ''}`) && !/tokyo/i.test(slot.city ?? '')) return false;
  const own = ownShop(it);
  if (own.length) return own.includes(st);
  const keys = new Set(it.where.map(chainKey));
  // the bag brands in the catalogue sit under "shoes-bags"
  if (keys.has('shoes') && /bag|túi|backpack|balo/i.test(`${it.name} ${it.ja ?? ''}`)) keys.add('bags');
  return keys.has(st.id) || keys.has(storeKey(st));
}

/** Slots whose stores sell the item. */
export function slotsFor(item: Item): Slot[] {
  return SLOTS.filter((s) => s.stores.some((st) => sells(st, item, s)));
}

/** Catalogue items that can be bought in a slot. */
export function itemsFor(slot: Slot): Item[] {
  return CATEGORIES.flatMap((c) => c.items).filter((it) => slot.stores.some((st) => sells(st, it, slot)));
}

export const BASKET_TOTAL = SHOPPING.reduce((t, i) => t + i.qty * i.unit, 0);
export const SHOP_BUDGET = BUDGET.find((b) => b.id === 'shop')?.yen ?? 0;
export const slotsOfDay = (n: number) => SLOTS.filter((s) => s.day === n);
