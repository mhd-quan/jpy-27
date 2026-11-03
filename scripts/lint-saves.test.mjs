// node --test 'scripts/*.test.mjs'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { bestEffort, silentSaves } from './lint-saves.mjs';

/** lines that hide a failed save */
const silent = [
  'try? context.save()',
  '        try? model.context.save()',
  '        guard (try? to.save()) != nil else { return }',
  'try?context.save()',
  'try? (context.save())',
  'try? context?.save()',
  'try? ctx!.save()',
  '        if changed { try? context.save() }',
  // the task's own saves: `commit()`, and the ledger's writes, which commit inside
  'try? context.commit()',
  'try? Ledger.merge(x, into: c)',
  '                merged = (try? Ledger.merge(clean, into: context))?.merged ?? clean',
];
/** lines that do not, or say why they may */
const allowed = [
  'try context.save()',
  'try context.commit()',
  '        savePace()',
  'if let data = try? JSONEncoder().encode(pace) { Shared.defaults.set(data, forKey: "paceModel") }',
  '            try? to.save() // save: best-effort, the rehearsal runs in memory without it',
  'if fm.fileExists(atPath: at.path) { try? fm.moveItem(at: at, to: other) }',
  'do { try context.save() } catch { rollback() }',
];

/** a folder of Swift files, removed after `body` */
function withFiles(files, body) {
  const dir = mkdtempSync(join(tmpdir(), 'lint-saves-'));
  try {
    for (const [name, text] of Object.entries(files)) {
      mkdirSync(join(dir, name, '..'), { recursive: true });
      writeFileSync(join(dir, name), text);
    }
    return body(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const lint = (...args) => spawnSync('node', ['scripts/lint-saves.mjs', ...args], { encoding: 'utf8' });

for (const line of silent) {
  test(`fails on: ${line.trim()}`, () => {
    assert.deepEqual(silentSaves(line), [{ line: 1, text: line.trim() }]);
  });
}
for (const line of allowed) {
  test(`passes: ${line.trim()}`, () => {
    assert.deepEqual(silentSaves(line), []);
  });
}

test('names the line, counted from 1', () => {
  const text = ['import SwiftData', '', 'func f(_ c: ModelContext) {', '    try? c.save()', '}'].join('\n');
  assert.deepEqual(silentSaves(text), [{ line: 4, text: 'try? c.save()' }]);
});

test('a silent save in a Swift file, in a folder below, fails with its file and line', () => {
  withFiles({ 'Data/Records.swift': 'struct A {}\n        try? context.save()\n', 'notes.md': 'try? context.save()\n' }, (dir) => {
    const r = lint(dir);
    assert.equal(r.status, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /Data\/Records\.swift:2: try\? context\.save\(\)/);
    assert.doesNotMatch(r.stdout, /notes\.md/);
  });
});

test('saves that throw, and marked best-effort copies, pass', () => {
  withFiles({ 'App.swift': allowed.join('\n') + '\n' }, (dir) => {
    const r = lint(dir);
    assert.equal(r.status, 0, r.stdout + r.stderr);
  });
});

test('the app has no silent save', () => {
  const r = lint();
  assert.equal(r.status, 0, r.stdout + r.stderr);
});

// the brief allows two: a third mark would be a silent save let through by a comment
test('the app marks exactly its two best-effort copies', () => {
  assert.deepEqual(bestEffort(['ios/JP27']), [
    {
      file: join('ios/JP27', 'Data/Records.swift'),
      text: 'guard (try? to.save()) != nil else { return } // save: best-effort, the side store stays and is folded in at the next launch',
    },
    {
      file: join('ios/JP27', 'Data/Records.swift'),
      text: 'try? to.save() // save: best-effort, a rehearsal without the copy starts from empty records, never the real ones',
    },
  ]);
});
