// Every plan item has an id written in the data (src/data/days.ts), and the app keys what it records
// about a visit — done, skipped, a reminder, a geofence — by that id. This checks that (1) every item
// has one, unique within its day, and (2) no visit changed its id since the base: an id that is gone
// while the same place (a stop) or the same from>to (a move) carries a new id looks like a rename and
// fails unless ID_RENAMES (src/data/id-renames.ts) maps it. A visit removed or added on its own passes.
//
// Usage: node scripts/check-ids.mjs [base]   (base: a git ref, default origin/main; its exported
// ios/JP27/Resources/Trip/trip.json is the base, skipped when it has none or no ids yet)

import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { DAYS, ALT_DAYS, dayKey } from '../src/data/days.ts';
import { ID_RENAMES } from '../src/data/id-renames.ts';

const root = new URL('..', import.meta.url).pathname;
const TRIP = 'ios/JP27/Resources/Trip/trip.json';

/** Days as the check sees them, `{ key, items }`, from the source… */
export const fromSource = (days) => days.map((d) => ({ key: dayKey(d), items: d.items }));
/** …or from an exported trip.json (items carry the same type, id, place, leg.from, leg.to). */
export const fromExport = (trip) => [...(trip.days ?? []), ...(trip.altDays ?? [])].map((d) => ({ key: d.key, items: d.items }));

/** What a visit is at, whatever its id: the place of a stop, from>to of a move. */
const anchor = (it) => (it.type === 'stop' ? (it.place ? `s:${it.place}` : null) : `m:${it.leg.from}>${it.leg.to}`);

/** (1) every item has an id, unique within its day */
export function problems(days) {
  const out = [];
  for (const d of days) {
    const seen = new Set();
    d.items.forEach((it, i) => {
      if (!it.id) out.push(`day ${d.key} item ${i}: no id`);
      else if (seen.has(it.id)) out.push(`day ${d.key}: ${it.id} is used twice — give one of them a key`);
      seen.add(it.id);
    });
  }
  return out;
}

/** ID_RENAMES names days that exist, ids those days no longer have, and targets they do have */
export function renameProblems(head, renames = ID_RENAMES) {
  const out = [];
  const days = new Map(head.map((d) => [d.key, new Set(d.items.map((i) => i.id))]));
  for (const [key, map] of Object.entries(renames)) {
    const ids = days.get(key);
    if (!ids) {
      out.push(`ID_RENAMES: no day ${key}`);
      continue;
    }
    for (const [from, to] of Object.entries(map)) {
      if (ids.has(from)) out.push(`ID_RENAMES['${key}']: ${from} is still an id of day ${key}`);
      if (!ids.has(to)) out.push(`ID_RENAMES['${key}']: ${from} → ${to}, but day ${key} has no ${to}`);
    }
  }
  return out;
}

/** (2) ids gone from `base` while their place or from>to carries a new id in `head`, not renamed */
export function compare(base, head, renames = ID_RENAMES) {
  const out = [];
  const heads = new Map(head.map((d) => [d.key, d]));
  for (const b of base) {
    const h = heads.get(b.key);
    if (!h) continue;
    const before = new Set(b.items.map((i) => i.id));
    const now = new Set(h.items.map((i) => i.id));
    const renamed = renames[b.key] ?? {};
    const targets = new Set(Object.values(renamed));
    for (const it of b.items) {
      if (!it.id || now.has(it.id) || renamed[it.id]) continue;
      const a = anchor(it);
      if (!a) continue;
      const fresh = h.items.filter((x) => anchor(x) === a && !before.has(x.id) && !targets.has(x.id)).map((x) => x.id);
      if (fresh.length)
        out.push(`day ${b.key}: ${it.id} is gone while ${fresh.join(', ')} is new at the same ${it.type === 'stop' ? 'place' : 'from>to'} — if it is the same visit, map it in ID_RENAMES['${b.key}']`);
    }
  }
  return out;
}

/** The base's exported days, or why there is nothing to compare with. Throws when `ref` is no commit. */
export function baseDays(ref) {
  const git = (...args) => spawnSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 1 << 28 });
  if (git('rev-parse', '--verify', '--quiet', `${ref}^{commit}`).status !== 0) throw new Error(`base ${ref} is not a commit in this checkout (CI checks out with fetch-depth: 0)`);
  if (git('cat-file', '-e', `${ref}:${TRIP}`).status !== 0) return { skip: `${ref} has no ${TRIP}` };
  const shown = git('show', `${ref}:${TRIP}`);
  if (shown.status !== 0) throw new Error(`git show ${ref}:${TRIP}: ${shown.stderr.trim()}`);
  const days = fromExport(JSON.parse(shown.stdout));
  if (!days.some((d) => d.items.some((i) => i.id))) return { skip: `${ref}'s ${TRIP} has no item ids yet` };
  return { days };
}

export function main(ref = 'origin/main', days = [...DAYS, ...ALT_DAYS]) {
  const head = fromSource(days);
  const errors = [...problems(head), ...renameProblems(head)];
  let base;
  try {
    base = baseDays(ref);
  } catch (e) {
    console.log(`! ${e.message}`);
    process.exitCode = 1;
    return;
  }
  if (base.days) errors.push(...compare(base.days, head));
  for (const e of errors) console.log(`! ${e}`);
  const count = head.reduce((n, d) => n + d.items.length, 0);
  console.log(
    errors.length
      ? `${errors.length} problem(s) with item ids`
      : `${count} items in ${head.length} days: every id is unique in its day; ${base.days ? `none changed since ${ref}` : `comparison skipped: ${base.skip}`}`,
  );
  if (errors.length) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main(process.argv[2] || undefined);
