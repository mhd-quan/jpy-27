// node --test 'scripts/*.test.mjs'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { compare, fromExport, fromSource, keptRenames, main, problems, renameProblems, TRIP } from './check-ids.mjs';
import { DAYS, ALT_DAYS, dayKey, leg, stop, walk } from '../src/data/days.ts';

/** day 8 as the check sees it, with `edit` applied to a copy of its items */
const day8 = (edit = (items) => items) => {
  const d = structuredClone(DAYS.find((x) => x.n === 8));
  d.items = edit(d.items);
  return fromSource([d]);
};
const items8 = () => DAYS.find((d) => d.n === 8).items;
const withId = (from, to) => (items) => items.map((i) => (i.id === from ? { ...i, id: to } : i));

test('every item has an id, unique within its day', () => {
  for (const d of [...DAYS, ...ALT_DAYS]) {
    const ids = d.items.map((i) => i.id);
    assert.equal(new Set(ids).size, ids.length, `day ${dayKey(d)}`);
    assert.ok(ids.every(Boolean));
  }
  assert.deepEqual(problems(fromSource([...DAYS, ...ALT_DAYS])), []);
});

test('day 8 rent and return are two visits', () => {
  const d8 = DAYS.find((d) => d.n === 8);
  assert.deepEqual(d8.items.filter((i) => i.place === 'wargo-gion').map((i) => [i.id, i.at]), [['s:wargo-gion:rent', '9:30'], ['s:wargo-gion:return', '14:30']]);
});

test('day 1 leaving the bags and checking in are two visits', () => {
  const d1 = DAYS.find((d) => d.n === 1);
  assert.deepEqual(d1.items.filter((i) => i.place === 'resol-akihabara').map((i) => [i.id, i.at]), [['s:resol-akihabara:bags', '12:00'], ['s:resol-akihabara:checkin', '15:00']]);
});

test('an id that disappears while its place stays fails without a rename', () => {
  const base = day8();
  const head = day8(withId('s:wargo-gion:return', 's:wargo-gion:back'));
  const errors = compare(base, head, {});
  assert.equal(errors.length, 1, errors.join('\n'));
  assert.match(errors[0], /day 8: s:wargo-gion:return is gone while s:wargo-gion:back is new/);
  const renames = { 8: { 's:wargo-gion:return': 's:wargo-gion:back' } };
  assert.deepEqual(compare(base, head, renames), []);
  assert.deepEqual(renameProblems(head, renames), []);
});

test('removing one of two visits at a place passes', () => {
  const head = day8((items) => items.filter((i) => i.id !== 's:wargo-gion:rent'));
  assert.deepEqual(compare(day8(), head, {}), []);
});

test('adding a visit passes', () => {
  const head = day8((items) => [...items, { ...items.find((i) => i.id === 's:wargo-gion:return'), id: 's:wargo-gion:again', at: '17:30' }]);
  assert.deepEqual(compare(day8(), head, {}), []);
});

test('keying a visit that had the default id fails once without a rename, passes with it', () => {
  // the base had one visit to Yorozuya; the head adds a second and keys both
  const base = day8();
  const head = day8((items) => {
    const lunch = items.find((i) => i.id === 's:yorozuya');
    return [...items.map((i) => (i === lunch ? { ...i, id: 's:yorozuya:lunch' } : i)), { ...lunch, id: 's:yorozuya:later', at: '18:00' }];
  });
  const errors = compare(base, head, {});
  assert.equal(errors.length, 1, errors.join('\n'));
  assert.match(errors[0], /s:yorozuya is gone while s:yorozuya:lunch, s:yorozuya:later is new/);
  assert.deepEqual(compare(base, head, { 8: { 's:yorozuya': 's:yorozuya:lunch' } }), []);
});

test('a move whose id changed at the same from>to fails, a move removed does not', () => {
  const id = 'm:sn-gion-tokuya>wargo-gion';
  assert.equal(compare(day8(), day8(withId(id, `${id}:back`)), {}).length, 1);
  assert.deepEqual(compare(day8(), day8((items) => items.filter((i) => i.id !== id)), {}), []);
});

test('a day only one side has is not compared', () => {
  assert.deepEqual(compare(day8(), [], {}), []);
  assert.deepEqual(compare([], day8(), {}), []);
});

test('a rename must point at an id of that day, from one it no longer has', () => {
  const head = day8();
  assert.equal(renameProblems(head, { 8: { 's:gone': 's:wargo-gion:rent' } }).length, 0);
  assert.match(renameProblems(head, { 8: { 's:gone': 's:nowhere' } }).join('\n'), /day 8 has no s:nowhere/);
  assert.match(renameProblems(head, { 8: { 's:wargo-gion:rent': 's:wargo-gion:return' } }).join('\n'), /s:wargo-gion:rent is still an id of day 8/);
  assert.match(renameProblems(head, { 99: { 's:a': 's:b' } }).join('\n'), /no day 99/);
});

test('a missing or repeated id is reported', () => {
  const out = problems(day8((items) => [...items.slice(0, 2), { ...items[2], id: undefined }, items[0]])).join('\n');
  assert.match(out, /day 8 item 2: no id/);
  assert.match(out, new RegExp(`day 8: ${items8()[0].id} is used twice`));
});

test('a day that comes back to a place keys every visit there', () => {
  // the original keyed, a bare second added: records on the bare id would move onto the new visit
  const lunch = items8().find((i) => i.id === 's:yorozuya');
  const keyedFirst = day8((items) => [...items.map((i) => (i.id === 's:yorozuya' ? { ...i, id: 's:yorozuya:lunch' } : i)), { ...lunch, at: '18:00' }]);
  assert.deepEqual(problems(keyedFirst), ['day 8: s:yorozuya is visited more than once — give every visit a key']);
  // the original bare, a keyed second added
  const keyedSecond = day8((items) => [...items, { ...lunch, id: 's:yorozuya:later', at: '18:00' }]);
  assert.deepEqual(problems(keyedSecond), ['day 8: s:yorozuya is visited more than once — give every visit a key']);
  // the same for a from>to
  const back = items8().find((i) => i.id === 'm:sn-gion-tokuya>wargo-gion');
  assert.equal(problems(day8((items) => [...items, { ...back, id: `${back.id}:again` }])).length, 1);
});

test('a visit removed and the other losing its key: map only the one that is the same visit', () => {
  const head = day8((items) => items.filter((i) => i.id !== 's:wargo-gion:rent').map((i) => (i.id === 's:wargo-gion:return' ? { ...i, id: 's:wargo-gion' } : i)));
  const errors = compare(day8(), head, {});
  assert.equal(errors.length, 2, errors.join('\n'));
  assert.ok(errors.every((e) => e.includes('only an old id whose visit is the same one (a visit removed needs no entry)')), errors.join('\n'));
  assert.deepEqual(compare(day8(), head, { 8: { 's:wargo-gion:return': 's:wargo-gion' } }), []);
});

test('a stop without a place: a new key in place of the old looks renamed', () => {
  const day = (key) => fromSource([{ n: 8, items: [stop('9:00', undefined, 'Nghỉ', undefined, undefined, undefined, { key })] }]);
  assert.equal(compare(day('rest'), day('nap'), {}).length, 1);
  assert.deepEqual(compare(day('rest'), day('nap'), { 8: { 's::rest': 's::nap' } }), []);
});

test('a rename the base shipped stays', () => {
  const shipped = { 8: { 's:wargo-gion': 's:wargo-gion:return' } };
  assert.match(keptRenames(shipped, {}).join('\n'), /ID_RENAMES\['8'\]: s:wargo-gion was shipped and is gone/);
  assert.deepEqual(keptRenames(shipped, { 8: { 's:wargo-gion': 's:wargo-gion:back' } }), []);
});

test('the source and the committed export have the same days, and agree on every id', () => {
  const committed = fromExport(JSON.parse(readFileSync(new URL(`../${TRIP}`, import.meta.url), 'utf8')));
  const source = fromSource([...DAYS, ...ALT_DAYS]);
  assert.deepEqual(source.map((d) => d.key), committed.map((d) => d.key));
  assert.ok(source.some((d) => d.key === 'kawaguchiko'));
  assert.deepEqual(compare(committed, source), []);
});

/** runs main, returns its exit code and what it printed, and leaves process.exitCode as it found it */
const run = (refs, days, load) => {
  const saved = process.exitCode;
  const lines = [];
  process.exitCode = undefined;
  try {
    main(refs, days, (l) => lines.push(l), load);
    return { code: process.exitCode ?? 0, out: lines.join('\n') };
  } finally {
    process.exitCode = saved;
  }
};
const renamedReturn = () => {
  const days = structuredClone([...DAYS, ...ALT_DAYS]);
  const it = days.find((d) => dayKey(d) === '8').items.find((i) => i.id === 's:wargo-gion:return');
  it.id = 's:wargo-gion:back';
  return days;
};

test('the command fails on a base that is no commit', () => {
  const r = run(['no-such-ref'], undefined);
  assert.equal(r.code, 1);
  assert.match(r.out, /base no-such-ref is not a commit/);
});

test('the command compares with a commit whose trip.json has ids', () => {
  // HEAD's export has ids (since the commit that wrote them)
  const same = run(['HEAD']);
  assert.equal(same.code, 0, same.out);
  assert.match(same.out, /none changed since HEAD$/);
  const renamed = run(['HEAD'], renamedReturn());
  assert.equal(renamed.code, 1, renamed.out);
  assert.match(renamed.out, /day 8: s:wargo-gion:return is gone while s:wargo-gion:back is new/);
});

test('the command takes the first base with ids, and checks the renames that base shipped', () => {
  const committed = fromExport(JSON.parse(readFileSync(new URL(`../${TRIP}`, import.meta.url), 'utf8')));
  const load = (renames) => (ref) => (ref === 'bare' ? { skip: 'bare has no ids' } : { days: committed, renames });
  const r = run(['bare', 'withIds'], renamedReturn(), load({}));
  assert.equal(r.code, 1, r.out);
  assert.match(r.out, /s:wargo-gion:return is gone/);
  assert.equal(run(['bare', 'withIds'], undefined, load({})).out.endsWith('none changed since withIds'), true);
  assert.match(run(['bare'], renamedReturn(), load({})).out, /comparison skipped: bare has no ids$/);
  const dropped = run(['withIds'], undefined, load({ 8: { 's:old': 's:wargo-gion:rent' } }));
  assert.equal(dropped.code, 1, dropped.out);
  assert.match(dropped.out, /s:old was shipped and is gone/);
});

test('ids do not follow the time, the waypoints or the minutes', () => {
  assert.equal(stop('11:20', 'nezu-shrine', 'Nezu').id, stop('11:05', 'nezu-shrine', 'Nezu Jinja', 'text', 100, true).id);
  assert.equal(stop('11:05', 'nezu-shrine', 'Nezu').id, 's:nezu-shrine');
  const a = walk('nezu-shrine', 'st-ueno-hirokoji', { via: [[35.7148, 139.7663]], min: '40' });
  const b = walk('nezu-shrine', 'st-ueno-hirokoji', { via: ['shinobazu', [35.71, 139.77]], min: '45', note: 'n' }, '11:30');
  assert.equal(a.id, 'm:nezu-shrine>st-ueno-hirokoji');
  assert.equal(b.id, a.id);
  assert.notEqual(b.leg.id, a.leg.id); // the geometry key still follows the waypoints
});

test('a key names the visit and stays out of the leg and its geometry key', () => {
  assert.equal(stop('9:30', 'wargo-gion', 'Thuê', undefined, undefined, undefined, { key: 'rent' }).id, 's:wargo-gion:rent');
  const plain = leg('keihan', 'st-sanjo', 'st-kiyomizu-gojo', { via: ['x'], min: '4' });
  const keyed = leg('keihan', 'st-sanjo', 'st-kiyomizu-gojo', { via: ['x'], min: '4', key: 'back' });
  assert.equal(keyed.id, 'm:st-sanjo>st-kiyomizu-gojo:back');
  assert.equal(keyed.leg.id, plain.leg.id);
  assert.deepEqual(keyed.leg, plain.leg);
  assert.ok(!('key' in keyed.leg));
});

test('a stop without a place needs a key, and keys are lowercase slugs', () => {
  assert.equal(stop('9:00', undefined, 'Nghỉ', undefined, undefined, undefined, { key: 'rest' }).id, 's::rest');
  assert.throws(() => stop('9:00', undefined, 'Nghỉ'), /a stop without a place needs a key/);
  for (const key of ['', 'Rent', 'a b', 'a:b', 'a>b', 'á']) {
    assert.throws(() => stop('9:00', 'wargo-gion', 'T', undefined, undefined, undefined, { key }), /key/, key);
    assert.throws(() => walk('a', 'b', { key }), /key/, key);
  }
});
