// Data for the iOS app: the same view models the site renders, serialised as JSON the app bundles,
// so the app works with no network. Run after any data change (README: Dữ liệu và pipeline).
//
//   ios/JP27/Resources/Trip/trip.json    days, legs and their geometry, places, rides — the plan itself
//   ios/JP27/Resources/Trip/guide.json   phrasebook, budget, shopping, stays, Fuji, bookings, notes
//   ios/Shared/schedule.json             a slim copy of the plan for the widget and the Live Activity
//   public/map/jp27-{light,dark}.json    the basemap style, served by the site for MapLibre Native
//
// Usage: node scripts/export-ios.mjs

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { DAYS, ALT_DAYS, dayKey } from '../src/data/days.ts';
import { LINES, MODE_LABEL } from '../src/data/lines.ts';
import { allPlaces, place } from '../src/data/catalog.ts';
import { GEO } from '../src/data/geo.gen.ts';
import { WALK_LEGS, WALK_STAYS } from '../src/data/walk.gen.ts';
import { SHOP_ROUTES } from '../src/data/shopping.gen.ts';
import { STAYS_GEN } from '../src/data/stays.gen.ts';
import { FUJI_SUMMIT, FUJI_SPOTS, FUJI_PANORAMAS } from '../src/data/fuji.gen.ts';
import { FUJI_RESEARCH } from '../src/data/research.gen.ts';
import { PHRASES, FUJI_SPOTS_R } from '../src/data/enrich.gen.ts';
import {
  TRIP,
  BUDGET,
  RATE_SCENARIOS,
  SAVINGS,
  SHOPPING,
  SHOP_GROUPS,
  TRANSPORT_LINES,
  PASSES,
  PHRASES as TRIP_PHRASES,
  BOOKINGS,
  CHECKS,
  STAYS,
} from '../src/data/trip.ts';
import { NOTE_GROUPS, STATIONS_TO_KNOW, SCENARIO_GROUPS, HUNT_STEPS, RESERVED } from '../src/data/notes.ts';
import { DAY_VIEWS, ALT_VIEWS, CHAPTERS } from '../src/lib/trip.ts';
import { RIDES, ALT_RIDES, rideAnchor, seatVerdict } from '../src/lib/rides.ts';
import { SLOTS, CATEGORIES, CHAINS, TAX_FREE, RULES, itemsFor } from '../src/lib/shopping.ts';
import { baseStyle } from '../src/lib/mapStyle.ts';
import { deepTidy } from './tidy.mjs';
import { DWELL, WAIT } from './plan-rules.mjs';

const root = new URL('..', import.meta.url).pathname;
const out = (rel, data) => {
  const file = join(root, rel);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify(data)}\n`);
  console.log(`${rel}  ${(JSON.stringify(data).length / 1024).toFixed(0)} KB`);
};

/** Drop null, undefined, empty strings and non-finite numbers so optional fields stay absent in Swift. */
function clean(v) {
  if (Array.isArray(v)) return v.map(clean);
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) {
      if (x === null || x === undefined || x === '' || (typeof x === 'number' && !Number.isFinite(x))) continue;
      o[k] = clean(x);
    }
    return o;
  }
  return v;
}

/** Self-hosted photos ship inside the app under commons/; remote ones stay URLs. */
const src = (s) => (s && !/^https?:/.test(s) ? s.replace(/^\/?img\//, '') : s);
const img = (i) => ({ kind: i.kind, src: src(i.src ?? i.url), full: i.full, caption: i.caption, credit: i.credit, license: i.license, page: i.page });
const r2 = (n) => Math.round(n * 100) / 100;

// ——— places ———
const uses = new Map();
for (const d of [...DAYS, ...ALT_DAYS]) {
  for (const it of d.items) {
    if (it.type !== 'stop' || !it.place) continue;
    const list = uses.get(it.place) ?? [];
    if (!list.some((u) => u.day === dayKey(d))) list.push({ day: dayKey(d), at: it.at });
    uses.set(it.place, list);
  }
}

const placeOut = (p) => ({
  id: p.id,
  name: p.name,
  ja: p.ja,
  kind: p.kind,
  area: p.area,
  lat: p.lat,
  lng: p.lng,
  role: p.role,
  dish: p.dish,
  price: p.price,
  note: p.note,
  tips: p.tips,
  closed: p.closed,
  pay: p.pay,
  tabelog: p.tabelog,
  official: p.official,
  review: p.review,
  address: p.address,
  hours: p.hours,
  rating: p.rating,
  ratingCount: p.ratingCount,
  fee: p.fee,
  bestTime: p.bestTime,
  station: p.station,
  fujiView: p.fujiView,
  fujiNote: p.fujiNote,
  images: (p.images ?? []).map(img),
  menu: p.menu && { ...p.menu, items: p.menu.items.map(({ src: _s, ...m }) => m) },
  snack: p.snack,
  store: p.store,
  fujiSpot: p.fujiSpot,
  day: p.day == null ? undefined : String(p.day),
  category: p.category,
  near: p.near,
  detourMin: p.detourMin,
  uses: uses.get(p.id) ?? [],
});

const places = allPlaces().map(placeOut);

// ——— days ———
const chapterOf = (n) => CHAPTERS.find((c) => c.days.includes(n))?.id;
const paths = {};

function legOut(l) {
  if (GEO[l.id]) paths[l.id] = { p: GEO[l.id].p, km: r2(GEO[l.id].km) };
  return {
    id: l.id,
    line: l.line,
    from: l.from,
    to: l.to,
    // place ids a walk passes; the plan clock spends its time as those stops come up
    via: (l.via ?? []).filter((v) => typeof v === 'string'),
    min: l.min,
    note: l.note,
    km: r2(l.km),
    walk: WALK_LEGS[l.id],
  };
}

function dayOut(v) {
  const d = v.day;
  const key = dayKey(d);
  return {
    key,
    n: d.n,
    replaces: d.replaces,
    date: d.date,
    dow: d.dow,
    title: d.title,
    route: d.route,
    stay: d.stay,
    lead: d.lead,
    walk: d.walk,
    meals: d.meals,
    trims: d.trims,
    alt: d.alt,
    chapter: chapterOf(d.n),
    km: Object.fromEntries(Object.entries(v.km).map(([k, x]) => [k, r2(x)])),
    items: d.items.map((it) =>
      it.type === 'stop'
        ? { type: 'stop', at: it.at, place: it.place, title: it.title, text: it.text, cost: it.cost, optional: it.optional || undefined, n: it.place ? v.stops.get(it.place) : undefined }
        : { type: 'move', at: it.at, leg: legOut(v.legs.find((l) => l.id === it.leg.id) ?? it.leg) },
    ),
    along: v.along.map((a) => ({
      place: a.p.id,
      km: r2(a.km),
      // a day with nothing on foot (day 12: hotel to airport) has no origin to measure from
      from: Number.isFinite(a.km) ? { label: a.from.label, lat: r2(a.from.pt[0] * 1000) / 1000, lng: r2(a.from.pt[1] * 1000) / 1000, onWalk: a.from.onWalk } : undefined,
      detour: a.detour && { p: a.detour.p, km: r2(a.detour.km), min: a.detour.min, mode: a.detour.mode, up: a.detour.up },
    })),
    slots: d.id ? [] : SLOTS.filter((s) => s.day === d.n).map((s) => s.id),
  };
}

const days = DAY_VIEWS.map(dayOut);
const altDays = ALT_VIEWS.map(dayOut);

// ——— rides ———
const rideOut = (r) => ({
  id: rideAnchor(r),
  day: dayKey(r.day),
  at: r.at,
  legs: r.legs.map((l) => l.id),
  color: r.color,
  lineName: r.lineName,
  fromName: r.fromName,
  toName: r.toName,
  km: r.km,
  min: r.min,
  title: r.title,
  train: r.train,
  seat: r.seat,
  seatVerdict: seatVerdict(r),
  stations: r.stations,
  hidden: r.hidden,
  events: r.events,
  transfers: r.transfers,
  alight: r.alight,
  onboard: r.onboard,
  board: r.board,
  pay: r.pay,
  sources: r.sources,
  researched: r.researched,
});

const lines = Object.fromEntries(Object.entries(LINES).map(([k, l]) => [k, { name: l.name, color: l.color, mode: l.mode }]));

const trip = clean({
  version: 1,
  meta: { ...TRIP, tz: 'Asia/Tokyo' },
  modes: MODE_LABEL,
  lines,
  chapters: CHAPTERS,
  places,
  days,
  altDays,
  paths,
  rides: RIDES.map(rideOut),
  altRides: ALT_RIDES.map(rideOut),
  reserved: RESERVED,
  rules: { dwell: DWELL, wait: WAIT },
});

// ——— guide ———
const slotOut = (s) => ({
  id: s.id,
  day: s.day,
  start: s.start,
  end: s.end,
  city: s.city,
  area: s.area,
  after: s.after,
  before: s.before,
  stores: s.stores.map((p) => p.id),
  focus: s.focus,
  why: s.why,
  skipIf: s.skipIf,
  route: SHOP_ROUTES[s.id] && { p: SHOP_ROUTES[s.id].p, km: SHOP_ROUTES[s.id].km, min: SHOP_ROUTES[s.id].min },
  items: itemsFor(s).map((i) => i.id),
});

const stayAround = (id) => {
  const g = STAYS_GEN[id] && deepTidy(STAYS_GEN[id]);
  if (!g) return undefined;
  return {
    ...g,
    photos: (g.photos ?? []).map(img),
    walks: (g.walks ?? []).map((w) => ({
      ...w,
      walk: WALK_STAYS[w.id],
      highlights: (w.highlights ?? []).map((h) => ({ ...h, images: (h.images ?? []).map(img) })),
    })),
  };
};

const guide = clean({
  version: 1,
  phrases: {
    scenarios: PHRASES.scenarios,
    groups: SCENARIO_GROUPS,
    trip: TRIP_PHRASES,
    stations: STATIONS_TO_KNOW.map(([romaji, ja]) => ({ romaji, ja })),
  },
  budget: {
    lines: BUDGET,
    scenarios: RATE_SCENARIOS,
    savings: SAVINGS,
    transport: TRANSPORT_LINES,
  },
  basket: {
    items: SHOPPING,
    groups: Object.entries(SHOP_GROUPS).map(([id, label]) => ({ id, label })),
  },
  shopping: {
    slots: SLOTS.map(slotOut),
    categories: CATEGORIES.map((c) => ({ id: c.id, vi: c.vi, items: c.items.map(({ category: _c, ...i }) => i) })),
    chains: CHAINS,
    taxFree: TAX_FREE,
    rules: RULES,
  },
  stays: STAYS.map((s) => ({ ...s, around: stayAround(s.id) })),
  hunt: HUNT_STEPS,
  fuji: {
    summit: FUJI_SUMMIT,
    spots: FUJI_SPOTS.map((s) => ({ ...s, day: s.day == null ? undefined : String(s.day) })),
    panoramas: FUJI_PANORAMAS,
    research: FUJI_RESEARCH,
    kawaguchiko: FUJI_SPOTS_R.kawaguchikoDay,
  },
  passes: PASSES,
  bookings: BOOKINGS,
  checks: CHECKS,
  notes: NOTE_GROUPS,
});

// ——— schedule: what a widget needs to say "next: …, leave in …" ———
const usedIds = new Set();
for (const d of [...days, ...altDays]) {
  if (d.stay) usedIds.add(d.stay);
  for (const it of d.items) {
    if (it.place) usedIds.add(it.place);
    if (it.leg) [it.leg.from, it.leg.to].forEach((x) => usedIds.add(x));
  }
}
const slimDay = (d) => ({
  key: d.key,
  n: d.n,
  replaces: d.replaces,
  date: d.date,
  dow: d.dow,
  title: d.title,
  route: d.route,
  stay: d.stay,
  chapter: d.chapter,
  meals: d.meals,
  trims: [],
  items: d.items.map((it) => (it.type === 'stop' ? { type: 'stop', at: it.at, place: it.place, title: it.title, cost: it.cost, optional: it.optional, n: it.n } : { type: 'move', at: it.at, leg: { id: it.leg.id, line: it.leg.line, from: it.leg.from, to: it.leg.to, via: it.leg.via, min: it.leg.min, km: it.leg.km, walk: it.leg.walk } })),
  along: [],
  slots: [],
});
// walks that pass several stops keep their geometry, so the widget's clock spends their time like the app's
const viaPaths = Object.fromEntries(
  [...days, ...altDays].flatMap((d) => d.items).filter((it) => it.type === 'move' && it.leg.via?.length && paths[it.leg.id]).map((it) => [it.leg.id, paths[it.leg.id]]),
);
const schedule = clean({
  version: 1,
  meta: trip.meta,
  modes: MODE_LABEL,
  lines,
  chapters: CHAPTERS,
  places: places
    .filter((p) => usedIds.has(p.id))
    .map((p) => ({ id: p.id, name: p.name, ja: p.ja, kind: p.kind, area: p.area, lat: p.lat, lng: p.lng, pay: p.pay, images: p.images.slice(0, 1), uses: [] })),
  days: days.map(slimDay),
  altDays: altDays.map(slimDay),
  paths: viaPaths,
  rides: [],
  bookings: BOOKINGS,
  altRides: [],
  reserved: RESERVED,
  rules: trip.rules,
});

out('ios/JP27/Resources/Trip/trip.json', trip);
out('ios/JP27/Resources/Trip/guide.json', guide);
out('ios/Shared/schedule.json', schedule);
for (const theme of ['light', 'dark']) out(`public/map/jp27-${theme}.json`, baseStyle(theme));

// sanity: every place a day points at exists
const ids = new Set(places.map((p) => p.id));
for (const d of [...days, ...altDays])
  for (const it of d.items) for (const id of it.type === 'stop' ? [it.place] : [it.leg.from, it.leg.to]) if (id && !ids.has(id)) throw new Error(`day ${d.key}: unknown place ${id}`);
void place;
