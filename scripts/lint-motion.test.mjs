// node --test 'scripts/*.test.mjs'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { motionHits } from './lint-motion.mjs';

/** code that writes a curve at the call site, or animates without a token */
const flagged = [
  'withAnimation(.snappy) { x = 1 }',
  'withAnimation(.snappy(duration: 0.25)) { x = 1 }',
  '.animation(.smooth, value: current)',
  '.animation(.smooth(duration: 0.3), value: current)',
  '.animation(Animation.smooth(duration: 0.3), value: current)',
  'withAnimation(.smooth(duration: 0.7).delay(0.1)) { risen = true }',
  'withAnimation(.easeOut(duration: 0.2)) { image = loaded }',
  '.animation(current ? .easeInOut(duration: 10) : .smooth(duration: 0.5), value: current)',
  'withAnimation(.bouncy) { go() }',
  '.animation(.spring(response: 0.3, dampingFraction: 0.72), value: p)',
  'withAnimation(.spring(duration: 0.38, bounce: 0.1)) { a = 1 }',
  'withAnimation(.interpolatingSpring(duration: 0.38, bounce: 0.1, initialVelocity: v)) { a = 1 }',
  'private static var snap: Animation { .spring(response: 0.38, dampingFraction: 0.86) }',
  '$open.animation(.snappy)',
  '.animation(.linear(duration: 1), value: t)',
  '.animation(.easeIn(duration: 0.2), value: t)',
  '.animation(.timingCurve(0.2, 0, 0, 1, duration: 0.3), value: t)',
  'withAnimation { proxy.scrollTo(last, anchor: .bottom) }',
  'withAnimation{ proxy.scrollTo(last) }',
  'LinearKeyframe(1, duration: 0.01)',
  'CubicKeyframe(1.32, duration: 0.7)',
  'SpringKeyframe(1, duration: 0.3)',
  // a token used bare: Reduce Motion is not applied (R-490)
  'withAnimation(Motion.pick) { a = 1 }',
  '.animation(Motion.settle, value: x)',
  'withAnimation(Motion.settle(velocity: v)) { a = 1 }',
  'withAnimation(Motion.press) { a = 1 }',
  '.animation(Motion.travel.delay(0.1), value: x)',
];
/** code that is not a curve, goes through `reduced`, or says why it is one */
const allowed = [
  'withAnimation(Motion.reduced(Motion.pick, reduceMotion)) { a = 1 }',
  'withAnimation(Motion.reduced(Motion.settle(velocity: v), reduceMotion)) { a = 1 }',
  'withAnimation(Motion.reduced(Motion.travel, reduceMotion)?.delay(0.1)) { a = 1 }',
  '.animation(Motion.reduced( Motion.settle, reduceMotion), value: x)',
  'withAnimation(Motion.arrive) { image = loaded }',
  '.animation(Motion.reduced(Motion.arrive, reduceMotion), value: x)',
  'withAnimation(nil) { a = 1 }',
  'withAnimation(reduceMotion ? nil : Motion.reduced(Motion.travel, reduceMotion)) { a = 1 }',
  '.symbolEffect(.bounce, value: isOn)',
  '.symbolEffect(.variableColor.iterative, isActive: active)',
  '.contentTransition(.symbolEffect(.replace))',
  'scrollEdgeEffectStyle(.soft, for: .all)',
  '.transition(.opacity)',
  '.transition(.move(edge: .bottom).combined(with: .opacity))',
  'LinearGradient(colors: [a, b], startPoint: .top, endPoint: .bottom)',
  'Gradient.Stop(color: .clear, location: 0)',
  '.smoothed(x)',
  'let spring = 3',
  'springs.count',
  'self.settle(velocity: v)',
  '// withAnimation(.snappy) { x = 1 }',
  '/// the old .smooth(duration: 0.3) and Motion.pick',
  '/* .spring(response: 1) */ let a = 1',
  'let s = "tap .snappy or .smooth(0.3)"',
  'let s = "\\(count) .bouncy"',
  'withAnimation(.snappy) { x = 1 } // motion: one-off the keyboard\'s own curve',
  '.animation(.spring(duration: d, bounce: 0), value: x) // motion: one-off the system keyboard\'s curve',
];

test('every curve written at a call site, every bare token and every unmarked keyframe is a hit', () => {
  for (const line of flagged) {
    const hits = motionHits(line);
    assert.equal(hits.length, 1, `should be flagged once: ${line}`);
    assert.equal(hits[0].line, 1);
  }
});

test('tokens through reduced, other kinds of symbol, comments and strings are not', () => {
  for (const line of allowed) assert.deepEqual(motionHits(line), [], `should pass: ${line}`);
});

test('a multi-line call is read as a whole: reduced( on one line, the token on the next', () => {
  assert.deepEqual(motionHits('withAnimation(Motion.reduced(\n    Motion.pick,\n    reduceMotion)) { a = 1 }'), []);
  assert.equal(motionHits('x\nwithAnimation(\n    Motion.pick\n) { a = 1 }')[0].line, 3);
});

test('hits are numbered from 1 and carry the trimmed line', () => {
  const hits = motionHits('let a = 1\n    withAnimation(.snappy) { a = 2 }\n');
  assert.deepEqual(hits.map((h) => [h.line, h.text]), [[2, 'withAnimation(.snappy) { a = 2 }']]);
});

test('the one-off marker needs a reason, on the line or on a comment-only line directly above', () => {
  assert.deepEqual(motionHits('// motion: one-off the cover drifts for 10 s\n.animation(.easeInOut(duration: 10), value: c)'), []);
  assert.deepEqual(motionHits('.animation(.easeInOut(duration: 10), value: c) // motion: one-off slow drift'), []);
  assert.equal(motionHits('.animation(.easeInOut(duration: 10), value: c) // motion: one-off').length, 1);
  assert.equal(motionHits('.animation(.easeInOut(duration: 10), value: c) // motion: one-off   ').length, 1);
  assert.equal(motionHits('// motion: one-off\n.animation(.easeInOut(duration: 10), value: c)').length, 1);
  // two lines above is too far; a code line above does not count
  assert.equal(motionHits('// motion: one-off slow\nlet a = 1\n.animation(.smooth, value: c)').length, 1);
  assert.equal(motionHits('let a = 1 // motion: one-off slow\n.animation(.smooth, value: c)').length, 1);
});

function lintTree(files) {
  const dir = mkdtempSync(join(tmpdir(), 'lint-motion-'));
  try {
    for (const [name, body] of Object.entries(files)) {
      mkdirSync(join(dir, name, '..'), { recursive: true });
      writeFileSync(join(dir, name), body);
    }
    return spawnSync('node', ['scripts/lint-motion.mjs', dir], { encoding: 'utf8' });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('the command fails on a hit, naming file and line, and skips Design/Motion.swift', () => {
  const r = lintTree({
    'Design/Motion.swift': 'static let pick: Animation = .snappy(duration: 0.25)\n',
    'Features/A.swift': 'let a = 1\nwithAnimation(.snappy) { a = 2 }\n',
    'Features/B.swift': 'withAnimation(Motion.reduced(Motion.pick, r)) { }\n',
    'Features/notes.txt': 'withAnimation(.snappy)\n',
  });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /Features\/A\.swift:2/);
  assert.doesNotMatch(r.stderr, /Motion\.swift|B\.swift|notes/);
});

test('the command passes on a clean tree', () => {
  const r = lintTree({ 'Features/B.swift': 'withAnimation(Motion.reduced(Motion.pick, r)) { }\n' });
  assert.equal(r.status, 0, r.stderr);
});
