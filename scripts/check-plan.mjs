// Can the plan actually be walked? For each day, run a clock through the timeline: walking time from
// the slope-aware model (walk.gen.ts), transit from each leg's stated lower bound plus a wait when no
// departure time is given, and a minimum stay at each stop. Report every stop or departure planned
// earlier than it can be reached, and the tight ones. Exits 1 when anything is late by more than its
// grace (plan-rules.mjs), so CI fails on a plan that cannot be kept.
//
// Usage: node scripts/check-plan.mjs   (after build-walk)

import { pathToFileURL } from 'node:url';
import { DAYS, ALT_DAYS } from '../src/data/days.ts';
import { LINES } from '../src/data/lines.ts';
import { place } from '../src/data/catalog.ts';
import { GEO } from '../src/data/geo.gen.ts';
import { WALK_LEGS } from '../src/data/walk.gen.ts';
import { decode, haversine } from './geo-tools.mjs';
import { DWELL, GRACE, TIGHT, WAIT } from './plan-rules.mjs';

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

/**
 * Runs the clock through `days`. `lines` is what the command prints; `late` counts the stops and
 * departures planned earlier than they can be reached, `withinGrace` the stops behind the clock by
 * no more than their grace, `ready` when each timed item can begin, by "day:index" (minutes).
 */
export function checkPlan(days) {
  const lines = [];
  let late = 0;
  let withinGrace = 0;
  const ready = {};
  for (const day of days) {
    const out = [];
    let clock = null; // free at this time
    let pendingWalk = null; // a walk that passes later stops: { pts, km, min, doneKm }
    for (const [index, it] of day.items.entries()) {
      const key = `${day.id ?? day.n}:${index}`;
      if (it.type === 'move') {
        const l = it.leg;
        const mode = LINES[l.line].mode;
        let dur;
        if (mode !== 'walk' && pendingWalk) {
          // the rest of a walk that passed stops, from the last of them to where it ends, comes
          // before the ride (walk km and polyline km are measured apart: never below zero)
          clock = (clock ?? 0) + (pendingWalk.min * Math.max(0, pendingWalk.km - pendingWalk.doneKm)) / pendingWalk.km;
          pendingWalk = null;
        }
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
        if (it.at && clock != null) ready[key] = clock;
        if (it.at && clock != null && toMin(it.at) < clock - GRACE.move) {
          out.push(`  ! ${it.at} ${LINES[l.line].name} ${l.from} → ${l.to}: free only at ${fmt(clock)} (${Math.round(clock - toMin(it.at))} min late)`);
          late++;
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
        if (clock != null) ready[key] = clock;
        const errand = /^(Gửi|Nhận phòng)/.test(it.title);
        if (clock != null && at < clock - GRACE.stop) {
          out.push(`  ! ${it.at} ${it.title}: earliest arrival ${fmt(clock)} (${Math.round(clock - at)} min short)`);
          late++;
        } else if (clock != null && at < clock && !errand) {
          out.push(`  ≈ ${it.at} ${it.title}: ${Math.round(clock - at)} min late, within the ${GRACE.stop}-min grace`);
          withinGrace++;
        } else if (clock != null && at - clock < TIGHT && !errand) {
          out.push(`  ~ ${it.at} ${it.title}: only ${Math.round(at - clock)} min to spare`);
        }
        clock = Math.max(clock ?? at, at);
      }
      clock = (clock ?? 0) + dwell(it);
    }
    // a walk still pending here ended the day: nothing after it reads the clock, so its last
    // stretch is not added
    if (out.length) lines.push(`Day ${day.id ?? day.n} — ${day.title}\n${out.join('\n')}`);
  }
  const grace = withinGrace ? ` (${withinGrace} within the grace)` : '';
  lines.push(late ? `\n${late} stops or departures planned earlier than they can be reached` : `\nevery timed stop can be reached${grace}`);
  return { lines, late, withinGrace, ready };
}

/** The command: prints the check of `days` and fails the process when anything is late. */
export function main(days = [...DAYS, ...ALT_DAYS]) {
  const { lines, late } = checkPlan(days);
  console.log(lines.join('\n'));
  process.exitCode = late > 0 ? 1 : 0;
}

// run as a command, not when a test imports it
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
