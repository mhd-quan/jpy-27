import { PLACES, type PlaceBase, type Role } from './places.ts';
import { DETAILS, EXTRA_PLACES, type Detail, type Img } from './research.gen.ts';

export type { Img };

export interface Place extends PlaceBase, Omit<Detail, 'lat' | 'lng' | 'images' | 'tips' | 'official'> {
  lat: number;
  lng: number;
  images: Img[];
  /** day the research tied this sight to (along / detour suggestions) */
  day?: number;
  category?: string;
  detourMin?: number;
}

const merged = new Map<string, Place>();

for (const base of PLACES) {
  const d = DETAILS[base.id];
  const lat = base.lat ?? d?.lat;
  const lng = base.lng ?? d?.lng;
  if (lat == null || lng == null) {
    // A place without coordinates cannot be drawn; surface it during development.
    console.warn(`[catalog] no coordinates for ${base.id}`);
    continue;
  }
  merged.set(base.id, {
    ...d,
    ...base,
    // research coordinates are verified on site maps; prefer them for sights and food
    lat: base.kind === 'station' ? lat : (d?.lat ?? lat),
    lng: base.kind === 'station' ? lng : (d?.lng ?? lng),
    tips: base.tips ?? d?.tips,
    official: base.official ?? d?.official,
    note: base.note ?? d?.why,
    images: d?.images ?? [],
  });
}

const nearestArea = (lat: number, lng: number) => {
  let best: Place | undefined;
  let bestD = Infinity;
  for (const p of merged.values()) {
    const d = (p.lat - lat) ** 2 + ((p.lng - lng) * Math.cos((lat * Math.PI) / 180)) ** 2;
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  return best?.area ?? 'tokyo';
};

for (const extra of EXTRA_PLACES) {
  const d = DETAILS[extra.id];
  if (!d?.lat || !d?.lng) continue;
  const existing = merged.get(extra.id);
  if (existing) {
    merged.set(extra.id, { ...existing, day: extra.day, category: extra.category, role: existing.role ?? (extra.role === 'plan' ? undefined : extra.role) });
    continue;
  }
  merged.set(extra.id, {
    ...d,
    id: extra.id,
    name: extra.name,
    ja: extra.ja,
    kind: 'sight',
    area: nearestArea(d.lat, d.lng),
    role: extra.role as Role,
    day: extra.day,
    category: extra.category,
    detourMin: extra.detourMin,
    note: d.why,
    lat: d.lat,
    lng: d.lng,
    images: d.images,
  });
}

export const PLACE_MAP = merged;

export function place(id: string): Place {
  const p = merged.get(id);
  if (!p) throw new Error(`Unknown place: ${id}`);
  return p;
}

export const hasPlace = (id: string) => merged.has(id);
export const allPlaces = () => [...merged.values()];
