// Merge the raw research files in /research into src/data/research.gen.ts.
//
// Inputs (all optional except food-tabelog.json):
//   research/food-tabelog.json   Tabelog facts + photos (scripts: see README)
//   research/captions.json       curated photo picks with Vietnamese captions
//   research/hotels-images.json  official hotel photos
//   research/sights-east.json    { places: [...] } sights for days 1–5
//   research/sights-west.json    { places: [...] } sights for days 6–12
//   research/fuji.json           Fuji climate, viewpoints, train windows
//   research/menus-*.json        recommended dishes with prices, per restaurant
//   research/snacks-*.json       { places: [...] } snack, dessert and market stops tied to a day
//   research/fuji-spots.json     Fuji spots people post about, Kawaguchiko day logistics
//   research/stays-around.json   walks and practical places around each hotel
//   research/shopping-*.json     item catalogue, stores and shopping slots
//   research/trains-*.json       what to see from each ride, transfers, when to get off
//   research/phrases.json        scenario phrasebook
//
// Writes src/data/research.gen.ts (place details) and src/data/enrich.gen.ts (everything else).
//
// Usage: node scripts/merge-research.mjs

import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const read = (name) => {
  const file = join(root, 'research', name);
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : null;
};

const tabelog = read('food-tabelog.json') ?? {};
const captions = read('captions.json') ?? {};
const hotels = read('hotels-images.json') ?? {};
const sights = [...(read('sights-east.json')?.places ?? []), ...(read('sights-west.json')?.places ?? [])];
const fuji = read('fuji.json');
const commons = read('commons-map.json') ?? {};
const local = (u) => commons[u] ?? u;

const KIND = { dish: 'dish', interior: 'interior', exterior: 'exterior', room: 'room', bath: 'bath', view: 'view', detail: 'detail', other: 'other' };
const round = (n) => (typeof n === 'number' ? Math.round(n * 1e6) / 1e6 : undefined);
const clean = (s) => (typeof s === 'string' ? s.replace(/\s+/g, ' ').trim() : undefined);

/** @type {Record<string, any>} */
const details = {};

// Restaurants from Tabelog
for (const [id, t] of Object.entries(tabelog)) {
  const picks = captions[id];
  let images = t.images ?? [];
  if (Array.isArray(picks) && picks.length) {
    images = picks
      .map(({ i, vi }) => (images[i] ? { ...images[i], caption: vi } : null))
      .filter(Boolean);
  } else {
    images = images.slice(0, 8);
  }
  details[id] = {
    lat: round(t.lat),
    lng: round(t.lng),
    address: clean(t.address),
    hours: clean(t.hours),
    rating: t.rating ? Number(t.rating) : undefined,
    ratingCount: t.ratingCount ? Number(t.ratingCount) : undefined,
    images: images.map((im) => ({
      kind: KIND[im.kind] ?? 'other',
      src: im.url,
      full: im.original,
      caption: clean(im.caption) ?? '',
      credit: im.credit,
      page: im.page,
    })),
  };
}

// Hotels (official photos)
for (const [id, h] of Object.entries(hotels)) {
  details[id] = {
    ...(details[id] ?? {}),
    images: (h.images ?? []).map((im) => ({
      kind: KIND[im.kind] ?? 'other',
      src: im.url,
      caption: clean(im.caption) ?? '',
      credit: im.credit ?? 'Website khách sạn',
      page: im.page || undefined,
    })),
  };
}

// Sights from the research agents
const extraPlaces = [];
const roleMap = { planned: 'plan', along: 'along', detour: 'detour', alt: 'alt' };
for (const p of sights) {
  if (!p?.id || typeof p.lat !== 'number' || typeof p.lng !== 'number') continue;
  const images = (p.images ?? [])
    .filter((im) => im?.url)
    .map((im) => ({
      kind: KIND[im.kind] ?? 'view',
      src: local(im.url),
      caption: clean(im.caption) ?? '',
      credit: clean(im.credit) ?? '',
      license: clean(im.license),
      page: im.page,
    }));
  details[p.id] = {
    ...(details[p.id] ?? {}),
    lat: round(p.lat),
    lng: round(p.lng),
    address: clean(p.address),
    hours: clean(p.hoursShort ?? p.hours),
    fee: clean(p.fee),
    bestTime: clean(p.bestTime),
    station: clean(p.nearestStation),
    why: clean(p.why),
    tips: clean(p.tips),
    fujiView: p.fujiView,
    fujiNote: clean(p.fujiNote),
    official: p.official ?? undefined,
    images: images.length ? images : details[p.id]?.images ?? [],
  };
  extraPlaces.push({
    id: p.id,
    name: clean(p.nameVi ?? p.nameEn) ?? p.id,
    ja: clean(p.nameJa),
    kind: 'sight',
    role: roleMap[p.role] ?? 'along',
    day: typeof p.day === 'number' ? p.day : undefined,
    category: p.category,
    detourMin: typeof p.detourMin === 'number' ? p.detourMin : undefined,
  });
}


// Menus: recommended dishes per restaurant
const readAll = (prefix) =>
  readdirSync(join(root, 'research'))
    .filter((f) => f.startsWith(prefix) && f.endsWith('.json'))
    .sort()
    .map((f) => read(f));
const num = (v) => (v == null || v === '' || Number.isNaN(Number(v)) ? null : Number(v));
for (const menus of readAll('menus-')) {
  for (const [id, m] of Object.entries(menus ?? {})) {
    if (!m?.items?.length) continue;
    details[id] = {
      ...(details[id] ?? { images: [] }),
      menu: {
        items: m.items
          .filter((it) => it?.ja || it?.vi)
          .map((it) => ({
            ja: clean(it.ja) ?? '',
            romaji: clean(it.romaji) ?? null,
            vi: clean(it.vi) ?? '',
            yen: num(it.yen),
            yenNote: clean(it.yenNote) ?? null,
            pick: it.pick ?? 'popular',
            note: clean(it.note) ?? null,
            src: it.src ?? null,
          })),
        orderTip: clean(m.orderTip) ?? null,
        ticketMachine: m.ticketMachine ?? null,
        menuEn: m.menuEn ?? null,
        sources: m.sources ?? [],
      },
    };
  }
}

// Snack, dessert and market stops, each tied to the day it was picked for
const SNACK_TYPES = new Set(['snack', 'dessert', 'bakery', 'cafe', 'market', 'street-food', 'ekiben']);
for (const file of readAll('snacks-')) {
  for (const p of file?.places ?? []) {
    const lat = num(p?.lat);
    const lng = num(p?.lng);
    if (!p?.id || lat == null || lng == null) continue;
    const images = (p.images ?? [])
      .filter((im) => im?.url)
      .map((im) => ({
        kind: KIND[im.kind] ?? 'dish',
        src: local(im.url),
        full: im.original,
        caption: clean(im.caption) ?? '',
        credit: clean(im.credit) ?? '',
        license: clean(im.license),
        page: im.page,
      }));
    const tb = p.source?.tabelog;
    details[p.id] = {
      lat: round(lat),
      lng: round(lng),
      address: clean(p.address),
      hours: clean(p.hours),
      why: clean(p.why),
      rating: num(tb?.rating) ?? undefined,
      ratingCount: num(tb?.count) ?? undefined,
      images,
      snack: {
        type: SNACK_TYPES.has(p.type) ? p.type : 'snack',
        get: (p.get ?? []).filter((g) => g?.ja || g?.vi).map((g) => ({ ja: clean(g.ja) ?? '', romaji: clean(g.romaji) ?? null, vi: clean(g.vi) ?? '', yen: num(g.yen) })),
        when: clean(p.when) ?? null,
        open: p.open ?? null,
        close: p.close ?? null,
        closedDow: Array.isArray(p.closedDow) ? p.closedDow.map(Number).filter((n) => n >= 0 && n <= 6) : [],
        closedNote: clean(p.closedNote) ?? null,
        queue: clean(p.queue) ?? null,
        pay: p.pay ?? null,
        tabelog: tb?.url ? { url: tb.url, rating: num(tb.rating), count: num(tb.count), award: clean(tb.award) ?? null } : null,
        social: (p.source?.social ?? []).filter((x) => x?.url).map((x) => ({ platform: x.platform ?? 'blog', url: x.url, note: clean(x.note) ?? null })),
      },
    };
    extraPlaces.push({
      id: p.id,
      name: clean(p.name) ?? p.id,
      ja: clean(p.ja),
      kind: 'food',
      role: 'along',
      day: num(p.day) ?? undefined,
      category: p.type,
      near: p.near,
    });
  }
}

// Everything that is not a place detail goes to enrich.gen.ts
const merged = (prefix, key) => readAll(prefix).flatMap((f) => f?.[key] ?? []);
const phrases = read('phrases.json') ?? { scenarios: [] };
const enrich = {
  PHRASES: phrases,
  STAYS_AROUND: read('stays-around.json') ?? {},
  FUJI_SPOTS_R: read('fuji-spots.json') ?? { spots: [], kawaguchikoDay: null },
  SHOP_ITEMS: read('shopping-items.json') ?? { categories: [], chains: [] },
  SHOP_PLAN: read('shopping-stores.json') ?? { stores: [], slots: [], rules: [] },
  RIDES_R: merged('trains-', 'rides'),
};
const enrichTypes = `// Generated by scripts/merge-research.mjs — do not edit by hand.
// Raw research shapes for the enrichment pages; each page narrows what it reads.
/* eslint-disable */
export interface PhraseBook {
  scenarios: {
    id: string;
    vi: string;
    hint?: string;
    for: string[];
    phrases: { id: string; ja: string; romaji: string; vi: string; note?: string | null; slot?: string | null; example?: { ja: string; romaji: string } | null }[];
    hear?: { ja: string; romaji: string; vi: string; reply?: { ja: string; romaji: string } | null }[];
  }[];
}
`;
writeFileSync(
  join(root, 'src/data/enrich.gen.ts'),
  enrichTypes +
    Object.entries(enrich)
      .map(([k, v]) => `export const ${k}${k === 'PHRASES' ? ': PhraseBook' : ': any'} = ${JSON.stringify(v, null, 1)};`)
      .join('\n\n') +
    '\n',
);

const header = '// Generated by scripts/merge-research.mjs — do not edit by hand.\n';
const body = [
  `export const DETAILS: Record<string, Detail> = ${JSON.stringify(details, null, 1)};`,
  `export const EXTRA_PLACES: ExtraPlace[] = ${JSON.stringify(extraPlaces, null, 1)};`,
  `export const FUJI_RESEARCH: FujiResearch | null = ${JSON.stringify(fuji ?? null, null, 1)};`,
].join('\n\n');

const types = `
export interface Img {
  kind: 'dish' | 'interior' | 'exterior' | 'room' | 'bath' | 'view' | 'detail' | 'other';
  src: string;
  full?: string;
  caption: string;
  credit: string;
  license?: string;
  page?: string;
}

export interface Detail {
  lat?: number;
  lng?: number;
  address?: string;
  hours?: string;
  rating?: number;
  ratingCount?: number;
  fee?: string;
  bestTime?: string;
  station?: string;
  why?: string;
  tips?: string;
  fujiView?: 'yes' | 'partial' | 'no' | 'unknown';
  fujiNote?: string;
  official?: string;
  images: Img[];
  menu?: Menu;
  snack?: Snack;
}

export interface MenuItem {
  ja: string;
  romaji: string | null;
  vi: string;
  yen: number | null;
  yenNote: string | null;
  pick: 'signature' | 'popular' | 'value' | 'light' | 'side' | 'dessert' | 'drink';
  note: string | null;
  src: string | null;
}

export interface Menu {
  items: MenuItem[];
  orderTip: string | null;
  ticketMachine: boolean | null;
  menuEn: boolean | null;
  sources: string[];
}

export interface Snack {
  type: 'snack' | 'dessert' | 'bakery' | 'cafe' | 'market' | 'street-food' | 'ekiben';
  get: { ja: string; romaji: string | null; vi: string; yen: number | null }[];
  when: string | null;
  open: string | null;
  close: string | null;
  closedDow: number[];
  closedNote: string | null;
  queue: string | null;
  pay: 'cash' | 'card' | 'mixed' | null;
  tabelog: { url: string; rating: number | null; count: number | null; award: string | null } | null;
  social: { platform: string; url: string; note: string | null }[];
}

export interface ExtraPlace {
  id: string;
  name: string;
  ja?: string;
  kind: 'sight' | 'food';
  near?: string;
  role: 'plan' | 'along' | 'detour' | 'alt';
  day?: number;
  category?: string;
  detourMin?: number;
}

// Shape written by the Fuji research task; kept loose on purpose.
export type FujiResearch = Record<string, any>;
`;

writeFileSync(join(root, 'src/data/research.gen.ts'), `${header}${types}\n${body}\n`);
console.log(`research: ${Object.keys(details).length} details, ${extraPlaces.length} extra places, fuji ${fuji ? 'yes' : 'no'}, ${enrich.PHRASES.scenarios.length} phrase scenarios, ${enrich.RIDES_R.length} rides`);
