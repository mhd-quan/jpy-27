// Station sequence for every train ride of the plan, for the "Trên tàu" page.
//
// For each rail leg (train / Shinkansen, at least 3 km) the MLIT N02 stations of the leg's own
// lines that sit on its geometry are projected onto it, giving the order and the distance from
// boarding. English names come from Wikidata (railway stations in the route's bounding box,
// matched by Japanese label and distance), cached in .cache/wikidata-stations.json.
//
// Output: src/data/rides.gen.ts  { [legId]: { km, stations: [{ ja, en, km, lat, lng }] } }
// Usage: node scripts/build-rides.mjs [--fresh]

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { DAYS, ALT_DAYS, legsOf } from '../src/data/days.ts';
import { LINES } from '../src/data/lines.ts';
import { GEO } from '../src/data/geo.gen.ts';
import { place } from '../src/data/catalog.ts';
import { ROMAJI, decode, haversine, stationsForNet } from './geo-tools.mjs';

const root = new URL('..', import.meta.url).pathname;
const fresh = process.argv.includes('--fresh');
const CACHE = join(root, '.cache/wikidata-stations.json');

async function wikidataStations() {
  if (!fresh && existsSync(CACHE)) return JSON.parse(readFileSync(CACHE, 'utf8'));
  // railway stations (and subclasses) inside the route's bounding box
  const query = `SELECT ?ja ?en ?c WHERE {
    SERVICE wikibase:box { ?s wdt:P625 ?c. bd:serviceParam wikibase:cornerSouthWest "Point(135.1 34.3)"^^geo:wktLiteral. bd:serviceParam wikibase:cornerNorthEast "Point(140.0 35.8)"^^geo:wktLiteral. }
    ?s wdt:P31/wdt:P279* wd:Q55488.
    ?s rdfs:label ?ja FILTER(lang(?ja) = "ja").
    OPTIONAL { ?s rdfs:label ?en FILTER(lang(?en) = "en") }
  }`;
  const url = `https://query.wikidata.org/sparql?query=${encodeURIComponent(query)}`;
  const res = await fetch(url, { headers: { Accept: 'application/sparql-results+json', 'User-Agent': 'nb2027-trip-site/1.0 (personal itinerary)' } });
  if (!res.ok) throw new Error(`wikidata ${res.status}`);
  const json = await res.json();
  const rows = json.results.bindings.flatMap((b) => {
    const m = /Point\(([-\d.]+) ([-\d.]+)\)/.exec(b.c.value);
    return m ? [{ ja: b.ja.value, en: b.en?.value ?? null, lat: Number(m[2]), lng: Number(m[1]) }] : [];
  });
  writeFileSync(CACHE, JSON.stringify(rows));
  console.log(`wikidata: ${rows.length} stations cached`);
  return rows;
}

const wd = await wikidataStations();
const byJa = new Map();
for (const r of wd) {
  const k = r.ja.replace(/駅$/, '');
  if (!byJa.has(k)) byJa.set(k, []);
  byJa.get(k).push(r);
}
/** "Odawara" for 小田原 at this spot; macrons from the site's own table win. */
function english(ja, pt) {
  if (ROMAJI[ja]) return ROMAJI[ja];
  let best = null;
  let bestKm = 2;
  for (const r of byJa.get(ja) ?? []) {
    const d = haversine(pt, [r.lat, r.lng]);
    if (r.en && d < bestKm) {
      bestKm = d;
      best = r.en;
    }
  }
  if (!best) return null;
  return best.replace(/\s+(Station|Stop)$/i, '').replace(/\s*\(.*\)$/, '').trim();
}

/** Distance along the line to the foot of the perpendicular from p, and how far off the line p is. */
function along(p, pts) {
  const kx = Math.cos((p[0] * Math.PI) / 180);
  let acc = 0;
  let best = { off: Infinity, km: 0 };
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1];
    const b = pts[i];
    const seg = haversine(a, b);
    const ax = (a[1] - p[1]) * kx;
    const ay = a[0] - p[0];
    const bx = (b[1] - p[1]) * kx;
    const by = b[0] - p[0];
    const dx = bx - ax;
    const dy = by - ay;
    const t = dx * dx + dy * dy > 0 ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / (dx * dx + dy * dy))) : 0;
    const foot = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
    const off = haversine(p, foot);
    if (off < best.off) best = { off, km: acc + seg * t };
    acc += seg;
  }
  return best;
}

const out = {};
for (const day of [...DAYS, ...ALT_DAYS]) {
  for (const leg of legsOf(day)) {
    const line = LINES[leg.line];
    if (out[leg.id] || !line.net || !['train', 'shinkansen'].includes(line.mode)) continue;
    const g = GEO[leg.id];
    if (!g || g.km < 3) continue;
    const pts = decode(g.p);
    const seen = new Map();
    for (const st of stationsForNet(line.net)) {
      const a = along([st.lat, st.lng], pts);
      if (a.off > 0.25) continue;
      const prev = seen.get(st.name);
      if (!prev || a.off < prev.off) seen.set(st.name, { ...a, st });
    }
    const stations = [...seen.values()]
      .sort((x, y) => x.km - y.km)
      .map(({ km, st }) => ({ ja: st.name, en: english(st.name, [st.lat, st.lng]), km: Math.round(km * 10) / 10, lat: Math.round(st.lat * 1e5) / 1e5, lng: Math.round(st.lng * 1e5) / 1e5 }));
    // the boarding and alighting points are the plan's own stations
    const from = place(leg.from);
    const to = place(leg.to);
    if (!stations.length || stations[0].km > 0.4) stations.unshift({ ja: from.ja ?? from.name, en: from.name, km: 0, lat: from.lat, lng: from.lng });
    else Object.assign(stations[0], { km: 0, en: stations[0].en ?? from.name });
    const last = stations.at(-1);
    if (g.km - last.km > 0.4) stations.push({ ja: to.ja ?? to.name, en: to.name, km: g.km, lat: to.lat, lng: to.lng });
    else Object.assign(last, { km: g.km, en: last.en ?? to.name });
    out[leg.id] = { km: g.km, stations };
    const miss = stations.filter((s) => !s.en).length;
    console.log(`${leg.id.padEnd(58)} ${String(stations.length).padStart(3)} stations ${g.km.toFixed(1).padStart(6)} km${miss ? `  (${miss} without English)` : ''}`);
  }
}

const header = '// Generated by scripts/build-rides.mjs — do not edit by hand.\n';
const type = '{ km: number; stations: { ja: string; en: string | null; km: number; lat: number; lng: number }[] }';
writeFileSync(join(root, 'src/data/rides.gen.ts'), `${header}export const RIDE_GEO: Record<string, ${type}> = ${JSON.stringify(out)};\n`);
console.log(`\n${Object.keys(out).length} rides written`);
