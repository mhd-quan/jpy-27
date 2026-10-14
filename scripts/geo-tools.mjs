// Shared helpers for the data scripts: geometry, polyline encoding, OSRM routing with a
// disk cache, and MLIT N02 station lookup.

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const cache = join(root, '.cache');
mkdirSync(join(cache, 'osrm'), { recursive: true });

// ——— geometry helpers ———
const R = 6371.0088;
const rad = (d) => (d * Math.PI) / 180;
export function haversine([lat1, lng1], [lat2, lng2]) {
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
export const lengthKm = (pts) => pts.reduce((s, p, i) => (i ? s + haversine(pts[i - 1], p) : 0), 0);

/** Douglas–Peucker on [lat, lng] with tolerance in degrees (approx). */
export function simplify(pts, tol) {
  if (pts.length < 3) return pts;
  const keep = new Uint8Array(pts.length);
  keep[0] = keep[pts.length - 1] = 1;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop();
    let max = 0;
    let idx = -1;
    const [ay, ax] = pts[a];
    const [by, bx] = pts[b];
    const dx = bx - ax;
    const dy = by - ay;
    const len2 = dx * dx + dy * dy || 1e-18;
    for (let i = a + 1; i < b; i++) {
      const [py, px] = pts[i];
      const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
      const d = Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
      if (d > max) {
        max = d;
        idx = i;
      }
    }
    if (max > tol && idx > 0) {
      keep[idx] = 1;
      stack.push([a, idx], [idx, b]);
    }
  }
  return pts.filter((_, i) => keep[i]);
}

/** Google polyline encoding, precision 5, input [lat, lng]. */
export function encode(pts) {
  let out = '';
  let pLat = 0;
  let pLng = 0;
  const enc = (v) => {
    v = v < 0 ? ~(v << 1) : v << 1;
    let s = '';
    while (v >= 0x20) {
      s += String.fromCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    return s + String.fromCharCode(v + 63);
  };
  for (const [lat, lng] of pts) {
    const iLat = Math.round(lat * 1e5);
    const iLng = Math.round(lng * 1e5);
    out += enc(iLat - pLat) + enc(iLng - pLng);
    pLat = iLat;
    pLng = iLng;
  }
  return out;
}
export function decode(str) {
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
    pts.push([lat / 1e5, lng / 1e5]);
  }
  return pts;
}

// ——— OSRM ———
export async function osrm(profile, pts, { fresh = false } = {}) {
  const coords = pts.map(([lat, lng]) => `${lng.toFixed(6)},${lat.toFixed(6)}`).join(';');
  const svc = profile === 'foot' ? 'routed-foot/route/v1/foot' : 'routed-car/route/v1/driving';
  const url = `https://routing.openstreetmap.de/${svc}/${coords}?overview=full&geometries=polyline`;
  const file = join(cache, 'osrm', `${createHash('sha1').update(url).digest('hex')}.json`);
  let json;
  if (!fresh && existsSync(file)) json = JSON.parse(readFileSync(file, 'utf8'));
  else {
    for (let attempt = 0; attempt < 4; attempt++) {
      const res = await fetch(url, { headers: { 'User-Agent': 'nb2027-trip-site/1.0 (personal itinerary)' } });
      if (res.ok) {
        json = await res.json();
        break;
      }
      await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
    }
    if (!json) throw new Error(`OSRM failed ${url}`);
    writeFileSync(file, JSON.stringify(json));
    await new Promise((r) => setTimeout(r, 400));
  }
  if (json.code !== 'Ok') throw new Error(`OSRM ${json.code}`);
  return decode(json.routes[0].geometry);
}

// ——— MLIT N02 stations ———
// Romanised names for the stations the site mentions; others stay in kanji.
export const ROMAJI = {
  新宿: 'Shinjuku', 代々木上原: 'Yoyogi-Uehara', 登戸: 'Noborito', 新百合ヶ丘: 'Shin-Yurigaoka', 町田: 'Machida', 相模大野: 'Sagami-Ōno',
  海老名: 'Ebina', 本厚木: 'Hon-Atsugi', 愛甲石田: 'Aikō-Ishida', 伊勢原: 'Isehara', 鶴巻温泉: 'Tsurumaki-Onsen', 東海大学前: 'Tōkaidaigakumae',
  秦野: 'Hadano', 渋沢: 'Shibusawa', 新松田: 'Shin-Matsuda', 開成: 'Kaisei', 栢山: 'Kayama', 螢田: 'Hotaruda', 足柄: 'Ashigara', 小田原: 'Odawara',
  箱根板橋: 'Hakone-Itabashi', 風祭: 'Kazamatsuri', 入生田: 'Iriuda', 箱根湯本: 'Hakone-Yumoto', 経堂: 'Kyōdō', 成城学園前: 'Seijōgakuen-mae',
  向ヶ丘遊園: 'Mukōgaoka-Yūen', 相模大塚: 'Sagami-Ōtsuka', 座間: 'Zama', 厚木: 'Atsugi',
  早川: 'Hayakawa', 根府川: 'Nebukawa', 真鶴: 'Manazuru', 湯河原: 'Yugawara', 熱海: 'Atami', 函南: 'Kannami', 三島: 'Mishima', 沼津: 'Numazu',
  片浜: 'Katahama', 原: 'Hara', 東田子の浦: 'Higashi-Tagonoura', 吉原: 'Yoshiwara', 富士: 'Fuji', 富士川: 'Fujikawa', 新蒲原: 'Shin-Kambara',
  蒲原: 'Kambara', 由比: 'Yui', 興津: 'Okitsu', 清水: 'Shimizu', 草薙: 'Kusanagi', 東静岡: 'Higashi-Shizuoka', 静岡: 'Shizuoka',
  掛川: 'Kakegawa', 浜松: 'Hamamatsu', 新富士: 'Shin-Fuji', 池の浦: 'Ikenoura', 淀屋橋: 'Yodoyabashi',
};
const stationFile = join(cache, 'n02/UTF-8/N02-23_Station.geojson');
let stations;
/** Stations of the given [operator, line] pairs, at the middle of each platform segment. */
export function stationsForNet(netPairs) {
  stations ??= existsSync(stationFile) ? JSON.parse(readFileSync(stationFile, 'utf8')).features : [];
  const net = new Set(netPairs.map(([op, l]) => `${op}|${l}`));
  return stations
    .filter((f) => net.has(`${f.properties.N02_004}|${f.properties.N02_003}`))
    .map((f) => {
      const c = f.geometry.coordinates[Math.floor(f.geometry.coordinates.length / 2)];
      return { name: f.properties.N02_005, lat: c[1], lng: c[0] };
    });
}
