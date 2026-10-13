// Small geometry helpers shared by the build (Astro) and the browser.

export type LatLng = [number, number];

export function decodePolyline(str: string): LatLng[] {
  const pts: LatLng[] = [];
  let i = 0;
  let lat = 0;
  let lng = 0;
  const next = () => {
    let shift = 0;
    let result = 0;
    let b: number;
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

const rad = (d: number) => (d * Math.PI) / 180;

export function haversineKm([lat1, lng1]: LatLng, [lat2, lng2]: LatLng) {
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371.0088 * Math.asin(Math.sqrt(a));
}

/** Bounds as [[west, south], [east, north]] */
export function boundsOf(points: LatLng[]): [[number, number], [number, number]] {
  let w = Infinity;
  let s = Infinity;
  let e = -Infinity;
  let n = -Infinity;
  for (const [lat, lng] of points) {
    if (lng < w) w = lng;
    if (lng > e) e = lng;
    if (lat < s) s = lat;
    if (lat > n) n = lat;
  }
  return [
    [w, s],
    [e, n],
  ];
}

/** Distance from a point to a polyline, km (equirectangular, fine at city scale). */
export function distanceToLineKm(p: LatLng, line: LatLng[]) {
  const k = Math.cos(rad(p[0]));
  const toXY = ([lat, lng]: LatLng) => [lng * k * 111.32, lat * 110.57];
  const [px, py] = toXY(p);
  let best = Infinity;
  for (let i = 1; i < line.length; i++) {
    const [ax, ay] = toXY(line[i - 1]);
    const [bx, by] = toXY(line[i]);
    const dx = bx - ax;
    const dy = by - ay;
    const len2 = dx * dx + dy * dy || 1e-12;
    const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
    const d = Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
    if (d < best) best = d;
  }
  return best;
}

/** Project lat/lng sets into an SVG box keeping aspect; returns path strings. */
export function sparkPaths(lines: LatLng[][], width: number, height: number, pad = 4) {
  const all = lines.flat();
  if (!all.length) return { paths: [] as string[], project: (_: LatLng) => [0, 0] as [number, number] };
  const k = Math.cos(rad(all.reduce((s, p) => s + p[0], 0) / all.length));
  const xs = all.map((p) => p[1] * k);
  const ys = all.map((p) => p[0]);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  const spanX = maxX - minX || 1e-6;
  const spanY = maxY - minY || 1e-6;
  const scale = Math.min((width - 2 * pad) / spanX, (height - 2 * pad) / spanY);
  const offX = (width - spanX * scale) / 2;
  const offY = (height - spanY * scale) / 2;
  const project = ([lat, lng]: LatLng): [number, number] => [offX + (lng * k - minX) * scale, height - (offY + (lat - minY) * scale)];
  const paths = lines.map((pts) =>
    pts
      .map((p, i) => {
        const [x, y] = project(p);
        return `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`;
      })
      .join(''),
  );
  return { paths, project };
}

export function encodePolyline(pts: LatLng[]) {
  let out = '';
  let pLat = 0;
  let pLng = 0;
  const enc = (v: number) => {
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

const DIRS = ['Bắc', 'Đông Bắc', 'Đông', 'Đông Nam', 'Nam', 'Tây Nam', 'Tây', 'Tây Bắc'];
export const compass = (bearing: number) => DIRS[Math.round(bearing / 45) % 8];
