// Walking time that respects hills, for every walk on the site (plan legs, detours, hotel walks,
// shopping routes).
//
// Elevation: AWS Terrain Tiles (Terrarium) at z14 (≈ 9.5 m per pixel at 35°N), cached in .cache/dem14.
// Speed: Tobler's hiking function v = 6·exp(−3.5·|s + 0.05|) km/h, which is fastest on a slight
// downhill and slows on both steep climbs and steep descents, scaled to a sightseeing pace
// (PACE) so that flat ground comes out near 3.9 km/h — crossings, crowds, looking around. Each walk
// adds a minute to get one's bearings; walks that start or end at a large station add the time from
// platform to street.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { PNG } from 'pngjs';
import { haversine } from './geo-tools.mjs';

const root = new URL('..', import.meta.url).pathname;
const Z = 14;
export const PACE = 0.78; // share of Tobler speed: 5.04 km/h × 0.78 ≈ 3.9 km/h on the flat
const STEP_KM = 0.015;
const HYST = 4; // metres

const tiles = new Map();
const world = 256 * 2 ** Z;
const px = (lng) => ((lng + 180) / 360) * world;
const py = (lat) => {
  const s = Math.sin((lat * Math.PI) / 180);
  return (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * world;
};

async function tile(x, y) {
  const key = `${x}/${y}`;
  if (tiles.has(key)) return tiles.get(key);
  const file = join(root, '.cache/dem14', `${x}`, `${y}.png`);
  if (!existsSync(file)) {
    mkdirSync(dirname(file), { recursive: true });
    const url = `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/${Z}/${x}/${y}.png`;
    let buf;
    for (let i = 0; i < 4 && !buf; i++) {
      const res = await fetch(url);
      if (res.ok) buf = Buffer.from(await res.arrayBuffer());
      else await new Promise((r) => setTimeout(r, 800 * (i + 1)));
    }
    if (!buf) throw new Error(`dem tile ${key}`);
    writeFileSync(file, buf);
  }
  const png = PNG.sync.read(readFileSync(file));
  const elev = new Float32Array(256 * 256);
  for (let i = 0; i < 256 * 256; i++) elev[i] = png.data[i * 4] * 256 + png.data[i * 4 + 1] + png.data[i * 4 + 2] / 256 - 32768;
  tiles.set(key, elev);
  return elev;
}

export async function preloadDem(points) {
  const need = new Set(points.map(([lat, lng]) => `${Math.floor(px(lng) / 256)}/${Math.floor(py(lat) / 256)}`));
  for (const k of need) {
    const [x, y] = k.split('/').map(Number);
    await tile(x, y);
  }
}

function elev(lat, lng) {
  const X = px(lng) - 0.5;
  const Y = py(lat) - 0.5;
  const x0 = Math.floor(X);
  const y0 = Math.floor(Y);
  const fx = X - x0;
  const fy = Y - y0;
  const at = (x, y) => {
    const t = tiles.get(`${Math.floor(x / 256)}/${Math.floor(y / 256)}`);
    return t ? t[(((y % 256) + 256) % 256) * 256 + (((x % 256) + 256) % 256)] : 0;
  };
  return Math.max(0, (1 - fx) * (1 - fy) * at(x0, y0) + fx * (1 - fy) * at(x0 + 1, y0) + (1 - fx) * fy * at(x0, y0 + 1) + fx * fy * at(x0 + 1, y0 + 1));
}

function resample(pts) {
  const out = [pts[0]];
  let carry = 0;
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1];
    const b = pts[i];
    const d = haversine(a, b);
    let t = STEP_KM - carry;
    while (t <= d) {
      const f = t / d;
      out.push([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]);
      t += STEP_KM;
    }
    carry = d - (t - STEP_KM);
  }
  out.push(pts.at(-1));
  return out;
}

const tobler = (s) => 6 * Math.exp(-3.5 * Math.abs(s + 0.05));

/** Big stations: minutes from the train door to the street, on top of the street walk. */
export const STATION_ACCESS = {
  'st-shinjuku': 5,
  'st-shinjuku-odakyu': 4,
  'st-shinagawa': 4,
  'st-nagoya': 5,
  'st-kintetsu-nagoya': 4,
  'st-kintetsu-kyoto': 4,
  'st-kyoto-karasuma': 3,
  'st-osaka-namba': 4,
  'st-namba': 4,
  'st-nankai-namba': 4,
  'st-umeda': 5,
  'st-shibuya': 4,
  'st-akihabara': 2,
  'st-odawara': 3,
  'st-shizuoka': 3,
  'st-asakusa': 2,
  'st-nihonbashi': 2,
  'st-kanda': 2,
  'st-ueno-hirokoji': 2,
  kix: 5,
  'haneda-t3': 5,
};

/**
 * Minutes to walk a path [lat, lng][] with its climbs, plus fixed overheads.
 * Call preloadDem(pts) first. Returns km, metres up and down, and minutes (walking + overheads).
 */
export function walkStats(pts, { from, to } = {}) {
  const s = resample(pts);
  const raw = s.map(([la, lo]) => elev(la, lo));
  // The surface model sees buildings, overpasses and station decks as ground. A 7-sample (≈105 m)
  // moving average, then a 4 m hysteresis (a change only counts once it holds), keeps flat streets
  // flat while real slopes — Kiyomizu, Chūreitō's steps, Kasuga — keep their climb.
  const smooth = raw.map((_, i) => {
    const w = raw.slice(Math.max(0, i - 3), i + 4);
    return w.reduce((t, v) => t + v, 0) / w.length;
  });
  const h = [];
  let ref = smooth[0];
  for (const v of smooth) {
    if (Math.abs(v - ref) > HYST) ref = v - Math.sign(v - ref) * HYST;
    h.push(ref);
  }
  let km = 0;
  let up = 0;
  let down = 0;
  let hours = 0;
  for (let i = 1; i < s.length; i++) {
    const d = haversine(s[i - 1], s[i]);
    if (d <= 0) continue;
    const dh = h[i] - h[i - 1];
    if (dh > 0) up += dh;
    else down -= dh;
    const slope = Math.max(-0.6, Math.min(0.6, dh / (d * 1000)));
    hours += d / (tobler(slope) * PACE);
    km += d;
  }
  const walkMin = hours * 60;
  // a change between two stations is one long transfer: count the bigger station's platform time once
  const a = STATION_ACCESS[from] ?? 0;
  const b = STATION_ACCESS[to] ?? 0;
  const station = a && b ? Math.max(a, b) : a + b;
  const overhead = (km > 0.05 ? 1 : 0) + station;
  return {
    km: Math.round(km * 100) / 100,
    up: Math.round(up),
    down: Math.round(down),
    walkMin: Math.round(walkMin * 10) / 10,
    min: Math.max(1, Math.round(walkMin + overhead)),
  };
}
