// Build-time view model for the "Trên tàu" page: each ride of the plan with its stations in
// order, what to look at on each side (research), where Fuji is in line of sight (terrain
// samples), and the moments to get ready to change or get off.
import { DAYS, ALT_DAYS, type Day } from '../data/days.ts';
import { RIDE_GEO } from '../data/rides.gen.ts';
import { RIDES_R } from '../data/enrich.gen.ts';
import { FUJI_TRACKS } from '../data/fuji.gen.ts';
import { legView, place, type LegView } from './trip.ts';

export type Side = 'left' | 'right' | 'both' | 'front' | 'down';

export interface RideStation {
  ja: string;
  en: string;
  km: number;
  /** the train stops here (or it is where you board, change or alight) */
  stop: boolean;
  marks: ('board' | 'alight' | 'transfer' | 'prev')[];
}

export interface RideEvent {
  side: Side;
  from: number; // index into stations
  to: number;
  what: string;
  tip?: string | null;
  fuji: boolean;
  /** computed from terrain rather than taken from research */
  computed?: boolean;
  src?: string;
}

export interface Ride {
  id: string;
  day: Day;
  at?: string;
  legs: LegView[];
  color: string;
  lineName: string;
  fromName: string;
  toName: string;
  km: number;
  min?: string;
  title: string;
  train?: string | null;
  seat?: string | null;
  stations: RideStation[];
  hidden: number; // stations passed without stopping that are not drawn
  events: RideEvent[];
  transfers: { at: string; text: string; idx: number }[];
  alight?: { prevSt: string; announce?: string; announceRomaji?: string; text?: string; idx: number } | null;
  onboard?: string | null;
  sources: string[];
  researched: boolean;
}

const SCENIC = new Set(['train', 'shinkansen', 'cable', 'ropeway', 'cruise', 'ferry']);

/** 大阪難波駅 (Kintetsu) → 大阪難波 */
const norm = (s: string) =>
  s
    .replace(/[（(].*?[）)]/g, '')
    .replace(/駅$/, '')
    .replace(/\s+/g, '')
    .trim();

// Stops of the services the plan uses, where the line has many stations the train runs through.
// Short rides and locals stop everywhere and need no list.
const STOPS: Record<string, string[]> = {
  keikyu: ['羽田空港第3ターミナル', '京急蒲田', '品川'],
  romancecar: ['新宿', '町田', '本厚木', '小田原', '箱根湯本'],
  kintetsu_nagoya: ['近鉄名古屋', '桑名', '近鉄四日市', '白子', '津', '松阪', '伊勢中川', '伊勢市'],
  shimakaze: ['鳥羽', '宇治山田', '伊勢市', '松阪', '大和八木', '京都'],
  kintetsu_nara: ['近鉄丹波橋', '新田辺', '大和西大寺', '新大宮', '近鉄奈良'],
  kintetsu_namba: ['近鉄奈良', '新大宮', '大和西大寺', '学園前', '生駒', '石切', '鶴橋', '大阪上本町', '近鉄日本橋', '大阪難波'],
  nankai: ['難波', '新今宮', '天下茶屋', '堺', '羽衣', '泉大津', '岸和田', '貝塚', '泉佐野', 'りんくうタウン', '関西空港'],
  fujiExcursion: ['新宿', '立川', '八王子', '大月', '都留文科大学前', '富士山', '富士急ハイランド', '河口湖'],
  hankyu: ['京都河原町', '烏丸', '大宮', '西院', '桂', '上桂', '松尾大社', '嵐山'],
};
/** Locals stop at every station: draw them all. */
const LOCAL = new Set(['tokaido', 'hakoneTozan', 'keihinTohoku', 'yamanote', 'chuoSobu', 'keihan', 'fujikyu']);
const stopsFor = (l: LegView): string[] | null => {
  if (l.line === 'kintetsu' && l.from === 'st-kintetsu-nagoya') return STOPS.kintetsu_nagoya;
  if (l.line === 'kintetsu' && l.from === 'st-kintetsu-tambabashi') return STOPS.kintetsu_nara;
  if (l.line === 'kintetsu' && l.from === 'st-kintetsu-nara') return STOPS.kintetsu_namba;
  return STOPS[l.line] ?? null;
};

interface RRide {
  id: string;
  day: number | string;
  line?: string;
  from: string;
  to: string;
  train?: string;
  seat?: string;
  views?: { side: Side; fromSt?: string; toSt?: string; what: string; fuji?: boolean; tip?: string | null; src?: string }[];
  transfers?: { at: string; text: string }[];
  alight?: { prevSt: string; announce?: string; announceRomaji?: string; text?: string };
  onboard?: string | null;
  sources?: string[];
}

/** The stations a leg passes, in order: N02 for rail, the two ends for boats and cable cars. */
function legStations(l: LegView): { ja: string; en: string; km: number }[] {
  const g = RIDE_GEO[l.id];
  if (g) return g.stations.map((s) => ({ ja: s.ja, en: s.en ?? s.ja, km: s.km }));
  const a = place(l.from);
  const b = place(l.to);
  return [
    { ja: a.ja ?? a.name, en: a.name, km: 0 },
    { ja: b.ja ?? b.name, en: b.name, km: l.km },
  ];
}

/** Fuji line-of-sight runs on one side, from the terrain samples of this leg. */
function fujiRuns(l: LegView) {
  const t = FUJI_TRACKS.find((x) => x.id === l.id);
  if (!t) return [];
  const skip = l.line === 'romancecar' ? 30 : 0; // Tokyo's buildings hide it whatever the terrain says
  const runs: { side: 'left' | 'right'; a: number; b: number; dist: number }[] = [];
  for (const s of t.samples) {
    if (!s.v || s.km < skip || s.dist > 75 || (s.side !== 'left' && s.side !== 'right')) continue;
    const last = runs.at(-1);
    if (last && last.side === s.side && s.km - last.b <= 3.1) last.b = s.km;
    else runs.push({ side: s.side, a: s.km, b: s.km, dist: s.dist });
  }
  return runs.filter((r) => r.b - r.a >= 1.5);
}

function build(day: Day, legs: LegView[], r: RRide | null, at?: string): Ride {
  // stations of all legs, end to end, km continuing across legs
  const stations: RideStation[] = [];
  let offset = 0;
  for (const l of legs) {
    const st = legStations(l);
    st.forEach((s, i) => {
      if (i === 0 && stations.length && norm(stations.at(-1)!.ja) === norm(s.ja)) return;
      stations.push({ ja: s.ja, en: s.en, km: Math.round((offset + s.km) * 10) / 10, stop: false, marks: [] });
    });
    offset += l.km;
  }
  const find = (name?: string | null) => {
    if (!name) return -1;
    const n = norm(name);
    let i = stations.findIndex((s) => norm(s.ja) === n);
    if (i < 0) i = stations.findIndex((s) => norm(s.ja).includes(n) || n.includes(norm(s.ja)));
    return i;
  };
  const stopList = legs.length === 1 ? stopsFor(legs[0]) : null;
  const shown = new Set<number>([0, stations.length - 1]);
  const local = legs.every((l) => LOCAL.has(l.line) || (l.line === 'kintetsu' && l.from === 'st-iseshi'));
  if (stopList) for (const n of stopList) shown.add(find(n));
  else if (local || stations.length <= 14) stations.forEach((_, i) => shown.add(i));
  for (const s of stopList ? stopList.map(find) : [...shown]) if (s >= 0) stations[s].stop = true;
  stations[0].marks.push('board');
  stations.at(-1)!.marks.push('alight');
  stations[0].stop = stations.at(-1)!.stop = true;
  // legs joined inside one ride: the joints are changes
  let acc = 0;
  for (const l of legs.slice(0, -1)) {
    acc += l.km;
    const i = stations.findIndex((s) => Math.abs(s.km - acc) < 0.6);
    if (i > 0) {
      stations[i].marks.push('transfer');
      stations[i].stop = true;
      shown.add(i);
    }
  }

  const events: RideEvent[] = [];
  for (const v of r?.views ?? []) {
    let a = find(v.fromSt);
    let b = find(v.toSt);
    if (a < 0 && b < 0) continue;
    if (a < 0) a = b;
    if (b < 0) b = a;
    if (a > b) [a, b] = [b, a];
    shown.add(a);
    shown.add(b);
    events.push({ side: v.side, from: a, to: b, what: v.what, tip: v.tip, fuji: Boolean(v.fuji), src: v.src });
  }
  // terrain says Fuji is in line of sight here; add it unless research already covers that stretch
  let base = 0;
  for (const l of legs) {
    for (const run of fujiRuns(l)) {
      const near = (km: number) => stations.reduce((best, s, i) => (Math.abs(s.km - km) < Math.abs(stations[best].km - km) ? i : best), 0);
      const a = near(base + run.a);
      const b = near(base + run.b);
      const covered = events.some((e) => e.fuji && e.side === run.side && e.from <= b && e.to >= a);
      if (covered) continue;
      shown.add(a);
      shown.add(b);
      events.push({ side: run.side, from: a, to: b, what: `Fuji trong tầm nhìn nếu trời quang, cách đỉnh khoảng ${Math.round(run.dist)} km.`, fuji: true, computed: true });
    }
    base += l.km;
  }

  const transfers = (r?.transfers ?? []).map((t) => ({ ...t, idx: find(t.at) })).filter((t) => t.idx >= 0);
  for (const t of transfers) {
    stations[t.idx].marks.push('transfer');
    stations[t.idx].stop = true;
    shown.add(t.idx);
  }
  let alight: Ride['alight'] = null;
  if (r?.alight?.prevSt) {
    let idx = find(r.alight.prevSt);
    if (idx < 0 || idx >= stations.length - 1) idx = Math.max(0, [...shown].filter((i) => i < stations.length - 1 && stations[i].stop).sort((x, y) => y - x)[0] ?? 0);
    stations[idx].marks.push('prev');
    shown.add(idx);
    alight = { ...r.alight, idx };
  }

  // keep only the drawn stations, remapping indices
  const keep = [...shown].filter((i) => i >= 0).sort((x, y) => x - y);
  const remap = new Map(keep.map((i, j) => [i, j]));
  const drawn = keep.map((i) => stations[i]);
  const first = legs[0];
  const last = legs.at(-1)!;
  return {
    id: r?.id ?? first.id,
    day,
    at,
    legs,
    color: first.color,
    lineName: legs.length > 1 && legs.some((l) => l.lineName !== first.lineName) ? [...new Set(legs.map((l) => l.lineName))].join(' + ') : first.lineName,
    fromName: first.fromName,
    toName: last.toName,
    km: Math.round(legs.reduce((t, l) => t + l.km, 0) * 10) / 10,
    min: legs.length === 1 ? first.min : undefined,
    title: r?.line ?? first.lineName,
    train: r?.train ?? null,
    seat: r?.seat ?? null,
    stations: drawn,
    hidden: stations.length - drawn.length,
    events: events.map((e) => ({ ...e, from: remap.get(e.from)!, to: remap.get(e.to)! })),
    transfers: transfers.map((t) => ({ ...t, idx: remap.get(t.idx)! })),
    alight: alight ? { ...alight, idx: remap.get(alight.idx)! } : null,
    onboard: r?.onboard ?? null,
    sources: r?.sources ?? [],
    researched: Boolean(r),
  };
}

/** Every scenic leg of a day, grouped into the rides the research describes. */
function ridesOf(day: Day): Ride[] {
  const out: Ride[] = [];
  const items = day.items;
  const research = (RIDES_R as RRide[]).filter((r) => String(r.day) === (day.id ?? String(day.n)));
  const used = new Set<string>();
  const moves = items.flatMap((it) => (it.type === 'move' ? [{ at: it.at, l: legView(it.leg) }] : [])).filter(({ l }) => SCENIC.has(l.mode));
  for (const r of research) {
    // first leg that boards at the research's "from", then legs until one reaches its "to"
    const fromN = norm(r.from);
    const toN = norm(r.to);
    const has = (l: LegView, n: string) => legStations(l).some((s) => norm(s.ja) === n || norm(s.ja).includes(n) || n.includes(norm(s.ja)));
    const start = moves.findIndex(({ l }) => !used.has(l.id) && has(l, fromN));
    if (start < 0) continue;
    const chosen = [];
    for (let i = start; i < moves.length; i++) {
      chosen.push(moves[i]);
      if (has(moves[i].l, toN)) break;
    }
    chosen.forEach(({ l }) => used.add(l.id));
    out.push(build(day, chosen.map((c) => c.l), r, chosen[0].at));
  }
  for (const { at, l } of moves) {
    if (used.has(l.id) || (l.km < 3 && l.mode !== 'cable')) continue;
    out.push(build(day, [l], null, at));
  }
  const order = (r: Ride) => items.findIndex((it) => it.type === 'move' && it.leg.id === r.legs[0].id);
  return out.sort((a, b) => order(a) - order(b));
}

export const RIDES = DAYS.flatMap(ridesOf);
export const ALT_RIDES = ALT_DAYS.flatMap(ridesOf);
