// node --test 'scripts/*.test.mjs'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { checkPlan } from './check-plan.mjs';
import { DAYS } from '../src/data/days.ts';

const withStop = (n, place, at) => {
  const days = structuredClone(DAYS);
  days.find((d) => d.n === n).items.find((i) => i.place === place).at = at;
  return days;
};
/** day `n` with its departure planned at `from` moved to `at` */
const withMove = (n, from, at) => {
  const days = structuredClone(DAYS);
  days.find((d) => d.n === n).items.find((i) => i.type === 'move' && i.at === from).at = at;
  return days;
};

test('the shipped plan passes and exits 0', () => {
  assert.equal(spawnSync('node', ['scripts/check-plan.mjs']).status, 0);
});
test('a stop moved before it can be reached fails', () => {
  const days = structuredClone(DAYS);
  days.find((d) => d.n === 2).items.find((i) => i.place === 'nezu-shrine').at = '6:00';
  const r = checkPlan(days);
  assert.equal(r.late, 1);
  assert.match(r.lines.join('\n'), /302 min short/);
});
test('a stop a little behind the clock is within the grace, not late and not negative spare', () => {
  const r = checkPlan(withStop(2, 'nezu-shrine', '11:00'));
  const out = r.lines.join('\n');
  assert.equal(r.late, 0);
  assert.equal(r.withinGrace, 1);
  assert.ok(r.lines.some((l) => l.split('\n').includes('  ≈ 11:00 Nezu Jinja: 2 min late, within the 2-min grace')), out);
  assert.ok(r.lines.at(-1).endsWith('every timed stop can be reached (1 within the grace)'), out);
  assert.doesNotMatch(out, /only -\d+ min to spare/);
});
test('the tail of a walk is counted before the next ride', () => {
  // Day 10: the loop up Fushimi Inari and back to the station, then the Keihan at 8:30 (item 4).
  // The same value is pinned in PlanFeasibilityTests.swift: the two clocks must agree on it.
  const ready = checkPlan(DAYS).ready['10:4'];
  assert.ok(Math.abs(ready - 496.858) < 0.001, `ready at ${ready}`);
});
test('the command fails on a plan that cannot be kept', () => {
  // the command itself, in its own process, on Day 2 with Nezu Jinja moved to 6:00
  const script = `
    import { main } from ${JSON.stringify(new URL('./check-plan.mjs', import.meta.url).href)};
    import { DAYS, ALT_DAYS } from ${JSON.stringify(new URL('../src/data/days.ts', import.meta.url).href)};
    DAYS.find((d) => d.n === 2).items.find((i) => i.place === 'nezu-shrine').at = '6:00';
    main([...DAYS, ...ALT_DAYS]);`;
  const r = spawnSync('node', ['--input-type=module', '-e', script], { encoding: 'utf8' });
  assert.match(r.stdout, /302 min short/, r.stderr);
  assert.equal(r.status, 1);
});
test('a departure more than a minute behind the clock is late, less is not', () => {
  // Day 10's Keihan (planned 8:30) can leave at 8:16.86 at the earliest
  const late = checkPlan(withMove(10, '8:30', '8:15')); // 1.86 min behind
  assert.equal(late.late, 1);
  assert.match(late.lines.join('\n'), /! 8:15 Keihan st-fushimi-inari → st-tambabashi: free only at 8:17 \(2 min late\)/);
  const kept = checkPlan(withMove(10, '8:30', '8:16')); // 0.86 min behind
  assert.equal(kept.late, 0);
  assert.doesNotMatch(kept.lines.join('\n'), /Keihan/);
});
