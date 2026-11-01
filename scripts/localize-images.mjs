// Self-host the Wikimedia Commons photos used by the site.
//
// Commons images are freely licensed (CC BY / BY-SA / public domain) and are shown
// with author, license and a link to the file page. Hot-linking them is unreliable
// (Wikimedia rate-limits), so this script downloads each file once, resizes it to
// 800 px WebP and writes public/img/commons/<hash>.webp plus research/commons-map.json.
// Restaurant photos (Tabelog) and hotel photos stay linked to their source.
//
// Needs ImageMagick (`convert`). Usage: node scripts/localize-images.mjs

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const UA = 'nb2027-trip-site/1.0 (personal itinerary site; https://jpy27.delphyra.tech/)';
const cacheDir = join(root, '.cache/commons');
const outDir = join(root, 'public/img/commons');
mkdirSync(cacheDir, { recursive: true });
mkdirSync(outDir, { recursive: true });

// every Commons photo referenced anywhere in the research files (places, spots, walks, highlights)
const urls = new Set();
const collect = (v) => {
  if (Array.isArray(v)) v.forEach(collect);
  else if (v && typeof v === 'object') {
    if (typeof v.url === 'string' && v.url.includes('upload.wikimedia.org')) urls.add(v.url);
    Object.values(v).forEach(collect);
  }
};
for (const f of readdirSync(join(root, 'research')).filter((x) => x.endsWith('.json') && x !== 'commons-map.json')) {
  collect(JSON.parse(readFileSync(join(root, 'research', f), 'utf8')));
}

const mapFile = join(root, 'research/commons-map.json');
const map = existsSync(mapFile) ? JSON.parse(readFileSync(mapFile, 'utf8')) : {};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hash = (s) => createHash('sha1').update(s).digest('hex').slice(0, 12);

let done = 0;
let failed = 0;
for (const url of urls) {
  const id = hash(url);
  const out = join(outDir, `${id}.webp`);
  const rel = `img/commons/${id}.webp`;
  if (existsSync(out)) {
    map[url] = rel;
    continue;
  }
  const raw = join(cacheDir, `${id}.img`);
  if (!existsSync(raw)) {
    let ok = false;
    for (let attempt = 0; attempt < 5 && !ok; attempt++) {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (res.ok) {
        writeFileSync(raw, Buffer.from(await res.arrayBuffer()));
        ok = true;
      } else if (res.status === 429) {
        const wait = Number(res.headers.get('retry-after') ?? 10) * 1000 + 2000 * attempt;
        await sleep(wait);
      } else {
        console.warn(`  ${res.status} ${url}`);
        break;
      }
    }
    await sleep(2000);
    if (!ok) {
      failed++;
      continue;
    }
  }
  execFileSync('convert', [raw, '-auto-orient', '-resize', '800x800>', '-strip', '-quality', '66', out]);
  map[url] = rel;
  if (++done % 10 === 0) console.log(`  ${done} images`);
}

writeFileSync(mapFile, JSON.stringify(map, null, 1));
console.log(`commons: ${Object.keys(map).length} local, ${failed} failed, ${urls.size} referenced`);
