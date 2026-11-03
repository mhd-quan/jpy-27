// Every plan item has an id written in the data (src/data/days.ts), and the app keys what it records
// about a visit — done, skipped, a reminder, a geofence — by that id. This checks that (1) every item
// has one, unique within its day, and a day that comes back to a place (or a from>to) keys every visit
// there; (2) no visit changed its id since the base: an id that is gone while the same place (a stop),
// the same from>to (a move) or, for stops without a place, another such stop carries a new id looks like
// a rename and fails unless ID_RENAMES (src/data/id-renames.ts) maps it. A visit removed or added on its
// own passes. (3) ID_RENAMES names ids the day no longer has, targets it has, and keeps every entry the
// base shipped (a phone can skip versions).
//
// Usage: node scripts/check-ids.mjs [base…]   (git refs, default origin/main; the base is the first whose
// exported ios/JP27/Resources/Trip/trip.json has item ids; with none, the comparison is skipped)
//
// CI compares a push with the commit before it and a pull request with its base branch. Until main
// carries ids, a pull request into main prints the skip; and as each push is compared with the one
// before, a red push can be followed by a green one — the red run stays in the branch history.

import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { DAYS, ALT_DAYS, dayKey } from '../src/data/days.ts';
import { ID_RENAMES } from '../src/data/id-renames.ts';

const root = new URL('..', import.meta.url).pathname;
export const TRIP = 'ios/JP27/Resources/Trip/trip.json';

/** Days as the check sees them, `{ key, items }`, from the source… */
export const fromSource = (days) => days.map((d) => ({ key: dayKey(d), items: d.items }));
/** …or from an exported trip.json (items carry the same type, id, place, leg.from, leg.to). */
export const fromExport = (trip) => [...(trip.days ?? []), ...(trip.altDays ?? [])].map((d) => ({ key: d.key, items: d.items }));

/**
 * What a visit is at, whatever its id: the place of a stop, from>to of a move, `s::` for every stop
 * without a place. For a place or a from>to it is also the bare default id.
 */
const anchor = (it) => (it.type === 'stop' ? `s:${it.place ?? ':'}` : `m:${it.leg.from}>${it.leg.to}`);

/** (1) every item has an id, unique within its day; a place or from>to the day repeats keys every visit */
export function problems(days) {
  const out = [];
  for (const d of days) {
    const seen = new Set();
    const count = new Map();
    for (const it of d.items) count.set(anchor(it), (count.get(anchor(it)) ?? 0) + 1);
    d.items.forEach((it, i) => {
      if (!it.id) out.push(`day ${d.key} item ${i}: no id`);
      else if (seen.has(it.id)) out.push(`day ${d.key}: ${it.id} is used twice — give one of them a key`);
      else if (it.id === anchor(it) && count.get(anchor(it)) > 1) out.push(`day ${d.key}: ${it.id} is visited more than once — give every visit a key`);
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

/** every rename the base shipped is still there: a phone that skipped that version still needs it */
export function keptRenames(baseRenames, renames = ID_RENAMES) {
  const out = [];
  for (const [key, map] of Object.entries(baseRenames ?? {}))
    for (const from of Object.keys(map)) if (!renames[key]?.[from]) out.push(`ID_RENAMES['${key}']: ${from} was shipped and is gone — keep it (point it at the id the visit has now)`);
  return out;
}

/** (2) ids gone from `base` while their anchor carries a new id in `head`, not renamed */
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
      const fresh = h.items.filter((x) => anchor(x) === a && !before.has(x.id) && !targets.has(x.id)).map((x) => x.id);
      if (fresh.length)
        out.push(
          `day ${b.key}: ${it.id} is gone while ${fresh.join(', ')} is new at the same ${it.type === 'move' ? 'from>to' : it.place ? 'place' : 'placeless stop'}` +
            ` — map in ID_RENAMES['${b.key}'] only an old id whose visit is the same one (a visit removed needs no entry)`,
        );
    }
  }
  return out;
}

/** The base's exported days and renames, or why there is none. Throws when `ref` is no commit or git fails. */
export function baseDays(ref) {
  const git = (...args) => spawnSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 1 << 28 });
  if (git('rev-parse', '--verify', '--quiet', `${ref}^{commit}`).status !== 0) throw new Error(`base ${ref} is not a commit in this checkout (CI checks out with fetch-depth: 0)`);
  const listed = git('ls-tree', '--name-only', ref, '--', TRIP);
  if (listed.status !== 0) throw new Error(`git ls-tree ${ref}: ${listed.stderr.trim()}`);
  if (!listed.stdout.trim()) return { skip: `${ref} has no ${TRIP}` };
  const shown = git('show', `${ref}:${TRIP}`);
  if (shown.status !== 0) throw new Error(`git show ${ref}:${TRIP}: ${shown.stderr.trim()}`);
  const trip = JSON.parse(shown.stdout);
  const days = fromExport(trip);
  if (!days.some((d) => d.items.some((i) => i.id))) return { skip: `${ref}'s ${TRIP} has no item ids yet` };
  return { days, renames: trip.idRenames ?? {} };
}

/** Checks `days` against the first of `refs` whose trip.json has ids; sets process.exitCode 1 on a problem. */
export function main(refs = ['origin/main'], days = [...DAYS, ...ALT_DAYS], log = console.log, load = baseDays) {
  const head = fromSource(days);
  const errors = [...problems(head), ...renameProblems(head)];
  const skipped = [];
  let base;
  try {
    for (const ref of [refs].flat()) {
      const b = load(ref);
      if (b.days) {
        base = { ref, ...b };
        break;
      }
      skipped.push(b.skip);
    }
  } catch (e) {
    log(`! ${e.message}`);
    process.exitCode = 1;
    return;
  }
  if (base) errors.push(...compare(base.days, head), ...keptRenames(base.renames));
  for (const e of errors) log(`! ${e}`);
  const count = head.reduce((n, d) => n + d.items.length, 0);
  log(
    errors.length
      ? `${errors.length} problem(s) with item ids`
      : `${count} items in ${head.length} days: every id is unique in its day; ${base ? `none changed since ${base.ref}` : `comparison skipped: ${skipped.join('; ')}`}`,
  );
  if (errors.length) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main(process.argv.length > 2 ? process.argv.slice(2) : undefined);
