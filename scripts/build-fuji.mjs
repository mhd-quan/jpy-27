// Fuji visibility from real terrain.
//
// For each viewpoint: distance and bearing to the summit, whether the line of sight
// clears the terrain in between (earth curvature + standard refraction), how much
// of the mountain shows above the nearest obstruction, its apparent size, and a
// horizon silhouette for the panorama drawing. For the train days it samples the
// track every ~1.5 km and records on which side of the train Fuji would appear.
//
// Elevation: AWS Terrain Tiles (Terrarium, z12 ≈ 30 m), cached in .cache/dem.
// Output: src/data/fuji.gen.ts
//
// Usage: node scripts/build-fuji.mjs

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { PNG } from 'pngjs';
import { place, hasPlace } from '../src/data/catalog.ts';
import { DAYS, legsOf } from '../src/data/days.ts';
import { GEO } from '../src/data/geo.gen.ts';
import { LINES } from '../src/data/lines.ts';

const root = new URL('..', import.meta.url).pathname;
const SUMMIT = { lat: 35.36064, lng: 138.72743, h: 3776 };
const Z = 12;
const R = 6371008.8;
const K = 0.13; // refraction coefficient
const EYE = 1.6;

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
async function preload(points) {
  const need = new Set();
  for (const [lat, lng] of points) need.add(`${Math.floor(px(lng) / 256)}/${Math.floor(py(lat) / 256)}`);
  let n = 0;
  for (const k of need) {
    const [x, y] = k.split('/').map(Number);
    await tile(x, y);
    if (++n % 25 === 0) console.log(`  dem ${n}/${need.size}`);
  }
}
function elevSync(lat, lng) {
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
function inverse(a, b) {
  const φ1 = rad(a.lat);
  const φ2 = rad(b.lat);
  const Δλ = rad(b.lng - a.lng);
  const d = 2 * R * Math.asin(Math.sqrt(Math.sin((φ2 - φ1) / 2) ** 2 + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) ** 2));
  const θ = Math.atan2(Math.sin(Δλ) * Math.cos(φ2), Math.cos(φ1) * Math.sin(φ2) - Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ));
  return { d, bearing: (deg(θ) + 360) % 360 };
}
function destination(a, bearing, dist) {
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

function sightline(o, eye = EYE, fixedElev) {
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

function panorama(o, eye = EYE, fixedElev, span = 22) {
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

// ——— viewpoints ———
const research = existsSync(join(root, 'research/fuji.json')) ? JSON.parse(readFileSync(join(root, 'research/fuji.json'), 'utf8')) : null;
const FALLBACK = [
  { id: 'onshi-hakone-park', lat: 35.19585, lng: 139.02475, day: 4, role: 'planned' },
  { id: 'moto-hakone-viewpoint', nameVi: 'Bờ hồ Moto-Hakone', lat: 35.2032, lng: 139.0268, day: 4, role: 'along' },
  { id: 'lake-ashi-cruise-deck', nameVi: 'Giữa hồ Ashi, trên thuyền', lat: 35.215, lng: 138.999, day: 4, role: 'planned', eye: 4, fixedElev: 725 },
  { id: 'togendai', lat: 35.2379, lng: 138.9953, day: 4, role: 'planned', fixedElev: 725 },
  { id: 'owakudani', lat: 35.2444, lng: 139.0196, day: 4, role: 'planned' },
  { id: 'sounzan', lat: 35.2464, lng: 139.0356, day: 4, role: 'planned' },
  { id: 'mizunoto', day: 4, role: 'planned' },
  { id: 'satta-pass', nameVi: 'Đèo Satta', lat: 35.0697, lng: 138.5452, day: 5, role: 'detour' },
  { id: 'miho-no-matsubara', nameVi: 'Miho no Matsubara', lat: 34.9967, lng: 138.5249, day: 5, role: 'detour' },
  { id: 'nihondaira-yume-terrace', nameVi: 'Nihondaira Yume Terrace', lat: 34.9708, lng: 138.4646, day: 5, role: 'detour' },
  { id: 'kaizan', day: 5, role: 'planned' },
  { id: 'oishi-park', nameVi: 'Công viên Ōishi', lat: 35.5233, lng: 138.747, day: 3, role: 'alt' },
  { id: 'chureito-pagoda', nameVi: 'Tháp Chūreitō', lat: 35.5011, lng: 138.8013, day: 3, role: 'alt' },
];
const spots = [];
const seen = new Set();
for (const s of [...(research?.spots ?? []), ...FALLBACK]) {
  if (!s?.id || seen.has(s.id)) continue;
  let lat = s.lat;
  let lng = s.lng;
  if ((lat == null || lng == null) && hasPlace(s.id)) ({ lat, lng } = place(s.id));
  if (typeof lat !== 'number' || typeof lng !== 'number') continue;
  seen.add(s.id);
  spots.push({ ...s, lat, lng });
}

// ——— train sampling ———
function decode(str) {
  const pts = [];
  let i = 0;
  let lat = 0;
  let lng = 0;
  const next = () => {
    let shift = 0;
    let result = 0;
    let b;
    do {
      b = str.charCodeAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return result & 1 ? ~(result >> 1) : result >> 1;
  };
  while (i < str.length) {
    lat += next();
    lng += next();
    pts.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return pts;
}
const TRAIN_LEGS = [];
for (const d of DAYS) {
  for (const l of legsOf(d)) {
    if (['romancecar', 'tokaido', 'shinkansen'].includes(l.line) && !TRAIN_LEGS.some((t) => t.id === l.id)) TRAIN_LEGS.push({ id: l.id, line: l.line, day: d.n });
  }
}
function sampleTrack(id, every = 1500, maxKm = Infinity) {
  const pts = decode(GEO[id].p);
  const out = [];
  let acc = 0;
  let next = 0;
  for (let i = 1; i < pts.length; i++) {
    const seg = inverse(pts[i - 1], pts[i]);
    while (next <= acc + seg.d && next <= maxKm * 1000) {
      const p = destination(pts[i - 1], seg.bearing, next - acc);
      out.push({ ...p, km: next / 1000, heading: seg.bearing });
      next += every;
    }
    acc += seg.d;
  }
  return out;
}

// ——— run ———
const all = [];
for (const s of spots) all.push([s.lat, s.lng], [SUMMIT.lat, SUMMIT.lng]);
const tracks = TRAIN_LEGS.map((t) => ({ ...t, samples: sampleTrack(t.id, 1500, t.line === 'shinkansen' ? 70 : Infinity) }));
for (const t of tracks) for (const s of t.samples) all.push([s.lat, s.lng]);
// bounding box of everything plus the summit, fill every tile inside
let s = 90;
let n = -90;
let w = 180;
let e = -180;
for (const [la, lo] of all) {
  s = Math.min(s, la);
  n = Math.max(n, la);
  w = Math.min(w, lo);
  e = Math.max(e, lo);
}
const fill = [];
for (let la = s - 0.05; la <= n + 0.05; la += 0.03) for (let lo = w - 0.05; lo <= e + 0.05; lo += 0.03) fill.push([la, lo]);
console.log('loading terrain…');
await preload(fill);

const outSpots = spots.map((sp) => {
  const sl = sightline(sp, sp.eye ?? EYE, sp.fixedElev);
  console.log(`${sp.id.padEnd(26)} ${String(sl.km).padStart(6)} km  ${String(sl.bearing).padStart(3)}°  ${sl.visible ? `visible, ${sl.shownM} m shown, ${sl.heightDeg}° tall` : `blocked at ${sl.blockKm} km`}`);
  return { id: sp.id, name: sp.nameVi ?? sp.nameEn ?? null, ja: sp.nameJa ?? null, lat: sp.lat, lng: sp.lng, day: sp.day ?? null, role: sp.role ?? null, ...sl };
});

const PANORAMAS = ['onshi-hakone-park', 'lake-ashi-cruise-deck', 'owakudani', 'satta-pass', 'oishi-park'];
const panoramas = {};
for (const id of PANORAMAS) {
  const sp = spots.find((x) => x.id === id);
  if (!sp) continue;
  panoramas[id] = panorama(sp, sp.eye ?? EYE, sp.fixedElev);
  console.log(`panorama ${id}`);
}

// Nearest station on the same line, romanised for the common ones.
const ROMAJI = {
  新宿: 'Shinjuku', 代々木上原: 'Yoyogi-Uehara', 登戸: 'Noborito', 新百合ヶ丘: 'Shin-Yurigaoka', 町田: 'Machida', 相模大野: 'Sagami-Ōno',
  海老名: 'Ebina', 本厚木: 'Hon-Atsugi', 愛甲石田: 'Aikō-Ishida', 伊勢原: 'Isehara', 鶴巻温泉: 'Tsurumaki-Onsen', 東海大学前: 'Tōkaidaigakumae',
  秦野: 'Hadano', 渋沢: 'Shibusawa', 新松田: 'Shin-Matsuda', 開成: 'Kaisei', 栢山: 'Kayama', 螢田: 'Hotaruda', 足柄: 'Ashigara', 小田原: 'Odawara',
  箱根板橋: 'Hakone-Itabashi', 風祭: 'Kazamatsuri', 入生田: 'Iriuda', 箱根湯本: 'Hakone-Yumoto', 経堂: 'Kyōdō', 成城学園前: 'Seijōgakuen-mae',
  向ヶ丘遊園: 'Mukōgaoka-Yūen', 相模大塚: 'Sagami-Ōtsuka', 座間: 'Zama', 厚木: 'Atsugi',
  早川: 'Hayakawa', 根府川: 'Nebukawa', 真鶴: 'Manazuru', 湯河原: 'Yugawara', 熱海: 'Atami', 函南: 'Kannami', 三島: 'Mishima', 沼津: 'Numazu',
  片浜: 'Katahama', 原: 'Hara', 東田子の浦: 'Higashi-Tagonoura', 吉原: 'Yoshiwara', 富士: 'Fuji', 富士川: 'Fujikawa', 新蒲原: 'Shin-Kambara',
  蒲原: 'Kambara', 由比: 'Yui', 興津: 'Okitsu', 清水: 'Shimizu', 草薙: 'Kusanagi', 東静岡: 'Higashi-Shizuoka', 静岡: 'Shizuoka',
  掛川: 'Kakegawa', 浜松: 'Hamamatsu', 新富士: 'Shin-Fuji',
};
const stationFile = join(root, '.cache/n02/UTF-8/N02-23_Station.geojson');
const stations = existsSync(stationFile) ? JSON.parse(readFileSync(stationFile, 'utf8')).features : [];
function stationsFor(line) {
  const net = new Set((LINES[line].net ?? []).map(([op, l]) => `${op}|${l}`));
  return stations
    .filter((f) => net.has(`${f.properties.N02_004}|${f.properties.N02_003}`))
    .map((f) => {
      const c = f.geometry.coordinates[Math.floor(f.geometry.coordinates.length / 2)];
      return { name: f.properties.N02_005, lat: c[1], lng: c[0] };
    });
}
function nearestStation(list, p) {
  let best = null;
  let bestD = 2500;
  for (const st of list) {
    const d = inverse(p, st).d;
    if (d < bestD) {
      bestD = d;
      best = st.name;
    }
  }
  return best ? (ROMAJI[best] ?? best) : null;
}

const SIDE = (rel) => (rel > 25 && rel < 155 ? 'right' : rel < -25 && rel > -155 ? 'left' : Math.abs(rel) <= 25 ? 'ahead' : 'behind');
const outTracks = tracks.map((t) => ({
  id: t.id,
  line: t.line,
  day: t.day,
  samples: t.samples.map((p, i, arr) => {
    const st = nearestStation(t.stations ?? (t.stations = stationsFor(t.line)), p);
    const sl = sightline(p, 3);
    let rel = sl.bearing - p.heading;
    rel = ((rel + 540) % 360) - 180;
    void arr;
    return { km: Math.round(p.km * 10) / 10, lat: Math.round(p.lat * 1e5) / 1e5, lng: Math.round(p.lng * 1e5) / 1e5, v: sl.visible ? 1 : 0, side: SIDE(rel), dist: sl.km, shown: sl.shownM, st };
  }),
}));
for (const t of outTracks) {
  const vis = t.samples.filter((x) => x.v);
  console.log(`${t.line}: ${vis.length}/${t.samples.length} samples with line of sight`);
}

writeFileSync(
  join(root, 'src/data/fuji.gen.ts'),
  `// Generated by scripts/build-fuji.mjs — do not edit by hand.\nexport const FUJI_SUMMIT = ${JSON.stringify(SUMMIT)};\nexport const FUJI_SPOTS = ${JSON.stringify(outSpots, null, 1)};\nexport const FUJI_PANORAMAS: Record<string, { from: number; step: number; angles: number[]; summitAz: number }> = ${JSON.stringify(panoramas)};\nexport const FUJI_TRACKS = ${JSON.stringify(outTracks)};\n`,
);
console.log('written src/data/fuji.gen.ts');
