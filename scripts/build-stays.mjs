// Walks and surroundings for each hotel, and Fuji from the ryokan.
//
// Walks from research/stays-around.json are routed on foot through their waypoints (OSRM).
// For the ryokan (Mizunoto) every ~50 m of each walk is tested for a terrain line of sight to the
// summit, the nearby viewpoints from the research are tested too, and a viewshed raster around the
// ryokan is drawn: transparent where hills hide the summit, tinted where they don't. Terrain only —
// trees and buildings are not in the elevation data.
//
// Output: src/data/stays.gen.ts, public/img/fuji-viewshed-mizunoto.png
// Usage: node scripts/build-stays.mjs [--fresh]

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { PNG } from 'pngjs';
import { place } from '../src/data/catalog.ts';
import { encode, haversine, lengthKm, osrm, simplify } from './geo-tools.mjs';
import { SUMMIT, preload, sightline } from './fuji-tools.mjs';
import { deepTidy } from './tidy.mjs';

const root = new URL('..', import.meta.url).pathname;
const fresh = process.argv.includes('--fresh');
const file = join(root, 'research/stays-around.json');
if (!existsSync(file)) {
  console.log('research/stays-around.json missing — nothing to do');
  process.exit(0);
}
const research = deepTidy(JSON.parse(readFileSync(file, 'utf8')));
// self-hosted copies of Commons photos (scripts/localize-images.mjs)
const commonsFile = join(root, 'research/commons-map.json');
const commons = existsSync(commonsFile) ? JSON.parse(readFileSync(commonsFile, 'utf8')) : {};
const localImg = (im) => ({ ...im, url: commons[im.url] ?? im.url });
const RYOKAN = 'mizunoto';
const WALK_KMH = 4.2;
const num = (v) => (v == null || v === '' ? null : Number(v));
const pt = (p) => [num(p[0] ?? p.lat), num(p[1] ?? p.lng)];

/** Resample a polyline every `step` km. */
function resample(pts, step) {
  const out = [{ p: pts[0], km: 0 }];
  let acc = 0;
  let next = step;
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1];
    const b = pts[i];
    const d = haversine(a, b);
    while (acc + d >= next) {
      const t = (next - acc) / d;
      out.push({ p: [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t], km: next });
      next += step;
    }
    acc += d;
  }
  out.push({ p: pts.at(-1), km: acc });
  return out;
}

const out = {};
for (const [id, r] of Object.entries(research)) {
  let hotel;
  try {
    hotel = place(id);
  } catch {
    console.warn(`! unknown hotel ${id}`);
    continue;
  }
  const home = [hotel.lat, hotel.lng];
  const walks = [];
  for (const w of r.walks ?? []) {
    const wps = (w.waypoints ?? []).map(pt).filter(([a, b]) => Number.isFinite(a) && Number.isFinite(b));
    if (wps.length < 2) continue;
    // start at the door even if the research started a few metres away
    if (haversine(wps[0], home) > 0.03) wps.unshift(home);
    let pts;
    try {
      pts = await osrm('foot', wps, { fresh });
    } catch (e) {
      console.warn(`! ${id}/${w.id}: ${e.message} — straight segments used`);
      pts = wps;
    }
    const km = lengthKm(pts);
    const walk = {
      id: w.id,
      title: w.title,
      best: w.best ?? null,
      text: w.text ?? null,
      minutes: num(w.minutes),
      routedMin: Math.round((km / WALK_KMH) * 60),
      km: Math.round(km * 100) / 100,
      p: encode(simplify(pts, 0.00001)),
      highlights: (w.highlights ?? [])
        .filter((h) => num(h.lat) != null && num(h.lng) != null)
        .map((h) => ({ name: h.name, ja: h.ja ?? null, lat: num(h.lat), lng: num(h.lng), text: h.text ?? null, images: (h.images ?? []).filter((im) => im?.url).map(localImg) })),
    };
    if (id === RYOKAN) {
      // line of sight every 50 m; consecutive samples with the same answer form one segment
      const samples = resample(pts, 0.05);
      await preload(samples.map((s) => s.p));
      const segs = [];
      for (const s of samples) {
        const v = sightline({ lat: s.p[0], lng: s.p[1] }).visible;
        const last = segs.at(-1);
        if (last && last.v === v) last.pts.push(s.p);
        else segs.push({ v, pts: last ? [last.pts.at(-1), s.p] : [s.p] });
      }
      const visKm = segs.filter((g) => g.v).reduce((t, g) => t + lengthKm(g.pts), 0);
      walk.fuji = {
        km: Math.round(visKm * 100) / 100,
        share: km ? Math.round((visKm / km) * 100) : 0,
        segs: segs.filter((g) => g.pts.length > 1).map((g) => ({ v: g.v, p: encode(simplify(g.pts, 0.00001)) })),
      };
      console.log(`  ${w.id}: Fuji in line of sight on ${walk.fuji.km} of ${walk.km} km`);
    }
    walks.push(walk);
    console.log(`${id.padEnd(16)} ${w.id.padEnd(28)} ${walk.km.toFixed(2)} km ~${walk.routedMin} min`);
  }
  const entry = {
    area: r.area ?? null,
    walks,
    around: (r.around ?? []).filter((a) => num(a.lat) != null && num(a.lng) != null).map((a) => ({ ...a, lat: num(a.lat), lng: num(a.lng), walkMin: num(a.walkMin) ?? Math.max(1, Math.round(((haversine(home, [num(a.lat), num(a.lng)]) * 1.35) / 3.9) * 60)) })),
    photos: (r.photos ?? []).filter((im) => im?.url).map(localImg),
    sources: r.sources ?? [],
  };
  if (id === RYOKAN && r.fuji) {
    const views = [];
    const cands = (r.fuji.nearbyViews ?? []).filter((v) => num(v.lat) != null && num(v.lng) != null);
    await preload(cands.map((v) => [num(v.lat), num(v.lng)]));
    for (const v of cands) {
      const s = sightline({ lat: num(v.lat), lng: num(v.lng) });
      views.push({ ...v, lat: num(v.lat), lng: num(v.lng), sight: s, fromRyokanKm: Math.round(haversine(home, [num(v.lat), num(v.lng)]) * 100) / 100 });
      console.log(`  view ${String(v.name).padEnd(34)} ${s.visible ? 'VISIBLE' : 'blocked'} ${s.km} km, shows ${s.shownM} m`);
    }
    entry.fuji = { ...r.fuji, nearbyViews: views, here: sightline({ lat: home[0], lng: home[1] }) };

    // viewshed raster, 3.6 × 3.6 km around the ryokan at ~45 m
    const half = 1.8;
    const dLat = half / 111.2;
    const dLng = half / (111.2 * Math.cos((home[0] * Math.PI) / 180));
    const W = 80;
    const H = 80;
    const bounds = [
      [home[1] - dLng, home[0] - dLat],
      [home[1] + dLng, home[0] + dLat],
    ];
    const cells = [];
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) cells.push([home[0] + dLat - ((y + 0.5) / H) * 2 * dLat, home[1] - dLng + ((x + 0.5) / W) * 2 * dLng]);
    await preload(cells);
    const png = new PNG({ width: W, height: H });
    let vis = 0;
    cells.forEach(([lat, lng], i) => {
      const v = sightline({ lat, lng }).visible;
      if (v) vis++;
      png.data[i * 4] = 47;
      png.data[i * 4 + 1] = 125;
      png.data[i * 4 + 2] = 225;
      png.data[i * 4 + 3] = v ? 150 : 0;
    });
    mkdirSync(join(root, 'public/img'), { recursive: true });
    writeFileSync(join(root, 'public/img/fuji-viewshed-mizunoto.png'), PNG.sync.write(png));
    entry.fuji.viewshed = { src: 'img/fuji-viewshed-mizunoto.png', bounds, share: Math.round((vis / cells.length) * 100) };
    console.log(`  viewshed: summit in line of sight from ${entry.fuji.viewshed.share}% of the 3.6 km square`);
  }
  out[id] = entry;
}

const header = '// Generated by scripts/build-stays.mjs — do not edit by hand.\n';
writeFileSync(join(root, 'src/data/stays.gen.ts'), `${header}export const STAYS_GEN: Record<string, any> = ${JSON.stringify(out, null, 1)};\nexport const FUJI_SUMMIT_LL = ${JSON.stringify([SUMMIT.lat, SUMMIT.lng])};\n`);
console.log(`\n${Object.keys(out).length} hotels written`);
