// Build real-world geometry for every leg of the trip.
//
//   rail / subway / shinkansen / cable car → shortest path over the MLIT N02
//     railway network (国土数値情報 鉄道データ), restricted to the line's operators
//   walk → OSRM foot profile, bus / shuttle → OSRM car profile
//     (routing.openstreetmap.de, OpenStreetMap data)
//   ferry / lake cruise → smoothed explicit path, ropeway → straight spans
//
// Output: src/data/geo.gen.ts  { [legId]: { p: encodedPolyline, km } }
// Responses are cached in .cache/ so re-runs are fast and polite.
//
// Usage: node scripts/build-geo.mjs [--fresh]

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { allLegs } from '../src/data/days.ts';
import { LINES } from '../src/data/lines.ts';
import { place } from '../src/data/catalog.ts';
import { encode, haversine, lengthKm, osrm as osrmCached, simplify } from './geo-tools.mjs';

const root = new URL('..', import.meta.url).pathname;
const cache = join(root, '.cache');
const fresh = process.argv.includes('--fresh');
const osrm = (profile, pts) => osrmCached(profile, pts, { fresh });

/** Centripetal-ish Catmull–Rom smoothing for water paths. */
function smooth(pts, steps = 8) {
  if (pts.length < 3) return pts;
  const out = [];
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] ?? pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] ?? p2;
    for (let s = 0; s < steps; s++) {
      const t = s / steps;
      const t2 = t * t;
      const t3 = t2 * t;
      out.push([0, 1].map((k) => 0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2 + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)));
    }
  }
  out.push(pts[pts.length - 1]);
  return out;
}

// ——— MLIT N02 railway network ———
function loadN02() {
  const dir = join(cache, 'n02');
  const file = join(dir, 'UTF-8', 'N02-23_RailroadSection.geojson');
  if (!existsSync(file)) {
    mkdirSync(dir, { recursive: true });
    const zip = join(cache, 'n02.zip');
    console.log('downloading MLIT N02-23 railway data…');
    execFileSync('curl', ['-sS', '-L', '-o', zip, 'https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-23/N02-23_GML.zip']);
    execFileSync('unzip', ['-o', '-q', zip, '-d', dir]);
  }
  return JSON.parse(readFileSync(file, 'utf8')).features;
}

let railFeatures;
const graphs = new Map();
const key = ([lat, lng]) => `${lat.toFixed(5)},${lng.toFixed(5)}`;

function railGraph(net) {
  const id = JSON.stringify(net);
  if (graphs.has(id)) return graphs.get(id);
  railFeatures ??= loadN02();
  const allowed = new Set(net.map(([op, line]) => `${op}|${line}`));
  const nodes = new Map(); // key -> {p, edges: Map<key, km>}
  const node = (p) => {
    const k = key(p);
    if (!nodes.has(k)) nodes.set(k, { p, edges: new Map() });
    return k;
  };
  const link = (a, b) => {
    if (a === b) return;
    const d = haversine(nodes.get(a).p, nodes.get(b).p);
    nodes.get(a).edges.set(b, d);
    nodes.get(b).edges.set(a, d);
  };
  const ends = [];
  for (const f of railFeatures) {
    const p = f.properties;
    if (!allowed.has(`${p.N02_004}|${p.N02_003}`)) continue;
    const lines = f.geometry.type === 'LineString' ? [f.geometry.coordinates] : f.geometry.coordinates;
    for (const coords of lines) {
      let prev = null;
      coords.forEach(([lng, lat], i) => {
        const k = node([lat, lng]);
        if (prev) link(prev, k);
        prev = k;
        if (i === 0 || i === coords.length - 1) ends.push(k);
      });
    }
  }
  // Stitch section ends that do not share an exact vertex (≤ 60 m apart).
  const grid = new Map();
  const cell = ([lat, lng]) => `${Math.floor(lat / 0.001)},${Math.floor(lng / 0.001)}`;
  for (const [k, n] of nodes) {
    const c = cell(n.p);
    if (!grid.has(c)) grid.set(c, []);
    grid.get(c).push(k);
  }
  for (const k of ends) {
    const n = nodes.get(k);
    const [cy, cx] = cell(n.p).split(',').map(Number);
    let best = null;
    let bestD = 0.06;
    for (let dy = -1; dy <= 1; dy++)
      for (let dx = -1; dx <= 1; dx++)
        for (const o of grid.get(`${cy + dy},${cx + dx}`) ?? []) {
          if (o === k || n.edges.has(o)) continue;
          const d = haversine(n.p, nodes.get(o).p);
          if (d < bestD && nodes.get(o).edges.size) {
            bestD = d;
            best = o;
          }
        }
    if (best && n.edges.size < 2) link(k, best);
  }
  graphs.set(id, nodes);
  return nodes;
}

function nearestNode(nodes, p) {
  let best = null;
  let bestD = Infinity;
  for (const [k, n] of nodes) {
    const d = haversine(p, n.p);
    if (d < bestD) {
      bestD = d;
      best = k;
    }
  }
  return [best, bestD];
}

function dijkstra(nodes, src, dst) {
  const dist = new Map([[src, 0]]);
  const prev = new Map();
  const done = new Set();
  // small binary heap
  const heap = [[0, src]];
  const push = (item) => {
    heap.push(item);
    let i = heap.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (heap[p][0] <= heap[i][0]) break;
      [heap[p], heap[i]] = [heap[i], heap[p]];
      i = p;
    }
  };
  const pop = () => {
    const top = heap[0];
    const last = heap.pop();
    if (heap.length) {
      heap[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
        if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
        if (m === i) break;
        [heap[m], heap[i]] = [heap[i], heap[m]];
        i = m;
      }
    }
    return top;
  };
  while (heap.length) {
    const [d, k] = pop();
    if (done.has(k)) continue;
    done.add(k);
    if (k === dst) break;
    for (const [o, w] of nodes.get(k).edges) {
      const nd = d + w;
      if (nd < (dist.get(o) ?? Infinity)) {
        dist.set(o, nd);
        prev.set(o, k);
        push([nd, o]);
      }
    }
  }
  if (!done.has(dst)) return null;
  const path = [];
  for (let k = dst; k; k = prev.get(k)) path.push(nodes.get(k).p);
  return path.reverse();
}

function railPath(net, from, to) {
  const nodes = railGraph(net);
  const [a, da] = nearestNode(nodes, from);
  const [b, db] = nearestNode(nodes, to);
  if (da > 0.6 || db > 0.6) console.warn(`  station far from track (${da.toFixed(2)} / ${db.toFixed(2)} km)`);
  const path = dijkstra(nodes, a, b);
  if (!path) throw new Error('no rail path');
  return path;
}

// ——— build ———
const pt = (ref) => (Array.isArray(ref) ? ref : [place(ref).lat, place(ref).lng]);

const out = {};
const seen = new Set();
for (const leg of allLegs()) {
  if (seen.has(leg.id)) continue;
  seen.add(leg.id);
  const line = LINES[leg.line];
  const a = pt(leg.from);
  const b = pt(leg.to);
  let pts;
  try {
    if (line.net) {
      pts = railPath(line.net, a, b);
      // attach the exact station points so the line meets the markers
      pts = [a, ...pts, b];
    } else if (leg.path) {
      pts = line.mode === 'ropeway' ? leg.path : smooth(leg.path);
    } else if (line.mode === 'walk') {
      pts = await osrm('foot', [a, ...(leg.via ?? []).map(pt), b]);
      pts = [a, ...pts, b];
    } else {
      pts = await osrm('car', [a, ...(leg.via ?? []).map(pt), b]);
      pts = [a, ...pts, b];
    }
  } catch (e) {
    console.warn(`! ${leg.id}: ${e.message} — straight line used`);
    pts = [a, b];
  }
  const km = lengthKm(pts);
  const tol = km > 30 ? 0.00025 : km > 5 ? 0.00008 : 0.00002;
  const simple = simplify(pts, tol);
  out[leg.id] = { p: encode(simple), km: Math.round(km * 100) / 100 };
  console.log(`${leg.line.padEnd(13)} ${leg.from} → ${leg.to}  ${km.toFixed(2)} km  ${simple.length} pts`);
}

const header = '// Generated by scripts/build-geo.mjs — do not edit by hand.\n';
writeFileSync(
  join(root, 'src/data/geo.gen.ts'),
  `${header}export const GEO: Record<string, { p: string; km: number }> = ${JSON.stringify(out, null, 1)};\n`,
);
console.log(`\n${Object.keys(out).length} legs written`);
