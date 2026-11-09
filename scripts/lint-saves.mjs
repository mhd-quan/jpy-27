// node scripts/lint-saves.mjs [folder …]   (default: ios/JP27)
//
// A save on the user's path says when it fails: `ModelContext.commit()` and `AppModel.persist` take
// the write back and tell the user (Task 1.4). A `try?` on a save hides the failure: the editor
// closes, the haptic says done, the sync says synced, and nothing was written. This fails on any
// line of Swift with one (on `save()`, on `commit()`, or on a `Ledger` write, which commits inside),
// unless the line says why it may (`// save: best-effort`): a copy with another way back, of which
// the app has two (Records.swift: folding the side store in, copying the records for a rehearsal).
//
// The reads money is decided on fail the same way (R-154): a `try?` on a fetch (or on a batch
// `delete(model:)`, which reads first) inside `Ledger`, or in a function that calls into it, turns a
// read that failed into "nothing there": a delete that deletes nothing and says done, an empty ledger
// digested and stamped synced, a merge that inserts a second row with the same id.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

/** `try?` on a save or a commit, the receiver perhaps optional (`context?.`) or forced (`ctx!.`),
 *  or on one of the ledger's writes */
export const SILENT_SAVE = /try\?\s*\(?\s*(?:[\w.?!]+\.(?:save|commit)\(\)|Ledger\.(?:apply|merge|keepApart|restore)\()/;
/** `try?` on a read of the records (`fetch`, `fetchCount`, …, the receiver perhaps optional or forced, or
 *  none), or on a batch `delete(model:)`, which reads first */
export const SILENT_READ = /try\?\s*\(?\s*(?:[\w.?!]+\.)?(?:fetch\w*\s*\(|delete\(\s*model:)/;
/** what a line says to be let through */
export const MARK = '// save: best-effort';

/** The lines of `text` with a silent save, numbered from 1. */
export function silentSaves(text) {
  return text.split('\n').flatMap((line, i) =>
    SILENT_SAVE.test(line) && !line.includes(MARK) ? [{ line: i + 1, text: line.trim() }] : []);
}

/** The lines of `text` with a silent read where money is decided (`moneyLines`), numbered from 1. */
export function silentReads(text) {
  const money = moneyLines(text);
  return text.split('\n').flatMap((line, i) =>
    money.has(i + 1) && SILENT_READ.test(line) && !line.includes(MARK) ? [{ line: i + 1, text: line.trim() }] : []);
}

/**
 * The lines (from 1) where money is decided: the bodies of `enum Ledger` and its extensions, and of every
 * function or initializer that calls into it (`Ledger.` in its code, not in a comment or a string).
 */
export function moneyLines(text) {
  const code = blanked(text);
  const lines = new Set();
  for (const b of blocks(code)) {
    const ledger = /\b(?:enum|extension)\s+Ledger\b/.test(b.header);
    const caller = /\b(?:func\s|init\s*[(<?])/.test(b.header) && /\bLedger\./.test(b.body);
    if (ledger || caller) for (let n = b.from; n <= b.to; n++) lines.add(n);
  }
  return lines;
}

/** Every `{ … }` of `code`: the code before it since the brace before (its declaration), its lines, its body. */
function blocks(code) {
  const out = [];
  const open = [];
  let line = 1;
  let since = 0;
  for (let i = 0; i < code.length; i++) {
    const c = code[i];
    if (c === '\n') line += 1;
    else if (c === '{') {
      open.push({ header: code.slice(since, i), from: line, at: i + 1 });
      since = i + 1;
    } else if (c === '}') {
      const b = open.pop();
      if (b) out.push({ header: b.header, from: b.from, to: line, body: code.slice(b.at, i) });
      since = i + 1;
    }
  }
  return out;
}

/**
 * `text` with its comments and what its string literals hold blanked out (newlines kept, so lines keep their
 * numbers), the code inside an interpolation kept: braces and calls are then those of the code.
 */
export function blanked(text) {
  let out = '';
  const blank = (s) => s.replace(/[^\n]/g, ' ');
  // where the scan is: code (counting the parentheses an interpolation opened), or a string and its end
  const stack = [{ code: true, parens: 0 }];
  let i = 0;
  while (i < text.length) {
    const top = stack[stack.length - 1];
    const rest = text.slice(i, i + 3);
    if (top.code) {
      if (rest.startsWith('//') || rest.startsWith('/*')) {
        const line = rest.startsWith('//');
        const end = line ? text.indexOf('\n', i) : text.indexOf('*/', i + 2);
        const to = end < 0 ? text.length : line ? end : end + 2;
        out += blank(text.slice(i, to));
        i = to;
      } else if (rest === '"""' || rest[0] === '"') {
        const close = rest === '"""' ? '"""' : '"';
        stack.push({ code: false, close });
        out += blank(close);
        i += close.length;
      } else {
        if (rest[0] === '(') top.parens += 1;
        if (rest[0] === ')' && top.parens === 0 && stack.length > 1) {
          // the end of an interpolation: back in its string
          stack.pop();
          out += ' ';
          i += 1;
          continue;
        }
        if (rest[0] === ')') top.parens -= 1;
        out += rest[0];
        i += 1;
      }
    } else if (rest.startsWith('\\(')) {
      stack.push({ code: true, parens: 0 });
      out += '  ';
      i += 2;
    } else if (rest[0] === '\\') {
      out += blank(text.slice(i, i + 2));
      i += 2;
    } else if (text.startsWith(top.close, i)) {
      stack.pop();
      out += blank(top.close);
      i += top.close.length;
    } else {
      out += blank(rest[0]);
      i += 1;
    }
  }
  return out;
}

/** The Swift files under `folders`, as `{ file, text }`, in a fixed order. */
function swiftFiles(folders) {
  return folders.flatMap((folder) =>
    readdirSync(folder, { recursive: true })
      .filter((name) => name.endsWith('.swift'))
      .sort()
      .map((name) => ({ file: join(folder, name), text: readFileSync(join(folder, name), 'utf8') })));
}

/** Every silent save, and every silent read where money is decided, in the Swift files under `folders`. */
export function lintSaves(folders) {
  return swiftFiles(folders).flatMap(({ file, text }) =>
    [...silentSaves(text), ...silentReads(text)].sort((a, b) => a.line - b.line).map((s) => ({ file, ...s })));
}

/** Every line under `folders` that says it may save silently, trimmed. */
export function bestEffort(folders) {
  return swiftFiles(folders).flatMap(({ file, text }) =>
    text.split('\n').filter((line) => line.includes(MARK)).map((line) => ({ file, text: line.trim() })));
}

export function main(folders = ['ios/JP27']) {
  const found = lintSaves(folders);
  for (const s of found) console.log(`${s.file}:${s.line}: ${s.text}`);
  console.log(found.length
    ? `${found.length} save(s) or money read(s) whose failure no one would see: use \`try context.commit()\` or \`model.persist(…)\`, read with \`try\` and report the failure as a failed write, or mark a best-effort copy with "${MARK}" and say why`
    : `no silent save, and no silent money read, in ${folders.join(', ')}`);
  process.exitCode = found.length ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const folders = process.argv.slice(2);
  main(folders.length ? folders : undefined);
}
