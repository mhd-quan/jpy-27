// node scripts/lint-motion.mjs [folder …]   (default: ios/JP27)
//
// Every animation of the app is named by what it is for (`Motion`, ios/JP27/Design/Motion.swift: press,
// pick, arrive, settle, travel) and goes through `Motion.reduced`, which is where Reduce Motion lives
// (Task 5.8). A curve written at the call site (`.snappy`, `.smooth(duration: 0.3)`, a spring), a
// `withAnimation { }` with no animation named, a keyframe, or a spring/travel token used bare is a second
// vocabulary that Reduce Motion cannot see. This fails on any line of Swift with one, unless the line (or the
// comment-only line directly above it) says why it may: `// motion: one-off <reason>`, the reason required.
//
// Also flagged: a modifier chained on a token (`Motion.travel.delay(…)`, even inside `reduced(`; chain after it:
// `Motion.reduced(Motion.travel, r)?.delay(…)`), `.linear` whatever follows it, `.blurReplace` (an offscreen filter),
// and the spellings of the default animation: `withAnimation()`, `withAnimation({`, `withAnimation(completionCriteria:`,
// `withAnimation(.default`, `.animation(.default`, `.animation()`.
//
// Not flagged: comments and string contents (a marker inside a string is not a marker); `.symbolEffect` /
// `.contentTransition` arguments (`.bounce`, `.variableColor`); `.soft` scroll edge effects; gradients, and the
// Charts `.linear` of `interpolationMethod(` and `type:`; `Motion.arrive`, which may be bare (a short ease that
// Reduce Motion keeps); a `.default` that is not the argument of `withAnimation(` or `.animation(`. Not seen:
// `.phaseAnimator(`, whose animation lives in a trailing closure that a line-local scan cannot read (the tree has
// none). UIKit's `UIView.transition` is outside the lint too.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { blanked } from './lint-saves.mjs';

/** a curve named at the call site */
const CURVE = /\.(?:snappy|smooth|easeOut|easeInOut|easeIn|bouncy|spring|interpolatingSpring|timingCurve)\b|(?<!interpolationMethod\(\s*)(?<!type:\s*)\.linear\b|\.blurReplace\b/g;
/** the default curve, named nowhere: `withAnimation { }`, `withAnimation()`, `withAnimation({`, `withAnimation(completionCriteria:`,
 *  `withAnimation(.default`, `.animation(.default`, `.animation()` (both `.default` only ever mean an Animation here) */
const BARE_WITH = /\bwithAnimation\s*(?:\{|\(\s*(?:\)|\{|\.default\b|completionCriteria:))|\.animation\s*\(\s*(?:\)|\.default\b)/g;
/** a keyframe: its own timing */
const KEYFRAME = /\b(?:Linear|Cubic|Spring|Move)Keyframe\s*\(/g;
/** a token that Reduce Motion should change, not the first argument of `Motion.reduced(` */
const BARE_TOKEN = /(?<!Motion\.reduced\(\s*)\bMotion\.(?:press|pick|settle|travel)\b/g;
/** a modifier chained on the token itself, even inside `reduced(`: it no longer matches by `==`, so a jump would become an ease */
const CHAINED_TOKEN = /\bMotion\.(?:press|pick|settle|travel)\b(?!\s*\()\s*\./g;
/** what a line says to be let through: the marker and a reason */
const ONE_OFF = /\/\/\s*motion:\s*one-off\s+\S/;
/** the file that defines the curves */
export const DEFINITION = 'Design/Motion.swift';

/** Whether `line` carries the marker as a comment: not inside a string literal (an odd number of quotes before it). */
function marked(line) {
  const m = ONE_OFF.exec(line);
  return m !== null && (line.slice(0, m.index).replaceAll('\\"', '').match(/"/g) ?? []).length % 2 === 0;
}

/** The lines of `text` with a curve, a bare animation or a bare token, numbered from 1, once each. */
export function motionHits(text) {
  const raw = text.split('\n');
  const code = blanked(text);
  const lines = new Set();
  for (const re of [CURVE, BARE_WITH, KEYFRAME, BARE_TOKEN, CHAINED_TOKEN]) {
    for (const m of code.matchAll(re)) lines.add(code.slice(0, m.index).split('\n').length);
  }
  return [...lines].sort((a, b) => a - b).flatMap((n) => {
    const above = raw[n - 2]?.trim() ?? '';
    const said = marked(raw[n - 1]) || (above.startsWith('//') && ONE_OFF.test(above));
    return said ? [] : [{ line: n, text: raw[n - 1].trim() }];
  });
}

/** Every `.swift` file under `folder`, but the definition of the tokens. */
function swiftFiles(folder) {
  return readdirSync(folder, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith('.swift'))
    .map((e) => join(e.parentPath ?? e.path, e.name))
    .filter((p) => !p.replaceAll('\\', '/').endsWith(`/${DEFINITION}`))
    .sort();
}

/** `[{file, line, text}]` over `folders`. */
export function lintMotion(folders) {
  return folders.flatMap((f) => swiftFiles(f).flatMap((file) =>
    motionHits(readFileSync(file, 'utf8')).map((h) => ({ file, ...h }))));
}

export function main(folders = ['ios/JP27']) {
  const hits = lintMotion(folders);
  for (const h of hits) console.error(`${h.file}:${h.line}: ${h.text}`);
  if (hits.length) {
    console.error(`\n${hits.length} animation(s) outside Motion. Use a token through Motion.reduced(token, reduceMotion), or add \`// motion: one-off <reason>\`.`);
    process.exit(1);
  }
  console.log('lint-motion: every animation is a Motion token');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const folders = process.argv.slice(2);
  main(folders.length ? folders : undefined);
}
