// node --test 'scripts/*.test.mjs'
// The basemap styles scripts/export-ios.mjs writes to public/map/, read as committed: what the app
// bundles and the site serves. CI runs this before regenerating them, and then checks the regenerated
// files are the committed ones; this catches what that check cannot, an immutable copy left
// uncommitted (an untracked file is not a diff).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = new URL('../public/map/', import.meta.url).pathname;
const read = (name) => JSON.parse(readFileSync(join(dir, name), 'utf8'));
const files = readdirSync(dir).filter((f) => f.endsWith('.json'));
const pinned = files.filter((f) => f.includes('@'));
const TEMPLATE = /^https:\/\/tiles\.openfreemap\.org\/planet\/([^/]+)\/\{z\}\/\{x\}\/\{y\}\.pbf$/;

/** what the export names a style: its tile build, then the hash of the style without its metadata */
const nameOf = (style) => {
  const { metadata, ...bare } = style;
  const build = style.sources.omt.tiles[0].match(TEMPLATE)?.[1];
  return `${build}-${createHash('sha256').update(JSON.stringify(bare)).digest('hex').slice(0, 8)}`;
};

for (const theme of ['light', 'dark']) {
  test(`jp27-${theme}: the metadata names the tiles the style reads, and the build`, () => {
    const style = read(`jp27-${theme}.json`);
    const tiles = style.sources.omt.tiles[0];
    assert.match(tiles, TEMPLATE);
    assert.equal(style.metadata['jp27:tiles'], tiles);
    assert.equal(style.metadata['jp27:build'], nameOf(style));
    assert.match(style.metadata['jp27:build'], /^[^/]+-[0-9a-f]{8}$/);
  });

  test(`jp27-${theme}: its immutable copy is committed and is the same style`, () => {
    const style = read(`jp27-${theme}.json`);
    const name = `jp27-${theme}@${style.metadata['jp27:build']}.json`;
    assert.ok(files.includes(name), `${name} is missing: run npm run ios:data and commit public/map`);
    assert.deepEqual(read(name), style);
  });

  test(`jp27-${theme}-current: names no build, its tiles come from the TileJSON`, () => {
    const style = read(`jp27-${theme}-current.json`);
    assert.equal(style.sources.omt.url, 'https://tiles.openfreemap.org/planet');
    assert.equal(style.sources.omt.tiles, undefined);
    assert.equal(style.metadata?.['jp27:tiles'], undefined);
    assert.equal(style.metadata?.['jp27:build'], undefined);
  });
}

test('every immutable style is named by its own content', () => {
  assert.ok(pinned.length >= 2);
  for (const file of pinned) {
    const style = read(file);
    const [, theme, name] = file.match(/^jp27-(light|dark)@(.+)\.json$/) ?? [];
    assert.ok(theme, `${file}: not jp27-<theme>@<build>.json`);
    assert.equal(style.metadata['jp27:build'], name, file);
    assert.equal(nameOf(style), name, `${file}: changed since it was published`);
    assert.equal(style.metadata['jp27:tiles'], style.sources.omt.tiles[0], file);
  }
});
