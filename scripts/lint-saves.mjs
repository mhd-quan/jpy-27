// node scripts/lint-saves.mjs [folder …]   (default: ios/JP27)
//
// A save on the user's path says when it fails: `ModelContext.commit()` and `AppModel.persist` take
// the write back and tell the user (Task 1.4). A `try?` on a save hides the failure: the editor
// closes, the haptic says done, the sync says synced, and nothing was written. This fails on any
// line of Swift with one (on `save()`, on `commit()`, or on a `Ledger` write, which commits inside),
// unless the line says why it may (`// save: best-effort`): a copy with another way back, of which
// the app has two (Records.swift: folding the side store in, copying the records for a rehearsal).
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

/** `try?` on a save or a commit, the receiver perhaps optional (`context?.`) or forced (`ctx!.`),
 *  or on one of the ledger's writes */
export const SILENT_SAVE = /try\?\s*\(?\s*(?:[\w.?!]+\.(?:save|commit)\(\)|Ledger\.(?:apply|merge|keepApart|restore)\()/;
/** what a line says to be let through */
export const MARK = '// save: best-effort';

/** The lines of `text` with a silent save, numbered from 1. */
export function silentSaves(text) {
  return text.split('\n').flatMap((line, i) =>
    SILENT_SAVE.test(line) && !line.includes(MARK) ? [{ line: i + 1, text: line.trim() }] : []);
}

/** The Swift files under `folders`, as `{ file, text }`, in a fixed order. */
function swiftFiles(folders) {
  return folders.flatMap((folder) =>
    readdirSync(folder, { recursive: true })
      .filter((name) => name.endsWith('.swift'))
      .sort()
      .map((name) => ({ file: join(folder, name), text: readFileSync(join(folder, name), 'utf8') })));
}

/** Every silent save in the Swift files under `folders`. */
export function lintSaves(folders) {
  return swiftFiles(folders).flatMap(({ file, text }) => silentSaves(text).map((s) => ({ file, ...s })));
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
    ? `${found.length} save(s) whose failure no one would see: use \`try context.commit()\` or \`model.persist(…)\`, or mark a best-effort copy with "${MARK}" and say why`
    : `no silent save in ${folders.join(', ')}`);
  process.exitCode = found.length ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const folders = process.argv.slice(2);
  main(folders.length ? folders : undefined);
}
