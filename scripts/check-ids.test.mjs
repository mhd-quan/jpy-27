// node --test 'scripts/*.test.mjs'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { compare, fromSource, problems, renameProblems } from './check-ids.mjs';
import { DAYS, ALT_DAYS, leg, stop, walk } from '../src/data/days.ts';

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
    assert.equal(new Set(ids).size, ids.length, `day ${d.n}`);
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
