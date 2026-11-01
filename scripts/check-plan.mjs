// Can the plan actually be walked? For each day, run a clock through the timeline: walking time from
// the slope-aware model (walk.gen.ts), transit from each leg's stated lower bound plus a wait when no
// departure time is given, and a minimum stay at each stop. Report every stop or departure planned
// earlier than it can be reached, and the tight ones.
//
// Usage: node scripts/check-plan.mjs   (after build-walk)

import { DAYS, ALT_DAYS } from '../src/data/days.ts';
import { LINES } from '../src/data/lines.ts';
import { place } from '../src/data/catalog.ts';
import { GEO } from '../src/data/geo.gen.ts';
import { WALK_LEGS } from '../src/data/walk.gen.ts';
import { decode, haversine } from './geo-tools.mjs';

const toMin = (t) => {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
};
const fmt = (m) => `${Math.floor(m / 60)}:${String(Math.round(m % 60)).padStart(2, '0')}`;

/** "1 giờ 40" → 100, "20–25, đổi…" → 20, "60–90 tính cả chờ" → 60 */
function statedMin(s) {
  if (!s) return null;
  const h = /(\d+)\s*giờ\s*(\d+)?/.exec(s);
  if (h) return Number(h[1]) * 60 + Number(h[2] ?? 0);
  const n = /(\d+)/.exec(s);
  return n ? Number(n[1]) : null;
}

// minimum time spent at a stop (minutes)
const DWELL = {
  kiyomizudera: 45, todaiji: 40, 'ise-naiku': 50, 'ise-geku': 40, 'meiji-jingu': 40, sensoji: 40, 'otagi-nenbutsuji': 40,
  'fushimi-sake': 60, 'onshi-hakone-park': 30, owakudani: 30, 'fs-chureito-pagoda': 30, 'fs-oishi-park': 45, 'wargo-gion': 30,
  doguyasuji: 60, 'takashimaya-osaka': 40, 'loft-umeda': 40, 'toshijima-wagu': 30, 'toshijima-toshi': 30,
  // places you walk through or stop at for a photo
  togetsukyo: 10, 'saga-toriimoto': 20, 'bamboo-grove': 20, hozenji: 20, 'fs-lawson-kawaguchiko-ekimae': 15, 'fs-honcho-dori': 15,
  manseibashi: 20, 'yanaka-ginza': 40, 'sumida-river': 15, nihonbashi: 15, 'gion-shirakawa': 20, okazaki: 20, 'uji-bridge': 10,
  'hakone-sekisho': 15, 'cedar-avenue': 10, 'hakone-shrine': 15,
};
function dwell(item) {
  const p = item.place ? place(item.place) : null;
  if (p && DWELL[p.id] != null) return DWELL[p.id];
  if (/trả phòng|Ăn sáng|Buffet/i.test(item.title)) return 40;
  if (/Nhận phòng/i.test(item.title)) return 15;
  if (/Gửi/i.test(item.title)) return 10;
  if (!p) return 10;
  if (p.kind === 'food') return item.cost >= 5000 ? 60 : item.cost >= 2000 ? 45 : 20;
  if (p.kind === 'shop') return 30;
  if (p.kind === 'station') return 10;
  if (p.kind === 'stay') return 10;
  return item.optional ? 20 : 30;
}

const WAIT = { subway: 4, train: 6, shinkansen: 8, bus: 8, shuttle: 6, ferry: 10, cruise: 10, ropeway: 5, cable: 6 };

/** distance along a polyline to the point nearest p */
function along(pts, p) {
  let acc = 0;
  let best = { off: Infinity, km: 0 };
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1];
    const b = pts[i];
    const seg = haversine(a, b);
    for (let t = 0; t <= 1; t += 0.1) {
      const q = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      const off = haversine(q, p);
      if (off < best.off) best = { off, km: acc + seg * t };
    }
    acc += seg;
  }
  return best.km;
}

let problems = 0;
for (const day of [...DAYS, ...ALT_DAYS]) {
  const out = [];
  let clock = null; // free at this time
  let pendingWalk = null; // a walk that passes later stops: { pts, km, min, doneKm }
  for (const it of day.items) {
    if (it.type === 'move') {
      const l = it.leg;
      const mode = LINES[l.line].mode;
      let dur;
      if (mode === 'walk') {
        const w = WALK_LEGS[l.id];
        const pts = GEO[l.id]?.p ? decode(GEO[l.id].p) : null;
        const passes = (l.via ?? []).some((v) => typeof v === 'string' && day.items.some((x) => x.type === 'stop' && x.place === v));
        if (passes && pts && w) {
          // time is spent as the stops along it come up
          pendingWalk = { pts, km: w.km, min: w.min, doneKm: 0, to: l.to };
          dur = 0;
        } else dur = w?.min ?? statedMin(l.min) ?? 5;
      } else {
        dur = statedMin(l.min) ?? 10;
        if (!it.at) dur += WAIT[mode] ?? 5;
      }
      if (it.at && clock != null && toMin(it.at) < clock - 1) {
        out.push(`  ! ${it.at} ${LINES[l.line].name} ${l.from} → ${l.to}: free only at ${fmt(clock)} (${Math.round(clock - toMin(it.at))} min late)`);
        problems++;
      }
      if (it.at) clock = Math.max(clock ?? 0, toMin(it.at));
      clock = (clock ?? 0) + dur;
      continue;
    }
    // a stop
    if (pendingWalk && it.place) {
      const p = place(it.place);
      const km = along(pendingWalk.pts, [p.lat, p.lng]);
      const part = Math.max(0, km - pendingWalk.doneKm);
      clock = (clock ?? 0) + (pendingWalk.min * part) / pendingWalk.km;
      pendingWalk.doneKm = Math.max(pendingWalk.doneKm, km);
      if (it.place === pendingWalk.to) pendingWalk = null;
    }
    if (it.at) {
      const at = toMin(it.at);
      if (clock != null && at < clock - 2) {
        out.push(`  ! ${it.at} ${it.title}: earliest arrival ${fmt(clock)} (${Math.round(clock - at)} min short)`);
        problems++;
      } else if (clock != null && at - clock < 3 && !/^(Gửi|Nhận phòng)/.test(it.title)) {
        out.push(`  ~ ${it.at} ${it.title}: only ${Math.round(at - clock)} min to spare`);
      }
      clock = Math.max(clock ?? at, at);
    }
    clock = (clock ?? 0) + dwell(it);
  }
  // a walk whose last stretch (after its last stop) was never counted
  if (out.length) console.log(`Day ${day.id ?? day.n} — ${day.title}\n${out.join('\n')}`);
}
console.log(problems ? `\n${problems} stops or departures planned earlier than they can be reached` : '\nevery timed stop can be reached');
