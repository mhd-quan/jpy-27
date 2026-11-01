// Terrain line of sight to Fuji, shared by build-fuji.mjs and build-stays.mjs.
// Elevation: AWS Terrain Tiles (Terrarium, z12 ≈ 30 m), cached in .cache/dem.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { PNG } from 'pngjs';

const root = new URL('..', import.meta.url).pathname;
export const SUMMIT = { lat: 35.36064, lng: 138.72743, h: 3776 };
const Z = 12;
const R = 6371008.8;
const K = 0.13; // refraction coefficient
export const EYE = 1.6;

// ——— DEM ———
const tiles = new Map();
async function tile(x, y) {
  const key = `${x}/${y}`;
  if (tiles.has(key)) return tiles.get(key);
  const file = join(root, '.cache/dem', String(Z), String(x), `${y}.png`);
  if (!existsSync(file)) {
    mkdirSync(dirname(file), { recursive: true });
    const url = `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/${Z}/${x}/${y}.png`;
    let buf;
    for (let i = 0; i < 4 && !buf; i++) {
      const res = await fetch(url);
      if (res.ok) buf = Buffer.from(await res.arrayBuffer());
      else await new Promise((r) => setTimeout(r, 1000 * (i + 1)));
    }
    if (!buf) throw new Error(`tile ${key}`);
    writeFileSync(file, buf);
  }
  const png = PNG.sync.read(readFileSync(file));
  const elev = new Float32Array(256 * 256);
  for (let i = 0; i < 256 * 256; i++) {
    const r = png.data[i * 4];
    const g = png.data[i * 4 + 1];
    const b = png.data[i * 4 + 2];
    elev[i] = r * 256 + g + b / 256 - 32768;
  }
  tiles.set(key, elev);
  return elev;
}
const world = 256 * 2 ** Z;
const px = (lng) => ((lng + 180) / 360) * world;
const py = (lat) => {
  const s = Math.sin((lat * Math.PI) / 180);
  return (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * world;
};
export async function preload(points) {
  const need = new Set();
  for (const [lat, lng] of points) need.add(`${Math.floor(px(lng) / 256)}/${Math.floor(py(lat) / 256)}`);
  let n = 0;
  for (const k of need) {
    const [x, y] = k.split('/').map(Number);
    await tile(x, y);
    if (++n % 25 === 0) console.log(`  dem ${n}/${need.size}`);
  }
}
export function elevSync(lat, lng) {
  const X = px(lng) - 0.5;
  const Y = py(lat) - 0.5;
  const x0 = Math.floor(X);
  const y0 = Math.floor(Y);
  const fx = X - x0;
  const fy = Y - y0;
  const at = (x, y) => {
    const t = tiles.get(`${Math.floor(x / 256)}/${Math.floor(y / 256)}`);
    if (!t) return 0;
    return t[(((y % 256) + 256) % 256) * 256 + (((x % 256) + 256) % 256)];
  };
  const v = (1 - fx) * (1 - fy) * at(x0, y0) + fx * (1 - fy) * at(x0 + 1, y0) + (1 - fx) * fy * at(x0, y0 + 1) + fx * fy * at(x0 + 1, y0 + 1);
  return Math.max(0, v); // sea and lakes clamp at 0 is fine for the sea; lakes keep their surface value
}

// ——— spherical helpers ———
const rad = (d) => (d * Math.PI) / 180;
const deg = (r) => (r * 180) / Math.PI;
export function inverse(a, b) {
  const φ1 = rad(a.lat);
  const φ2 = rad(b.lat);
  const Δλ = rad(b.lng - a.lng);
  const d = 2 * R * Math.asin(Math.sqrt(Math.sin((φ2 - φ1) / 2) ** 2 + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) ** 2));
  const θ = Math.atan2(Math.sin(Δλ) * Math.cos(φ2), Math.cos(φ1) * Math.sin(φ2) - Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ));
  return { d, bearing: (deg(θ) + 360) % 360 };
}
export function destination(a, bearing, dist) {
  const δ = dist / R;
  const θ = rad(bearing);
  const φ1 = rad(a.lat);
  const λ1 = rad(a.lng);
  const φ2 = Math.asin(Math.sin(φ1) * Math.cos(δ) + Math.cos(φ1) * Math.sin(δ) * Math.cos(θ));
  const λ2 = λ1 + Math.atan2(Math.sin(θ) * Math.sin(δ) * Math.cos(φ1), Math.cos(δ) - Math.sin(φ1) * Math.sin(φ2));
  return { lat: deg(φ2), lng: deg(λ2) };
}
const drop = (d) => ((d * d) / (2 * R)) * (1 - K);
const angle = (h, h0, d) => Math.atan2(h - drop(d) - h0, d);

// Fuji's approximate full width (km) at a given depth below the summit (m)
const WIDTH = [
  [0, 0.6],
  [500, 2],
  [1000, 3.6],
  [1500, 5.6],
  [2000, 8.5],
  [2500, 13],
  [3000, 20],
];
const widthAt = (depth) => {
  for (let i = 1; i < WIDTH.length; i++) {
    if (depth <= WIDTH[i][0]) {
      const [d0, w0] = WIDTH[i - 1];
      const [d1, w1] = WIDTH[i];
      return w0 + ((depth - d0) / (d1 - d0)) * (w1 - w0);
    }
  }
  return WIDTH.at(-1)[1];
};

export function sightline(o, eye = EYE, fixedElev) {
  const { d: D, bearing } = inverse(o, SUMMIT);
  const h0 = (fixedElev ?? elevSync(o.lat, o.lng)) + eye;
  const aSummit = angle(SUMMIT.h, h0, D);
  let maxA = -Math.PI / 2;
  let maxAt = 0;
  const step = 40;
  // Fuji's own flanks (≈ 8 km around the summit) are the mountain, not an obstruction.
  for (let s = 120; s < D - 8000; s += s < 3000 ? step : step * 2) {
    const p = destination(o, bearing, s);
    const a = angle(elevSync(p.lat, p.lng), h0, s);
    if (a > maxA) {
      maxA = a;
      maxAt = s;
    }
  }
  const visible = aSummit > maxA;
  // height on the summit's vertical at which the obstruction angle lands
  const hBase = Math.tan(maxA) * D + drop(D) + h0;
  const foot = 900;
  const shown = visible ? Math.max(0, Math.min(SUMMIT.h - foot, SUMMIT.h - hBase)) : 0;
  const heightDeg = visible ? deg(aSummit - Math.max(maxA, angle(SUMMIT.h - shown, h0, D))) : 0;
  const widthDeg = shown ? deg((widthAt(shown) * 1000) / D) : 0;
  return {
    km: Math.round(D / 100) / 10,
    bearing: Math.round(bearing),
    elev: Math.round(h0 - eye),
    visible,
    shownM: Math.round(shown / 10) * 10,
    heightDeg: Math.round(heightDeg * 100) / 100,
    widthDeg: Math.round(widthDeg * 10) / 10,
    blockKm: visible ? null : Math.round(maxAt / 100) / 10,
  };
}

export function panorama(o, eye = EYE, fixedElev, span = 22) {
  const { d: D, bearing } = inverse(o, SUMMIT);
  const h0 = (fixedElev ?? elevSync(o.lat, o.lng)) + eye;
  const out = [];
  const maxDist = Math.max(D + 15000, 30000);
  for (let az = bearing - span; az <= bearing + span + 1e-9; az += 0.25) {
    let maxA = -0.02;
    for (let s = 150; s < maxDist; s += s < 4000 ? 60 : s < 20000 ? 120 : 240) {
      const p = destination(o, az, s);
      const a = angle(elevSync(p.lat, p.lng), h0, s);
      if (a > maxA) maxA = a;
    }
    out.push(Math.round(deg(maxA) * 1000) / 1000);
  }
  return { from: Math.round((bearing - span) * 100) / 100, step: 0.25, angles: out, summitAz: Math.round(bearing * 100) / 100 };
}

