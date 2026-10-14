// Build-time view models that join days, places, lines and geometry.
import { DAYS, legsOf, foodTotal, type Day, type Leg, type Stop } from '../data/days.ts';
import { LINES, MODE_LABEL, type Mode } from '../data/lines.ts';
import { place, allPlaces, hasPlace, type Place } from '../data/catalog.ts';
import { GEO } from '../data/geo.gen.ts';
import { DETOURS } from '../data/detours.gen.ts';
import { decodePolyline, boundsOf, haversineKm, nearestOnLine, type LatLng } from './geo.ts';
import type { Pin, RouteLeg } from './map.ts';

export { DAYS, place, LINES, MODE_LABEL };

export const url = (path = '') => `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
/** Remote photos stay absolute; self-hosted ones live under the site base. */
export const imgSrc = (src: string) => (/^https?:/.test(src) ? src : url(src));

export interface LegView extends Leg {
  mode: Mode;
  color: string;
  lineName: string;
  km: number;
  pts: LatLng[];
  fromName: string;
  toName: string;
}

export function legView(leg: Leg): LegView {
  const line = LINES[leg.line];
  const g = GEO[leg.id];
  const pts = g ? decodePolyline(g.p) : [];
  return {
    ...leg,
    mode: line.mode,
    color: line.color,
    lineName: line.name,
    km: g?.km ?? 0,
    pts,
    fromName: place(leg.from).name,
    toName: place(leg.to).name,
  };
}

export const routeLeg = (l: LegView, day?: number): RouteLeg => ({ id: l.id, p: GEO[l.id]?.p ?? '', color: l.color, mode: l.mode, day });

/** Numbered stops of a day: each distinct place in order of first appearance. */
export function stopsOf(day: Day) {
  const order = new Map<string, number>();
  for (const item of day.items) {
    if (item.type === 'stop' && item.place && !order.has(item.place)) {
      const p = place(item.place);
      if (p.kind !== 'station') order.set(item.place, order.size + 1);
    }
  }
  return order;
}

/** Straight-line reach from wherever the day is on foot; further sights only when research tied them to the day. */
const ALONG_KM = 1.2;

/** Where a detour would start: a place the day stops at, or a point on one of its walks. */
export interface Origin {
  pt: LatLng;
  label: string;
  onWalk: boolean;
}

export type Detour = (typeof DETOURS)[string]; // origin → sight, encoded polyline [lat, lng]

/** "ga Kanda", but piers and airports keep their own word. */
export const stationLabel = (name: string) => (/^(Bến|Sân bay|Ga )/.test(name) ? name : `ga ${name}`);

export interface Along {
  p: Place;
  km: number; // straight line from the origin
  from: Origin;
  detour?: Detour;
}

function footOrigins(day: Day, legs: LegView[]) {
  const places: Origin[] = [];
  const ids = new Set<string>();
  const add = (id: string) => {
    if (ids.has(id)) return;
    ids.add(id);
    const p = place(id);
    places.push({ pt: [p.lat, p.lng], label: p.kind === 'station' ? stationLabel(p.name) : p.name, onWalk: false });
  };
  // on a day that changes hotel, the morning walk out of last night's one is just checking out
  const leaving = DAYS[day.n - 2]?.stay;
  const left = leaving && leaving !== day.stay ? leaving : undefined;
  for (const item of day.items) if (item.type === 'stop' && item.place && item.place !== left && place(item.place).kind !== 'station') add(item.place);
  if (day.stay) add(day.stay);
  const walks = legs.filter((l) => l.mode === 'walk' && l.pts.length > 1 && l.from !== left && l.to !== left);
  // stations count once you walk out of them
  for (const l of walks) for (const id of [l.from, l.to]) add(id);
  return { places, walks };
}

function nearestOrigin(at: LatLng, { places, walks }: ReturnType<typeof footOrigins>) {
  let best: { km: number; from: Origin } = { km: Infinity, from: { pt: at, label: '', onWalk: false } };
  for (const o of places) {
    const km = haversineKm(at, o.pt);
    if (km < best.km) best = { km, from: o };
  }
  for (const l of walks) {
    const near = nearestOnLine(at, l.pts);
    // a walk only wins when the sight lies beside it, not near either end (those are places already)
    if (near.km < best.km - 0.05) best = { km: near.km, from: { pt: near.pt, label: `${l.fromName} → ${l.toName}`, onWalk: true } };
  }
  return best;
}

/** Sights the research tied to this day, or within a short walk of where the day is on foot, not already in the plan. */
export function alongCandidates(day: Day, legs: LegView[]): Along[] {
  const planned = new Set(day.items.flatMap((i) => (i.type === 'stop' && i.place ? [i.place] : [])));
  const origins = footOrigins(day, legs);
  return allPlaces()
    .filter((p) => (p.kind === 'sight' || p.kind === 'shop') && !planned.has(p.id))
    .filter((p) => p.role === 'along' || p.role === 'detour' || p.day === day.n)
    .filter((p) => p.role !== 'alt')
    .map((p) => ({ p, ...nearestOrigin([p.lat, p.lng], origins), detour: DETOURS[`${day.n}.${p.id}`] }))
    .filter(({ p, km }) => p.day === day.n || km < ALONG_KM);
}

export function alongOf(day: Day, legs: LegView[]): Along[] {
  return (
    alongCandidates(day, legs)
      // a long ride there is an outing of its own, not a detour
      .filter(({ detour }) => !(detour?.mode === 'car' && detour.min > 25))
      .sort((a, b) => (a.detour?.km ?? a.km) - (b.detour?.km ?? b.km))
  );
}

export interface DayView {
  day: Day;
  legs: LegView[];
  stops: Map<string, number>;
  pins: Pin[];
  bounds: [[number, number], [number, number]];
  km: { rail: number; walk: number; road: number; water: number; air: number };
  food: number;
  along: Along[];
}

export function dayView(day: Day): DayView {
  const legs = legsOf(day).map(legView);
  const stops = stopsOf(day);
  const along = alongOf(day, legs);
  const pins: Pin[] = [];
  const seen = new Set<string>();
  for (const [id, n] of stops) {
    const p = place(id);
    pins.push({ id, lat: p.lat, lng: p.lng, kind: p.kind as Pin['kind'], label: p.name, n, day: day.n });
    seen.add(id);
  }
  if (day.stay && !seen.has(day.stay)) {
    const p = place(day.stay);
    pins.push({ id: p.id, lat: p.lat, lng: p.lng, kind: 'stay', label: p.name, day: day.n });
    seen.add(p.id);
  }
  for (const l of legs) {
    for (const id of [l.from, l.to]) {
      if (seen.has(id)) continue;
      const p = place(id);
      if (p.kind === 'station') {
        pins.push({ id, lat: p.lat, lng: p.lng, kind: 'station', label: p.name, day: day.n });
        seen.add(id);
      }
    }
  }
  for (const { p } of along) {
    if (seen.has(p.id)) continue;
    pins.push({ id: p.id, lat: p.lat, lng: p.lng, kind: 'along', label: p.name, day: day.n });
    seen.add(p.id);
  }
  const pts = legs.flatMap((l) => l.pts);
  const km = { rail: 0, walk: 0, road: 0, water: 0, air: 0 };
  for (const l of legs) {
    if (['train', 'subway', 'shinkansen', 'cable'].includes(l.mode)) km.rail += l.km;
    else if (l.mode === 'walk') km.walk += l.km;
    else if (l.mode === 'bus' || l.mode === 'shuttle') km.road += l.km;
    else if (l.mode === 'ferry' || l.mode === 'cruise') km.water += l.km;
    else km.air += l.km;
  }
  return {
    day,
    legs,
    stops,
    pins,
    bounds: boundsOf(pts.length ? pts : pins.map((p) => [p.lat, p.lng] as LatLng)),
    km,
    food: foodTotal(day.meals),
    along,
  };
}

export const DAY_VIEWS = DAYS.map(dayView);

export function tripTotals() {
  const t = { rail: 0, walk: 0, road: 0, water: 0, air: 0, legs: 0 };
  for (const v of DAY_VIEWS) {
    for (const k of ['rail', 'walk', 'road', 'water', 'air'] as const) t[k] += v.km[k];
    t.legs += v.legs.length;
  }
  return t;
}

export const fmtKm = (km: number) => (km < 1 ? `${Math.round(km * 1000)} m` : `${km.toLocaleString('vi-VN', { maximumFractionDigits: km < 10 ? 1 : 0 })} km`);
export const fmtYen = (n: number) => `¥${n.toLocaleString('vi-VN')}`;

export const dateLabel = (iso: string) => {
  const [, m, d] = iso.split('-').map(Number);
  return `${d} tháng ${m}`;
};
export const shortDate = (iso: string) => {
  const [, m, d] = iso.split('-').map(Number);
  return `${d}/${m}`;
};

export type { Stop, Place, LatLng };
export { hasPlace };

/** Chapters = consecutive nights in the same hotel. */
export const CHAPTERS = [
  { id: 'tokyo', name: 'Tokyo', nights: 3, days: [1, 2, 3], stay: 'resol-akihabara', short: 'RESOL Akihabara', color: '#F39700' },
  { id: 'hakone', name: 'Hakone', nights: 1, days: [4], stay: 'mizunoto', short: 'Mizunoto', color: '#D23A3A' },
  { id: 'ise', name: 'Ise', nights: 2, days: [5, 6], stay: 'era-ise', short: 'ERA Ise', color: '#C8323F' },
  { id: 'kyoto', name: 'Kyoto', nights: 3, days: [7, 8, 9], stay: 'cross-kyoto', short: 'Cross Hotel', color: '#1E8A55' },
  { id: 'osaka', name: 'Osaka', nights: 2, days: [10, 11, 12], stay: 'forza-osaka', short: 'Forza Namba', color: '#E15A26' },
];

export const allPlacesOf = (kind: Place['kind']) => allPlaces().filter((p) => p.kind === kind);

/** Where each place is used in the plan: day, time and a global order for sorting. */
export function usesOf() {
  const uses = new Map<string, { day: number; at?: string; order: number }[]>();
  let order = 0;
  for (const d of DAYS) {
    for (const item of d.items) {
      order++;
      if (item.type !== 'stop' || !item.place) continue;
      const list = uses.get(item.place) ?? [];
      if (!list.some((u) => u.day === d.n)) list.push({ day: d.n, at: item.at, order });
      uses.set(item.place, list);
    }
    for (const id of d.alt?.places ?? []) {
      const list = uses.get(id) ?? [];
      if (!list.some((u) => u.day === d.n)) list.push({ day: d.n, order: order + 0.5 });
      uses.set(id, list);
    }
  }
  return uses;
}
