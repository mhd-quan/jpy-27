// Build-time view models that join days, places, lines and geometry.
import { DAYS, legsOf, foodTotal, type Day, type Leg, type Stop } from '../data/days.ts';
import { LINES, MODE_LABEL, type Mode } from '../data/lines.ts';
import { place, allPlaces, hasPlace, type Place } from '../data/catalog.ts';
import { GEO } from '../data/geo.gen.ts';
import { decodePolyline, boundsOf, distanceToLineKm, type LatLng } from './geo.ts';
import type { Pin, RouteLeg } from './map.ts';

export { DAYS, place, LINES, MODE_LABEL };

export const url = (path = '') => `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;

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

const ALONG_KM = 1.6;

/** Sights the research tied to this day, or that sit close to today's path, not already in the plan. */
export function alongOf(day: Day, legs: LegView[]) {
  const planned = new Set(day.items.flatMap((i) => (i.type === 'stop' && i.place ? [i.place] : [])));
  const path = legs.filter((l) => l.mode !== 'shinkansen').flatMap((l) => l.pts);
  return allPlaces()
    .filter((p) => (p.kind === 'sight' || p.kind === 'shop') && !planned.has(p.id))
    .filter((p) => p.role === 'along' || p.role === 'detour' || p.day === day.n)
    .map((p) => ({ p, km: path.length ? distanceToLineKm([p.lat, p.lng], path) : Infinity }))
    .filter(({ p, km }) => p.day === day.n || km < ALONG_KM)
    .filter(({ p }) => p.role !== 'alt')
    .sort((a, b) => a.km - b.km);
}

export interface DayView {
  day: Day;
  legs: LegView[];
  stops: Map<string, number>;
  pins: Pin[];
  bounds: [[number, number], [number, number]];
  km: { rail: number; walk: number; road: number; water: number; air: number };
  food: number;
  along: { p: Place; km: number }[];
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
  { id: 'tokyo', name: 'Tokyo', nights: 3, days: [1, 2, 3], stay: 'resol-akihabara', color: '#F39700' },
  { id: 'hakone', name: 'Hakone', nights: 1, days: [4], stay: 'mizunoto', color: '#D23A3A' },
  { id: 'ise', name: 'Ise', nights: 2, days: [5, 6], stay: 'era-ise', color: '#C8323F' },
  { id: 'kyoto', name: 'Kyoto', nights: 3, days: [7, 8, 9], stay: 'cross-kyoto', color: '#1E8A55' },
  { id: 'osaka', name: 'Osaka', nights: 2, days: [10, 11, 12], stay: 'forza-osaka', color: '#E15A26' },
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
