// node --test 'scripts/*.test.mjs'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { bestEffort, silentReads, silentSaves } from './lint-saves.mjs';

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

// The reads a money write is decided on (R-154): a failed one read as "nothing there" deletes nothing and
// says done, digests an empty ledger and stamps it synced, or inserts a second row with the same id.

/** money code, numbered from 1 */
const money = (...lines) => lines.join('\n');

test('a read that hides its failure inside the ledger fails', () => {
  const text = money(
    '@MainActor enum Ledger {',
    '    static func state(_ context: ModelContext) -> LedgerState {',
    '        let rows = (try? context.fetch(FetchDescriptor<Expense>())) ?? []',
    '        return LedgerState(records: rows)',
    '    }',
    '}',
    'extension Ledger {',
    '    static func one(_ id: UUID, in context: ModelContext) -> Expense? {',
    '        try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first',
    '    }',
    '}',
  );
  assert.deepEqual(silentReads(text), [
    { line: 3, text: 'let rows = (try? context.fetch(FetchDescriptor<Expense>())) ?? []' },
    { line: 9, text: 'try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first' },
  ]);
});

test('in a function that calls the ledger, a read or a batch delete that hides its failure fails', () => {
  const text = money(
    'func unbuy(_ itemID: String) -> Bool {',
    '    try? context.delete(model: Purchase.self, where: #Predicate { $0.itemID == itemID })',
    '    for e in (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.itemID == linked }))) ?? [] {',
    '        Ledger.delete(e, in: context)',
    '    }',
    '    let n = (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0',
    '    return persist("Bỏ đã mua")',
    '}',
  );
  assert.deepEqual(silentReads(text).map((r) => r.line), [2, 3, 6]);
});

test('reads that throw, and the same silent read where no money is decided, pass', () => {
  const text = money(
    'enum Ledger {',
    '    static func state(_ context: ModelContext) throws(SaveFailure) -> LedgerState {',
    '        let rows = try fetch(FetchDescriptor<Expense>(), in: context)',
    '        return LedgerState(records: rows)',
    '    }',
    '}',
    '/// copies, folded in like `Ledger.merge` would: a comment is not a call',
    'private static func copyRecords(from: ModelContext, to: ModelContext) {',
    '    for e in (try? from.fetch(FetchDescriptor<Expense>())) ?? [] { to.insert(e.copy()) }',
    '}',
    'func csv() -> String {',
    '    let label = "Ledger.state {"',
    '    let rows = (try? context.fetch(FetchDescriptor<Expense>())) ?? []',
    '    return "\\(rows.map { "\\($0.yen) }" })"',
    '}',
  );
  assert.deepEqual(silentReads(text), []);
});

test('braces in strings, interpolations and comments do not end the ledger early', () => {
  const text = money(
    'enum Ledger {',
    '    static let a = "}"',
    '    static let b = "\\(x.map { "}" })" // }',
    '    /* } */',
    '    static func f(_ c: ModelContext) { _ = try? c.fetch(D()) }',
    '}',
    'func g(_ c: ModelContext) { _ = try? c.fetch(D()) }',
  );
  assert.deepEqual(silentReads(text).map((r) => r.line), [5]);
});

test('a silent read in the ledger fails the command, with its file and line', () => {
  withFiles({ 'Data/Records.swift': 'enum Ledger {\n    static func f(_ c: ModelContext) { _ = try? c.fetch(D()) }\n}\n' }, (dir) => {
    const r = lint(dir);
    assert.equal(r.status, 1, r.stdout + r.stderr);
    assert.match(r.stdout, /Data\/Records\.swift:2: static func f\(_ c: ModelContext\) \{ _ = try\? c\.fetch\(D\(\)\) \}/);
  });
});
