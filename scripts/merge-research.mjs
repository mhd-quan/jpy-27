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
//   research/shopping-cards.json what each store is, what to look for, practical advice, photos
//   research/fuji-photos.json    what each Fuji viewpoint looks like (photos), for places without any
//   research/trains-*.json       what to see from each ride, transfers, when to get off
//   research/phrases.json        scenario phrasebook
//
// Writes src/data/research.gen.ts (place details) and src/data/enrich.gen.ts (everything else).
//
// Usage: node scripts/merge-research.mjs

import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { deepTidy } from './tidy.mjs';

const root = new URL('..', import.meta.url).pathname;
// research text is tidied of internal references (scripts/tidy.mjs) as it is read
const read = (name) => {
  const file = join(root, 'research', name);
  return existsSync(file) ? deepTidy(JSON.parse(readFileSync(file, 'utf8'))) : null;
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
      // a day number, or an alternative day's slug ("kawaguchiko")
      day: num(p.day) ?? (typeof p.day === 'string' ? p.day : undefined),
      category: p.type,
      near: p.near,
    });
  }
}

// Commons photos as the research files list them (url, page, credit, licence, Vietnamese caption)
const commonsImages = (list, fallbackKind) =>
  (list ?? []).filter((im) => im?.url).map((im) => ({ kind: KIND[im.kind] ?? fallbackKind, src: local(im.url), caption: clean(im.caption) ?? '', credit: clean(im.credit) ?? '', license: clean(im.license), page: im.page }));

// Shopping stores: catalog places (kind shop) so the place sheet and maps can use them. A store's
// card (shopping-cards.json) says what the store is, which becomes the place's note; the plan's
// reason to go there moves to store.plan.
const shopExtra = read('shopping-extra.json') ?? { items: [], stores: [], sources: [] };
const shopCards = read('shopping-cards.json') ?? {};
for (const st of [...(read('shopping-stores.json')?.stores ?? []), ...(shopExtra.stores ?? [])]) {
  const lat = num(st?.lat);
  const lng = num(st?.lng);
  if (!st?.id || lat == null || lng == null) continue;
  const card = shopCards[st.id] ?? {};
  const about = clean(card.about);
  const images = commonsImages(card.images, 'exterior');
  details[st.id] = {
    ...(details[st.id] ?? { images: [] }),
    lat: round(lat),
    lng: round(lng),
    address: clean(st.address),
    hours: clean(st.hours),
    why: about ?? clean(st.why),
    tips: clean(st.floors),
    official: st.src ?? undefined,
    images: images.length ? images : details[st.id]?.images ?? [],
    store: {
      chain: st.chain ?? 'other',
      city: st.city ?? null,
      open: st.open ?? null,
      close: st.close ?? null,
      closedDow: Array.isArray(st.closedDow) ? st.closedDow.map(Number) : [],
      taxFree: st.taxFree ?? null,
      near: st.near ?? null,
      walkMin: num(st.walkMin),
      plan: about ? clean(st.why) ?? null : null,
      buy: (card.buy ?? []).map(clean).filter(Boolean),
      advice: clean(card.tips) ?? null,
    },
  };
  extraPlaces.push({ id: st.id, name: clean(st.name) ?? st.id, ja: clean(st.ja), kind: 'shop', role: 'alt', day: num(st.day) ?? undefined, category: st.chain });
}

// Fuji spots people post about: sights tied to the plan day they fit (4, 5 or the Kawaguchiko day)
const FIT_DAY = { day4: 4, day5: 5, kawaguchiko: 'kawaguchiko' };
for (const sp of read('fuji-spots.json')?.spots ?? []) {
  const lat = num(sp?.lat);
  const lng = num(sp?.lng);
  if (!sp?.id || lat == null || lng == null) continue;
  const images = commonsImages(sp.images, 'view');
  details[sp.id] = {
    ...(details[sp.id] ?? {}),
    lat: round(lat),
    lng: round(lng),
    hours: clean(sp.hours),
    fee: sp.costYen ? `¥${Number(sp.costYen).toLocaleString('vi-VN')}` : undefined,
    bestTime: clean(sp.bestTime),
    station: sp.nearestStation?.name ? `${clean(sp.nearestStation.name)}${sp.nearestStation.walkMin ? ` ${sp.nearestStation.walkMin} phút` : ''}` : undefined,
    why: clean(sp.famousFor),
    tips: [clean(sp.status2026), clean(sp.etiquette)].filter(Boolean).join(' ') || undefined,
    images: images.length ? images : details[sp.id]?.images ?? [],
    fujiSpot: {
      area: sp.area ?? null,
      type: sp.type ?? null,
      fit: sp.fit ?? null,
      status: clean(sp.status2026) ?? null,
      etiquette: clean(sp.etiquette) ?? null,
      access: sp.access ?? {},
      busStop: sp.busStop ?? null,
      social: (sp.social ?? []).filter((x) => x?.url).map((x) => ({ platform: x.platform ?? 'blog', url: x.url, note: clean(x.note) ?? null })),
    },
  };
  extraPlaces.push({ id: sp.id, name: clean(sp.name) ?? sp.id, ja: clean(sp.ja), kind: 'sight', role: 'detour', day: FIT_DAY[sp.fit] ?? undefined, category: 'fuji-spot' });
}

// A Fuji viewpoint's photos (fuji-photos.json) also become the place's own when it has none: a
// station or a sight shown only by its sight line. Places with photos keep theirs (a ryokan's
// rooms stay on the ryokan's page; the viewpoint's card shows the scenery first either way).
for (const [id, v] of Object.entries(read('fuji-photos.json') ?? {})) {
  const images = commonsImages(v?.images, 'view');
  if (images.length && !(details[id]?.images ?? []).length) details[id] = { ...(details[id] ?? {}), images };
}

// Everything that is not a place detail goes to enrich.gen.ts
const merged = (prefix, key) => readAll(prefix).flatMap((f) => f?.[key] ?? []);
const phrases = read('phrases.json') ?? { scenarios: [] };
const enrich = {
  PHRASES: phrases,
  STAYS_AROUND: read('stays-around.json') ?? {},
  FUJI_SPOTS_R: read('fuji-spots.json') ?? { spots: [], kawaguchikoDay: null },
  // MUJI and Don Quijote (shopping-extra.json) slot into the catalogue's categories and store list
  SHOP_ITEMS: (() => {
    const base = read('shopping-items.json') ?? { categories: [], chains: [] };
    for (const it of shopExtra.items ?? []) base.categories.find((c) => c.id === it.category)?.items.push(it);
    base.sources = [...(base.sources ?? []), ...(shopExtra.sources ?? [])];
    return base;
  })(),
  SHOP_PLAN: (() => {
    const base = read('shopping-stores.json') ?? { stores: [], slots: [], rules: [] };
    base.stores = [...base.stores, ...(shopExtra.stores ?? [])];
    return base;
  })(),
  RIDES_R: [...merged('trains-', 'rides'), ...(read('buses.json')?.rides ?? []).map((r) => ({ ...r, kind: 'bus' }))],
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
  store?: Store;
  fujiSpot?: FujiSpot;
}

export interface FujiSpot {
  area: string | null;
  type: string | null;
  fit: 'day4' | 'day5' | 'kawaguchiko' | null;
  status: string | null;
  etiquette: string | null;
  access: { kawaguchiko?: string | null; day4?: string | null; day5?: string | null };
  busStop: { ja: string; lat: number; lng: number; lines?: string | string[]; walkMin?: number; [k: string]: unknown } | null;
  social: { platform: string; url: string; note: string | null }[];
}

export interface Store {
  chain: string;
  city: string | null;
  open: string | null;
  close: string | null;
  closedDow: number[];
  taxFree: boolean | null;
  near: string | null;
  walkMin: number | null;
  plan: string | null;
  buy: string[];
  advice: string | null;
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
  kind: 'sight' | 'food' | 'shop';
  near?: string;
  role: 'plan' | 'along' | 'detour' | 'alt';
  day?: number | string;
  category?: string;
  detourMin?: number;
}

// Shape written by the Fuji research task; kept loose on purpose.
export type FujiResearch = Record<string, any>;
`;

writeFileSync(join(root, 'src/data/research.gen.ts'), `${header}${types}\n${body}\n`);
console.log(`research: ${Object.keys(details).length} details, ${extraPlaces.length} extra places, fuji ${fuji ? 'yes' : 'no'}, ${enrich.PHRASES.scenarios.length} phrase scenarios, ${enrich.RIDES_R.length} rides`);
