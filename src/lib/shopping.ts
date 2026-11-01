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
    [/onitsuka|asics|abc-mart|moonstar|anello|porter/, 'shoes'],
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
  'slot-5-1': { start: '12:15', end: '12:50', after: 'kaizan', before: 'st-shimizu' },
  'slot-6-1': { start: '12:25' },
  'slot-7-1': { start: '14:00', end: '15:00' },
  'slot-8-2': { focus: 'Ippodo hōjicha gói 80 g ×6 (khoảng ¥1.080 mỗi gói, giá 2026); thử trà ở phòng trà Kaboku nếu còn chỗ.' },
  'slot-11-2': { start: '13:35', end: '14:30' },
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
export const SLOTS: Slot[] = [...plan.slots.filter((s) => !DROP.has(s.id)).map((s) => ({ ...s, ...(PATCH[s.id] ?? {}) })), ...EXTRA]
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
export const SOURCES = [...new Set([...(plan.sources ?? []), ...(itemsRaw.sources ?? [])])];

/** Slots whose stores sell what an item lists in `where` (chains or store ids). */
export function slotsFor(item: Item): Slot[] {
  const keys = new Set(item.where.map(chainKey));
  return SLOTS.filter((s) => s.stores.some((st) => keys.has(st.id) || keys.has(chainKey(st.store?.chain ?? st.category ?? ''))));
}

/** Catalogue items that can be bought in a slot. */
export function itemsFor(slot: Slot): Item[] {
  const chains = new Set(slot.stores.map((st) => chainKey(st.store?.chain ?? st.category ?? '')));
  const ids = new Set(slot.stores.map((st) => st.id));
  return CATEGORIES.flatMap((c) => c.items).filter((it) => it.where.some((w) => chains.has(chainKey(w)) || ids.has(w)));
}

export const BASKET_TOTAL = SHOPPING.reduce((t, i) => t + i.qty * i.unit, 0);
export const SHOP_BUDGET = BUDGET.find((b) => b.id === 'shop')?.yen ?? 0;
export const slotsOfDay = (n: number) => SLOTS.filter((s) => s.day === n);
