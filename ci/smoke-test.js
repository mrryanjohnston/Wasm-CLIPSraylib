// Checks the generated page against the sources it was built from and against
// the assets/ tree it points at, so a broken page fails the build instead of
// being deployed. Runs after 'make html', needs node and nothing else.
//
// What it cannot check is the part that needs a GPU: whether the wasm actually
// boots and draws. Everything here is about the page being internally
// consistent and every url it names being present.
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const PAGE = 'tour-of-clipsraylib.html';

let failures = 0;
function check(ok, what, detail) {
  if (ok) return true;
  failures++;
  console.error(`FAIL ${what}${detail ? `\n     ${detail}` : ''}`);
  return false;
}
function read(p) {
  return fs.readFileSync(path.join(root, p), 'utf8');
}
// The page only ever carries these three, because they are the three build.sh
// escapes on the way in.
function unescapeHtml(s) {
  return s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}
// An asset url in the page (/assets/...) named as a path on disk. Spaces are
// the only character in these names that a browser would encode.
function assetPath(url) {
  return path.join(root, decodeURIComponent(url).replace(/^\//, ''));
}

const page = read(PAGE);

// --- nothing left unexpanded -------------------------------------------------
const leftover = page.match(/@[A-Z_]+@/g);
check(!leftover, 'no unexpanded placeholders', leftover && leftover.join(', '));

// --- the examples the page was built from ------------------------------------
const index = read('examples-index')
  .split('\n')
  .map((l) => l.trim())
  .filter(Boolean);
check(index.length > 0, 'examples-index is not empty');

const options = [...page.matchAll(/<option value="([^"]+)">([^<]*)<\/option>/g)].map((m) => [
  m[1],
  m[2],
]);
const divs = new Map(
  [...page.matchAll(/<div id="([^"]+)" class="hidden">([\s\S]*?)<\/div>/g)].map((m) => [
    m[1],
    unescapeHtml(m[2]),
  ])
);

check(
  options.length === index.length,
  'every indexed example has an option',
  `index ${index.length}, options ${options.length}`
);
check(
  options.every(([value, label], i) => value === `${index[i]}.bat` && label === value),
  'the picker lists the examples in examples-index order',
  options.map(([v]) => v).join(', ')
);
check(
  divs.size === index.length,
  'every indexed example has a hidden div',
  `index ${index.length}, divs ${divs.size}`
);

for (const slug of index) {
  const id = `${slug}.bat`;
  const src = read(path.join('examples', id));
  const inPage = divs.get(id);
  if (!check(inPage !== undefined, `${id} is in the page`)) continue;
  check(
    inPage.replace(/\n+$/, '') === src.replace(/\n+$/, ''),
    `${id} survived the trip into the page unchanged`
  );
}

const textarea = unescapeHtml(page.match(/<textarea id="code">([\s\S]*?)<\/textarea>/)[1]);
check(
  textarea.replace(/\n+$/, '') === read(path.join('examples', `${index[0]}.bat`)).replace(/\n+$/, ''),
  'the textarea opens on the first indexed example'
);

// --- every url the page names is staged in assets/ ---------------------------
const engineUrl = (page.match(/<script src="(\/assets\/[^"]+)"><\/script>/) || [])[1];
if (check(engineUrl, 'the page loads the engine from assets/')) {
  check(fs.existsSync(assetPath(engineUrl)), `${engineUrl} exists`);
  // emscripten resolves the wasm against the directory it was loaded from, so
  // it has to be a sibling and it has to still be called clipsraylib.wasm.
  const wasm = path.join(path.dirname(assetPath(engineUrl)), 'clipsraylib.wasm');
  if (check(fs.existsSync(wasm), 'clipsraylib.wasm sits beside the glue')) {
    check(
      fs.readFileSync(wasm).subarray(0, 4).equals(Buffer.from([0x00, 0x61, 0x73, 0x6d])),
      'clipsraylib.wasm is a wasm module'
    );
  }
  check(
    read(engineUrl.replace(/^\//, '')).includes('clipsraylib.wasm'),
    'the glue asks for clipsraylib.wasm by that name'
  );
}

const cssUrl = (page.match(/<link rel="stylesheet"[^>]*href="(\/assets\/[^"]+)"/) || [])[1];
if (check(cssUrl, 'the page links a stylesheet from assets/')) {
  check(fs.existsSync(assetPath(cssUrl)), `${cssUrl} exists`);
}

// --- textures: what the page fetches vs what was staged ----------------------
const jsString = "'((?:[^'\\\\]|\\\\.)*)'";
const pairs = [...page.matchAll(new RegExp(`^\\t\\t\\[${jsString}, ${jsString}\\],?$`, 'gm'))].map(
  (m) => [m[1], m[2]].map((s) => s.replace(/\\(.)/g, '$1'))
);
check(pairs.length > 0, 'the page fetches at least one texture');

for (const [name, url] of pairs) {
  const staged = assetPath(url);
  if (!check(fs.existsSync(staged), `${url} exists`)) continue;
  // The whole point of the per-texture hash: the url has to be derived from
  // the contents, or it is not safe to serve it immutable.
  const digest = crypto.createHash('sha256').update(fs.readFileSync(staged)).digest('hex');
  const stem = name.replace(/\.png$/, '');
  check(
    path.basename(url) === `${stem}.${digest.slice(0, 12)}.png`,
    `${name} is published under its own content hash`,
    `url ${path.basename(url)}, contents hash to ${digest.slice(0, 12)}`
  );
}

const fetched = pairs.map(([name]) => name).sort();
const built = fs
  .readdirSync(root)
  .filter((f) => f.endsWith('.png'))
  .sort();
check(
  fetched.join('\n') === built.join('\n'),
  'the page fetches exactly the textures the build produced',
  `page: ${fetched.join(', ')}\n     built: ${built.join(', ')}`
);
check(
  fs.readdirSync(assetPath('/assets/textures')).length === pairs.length,
  'assets/textures holds nothing the page does not ask for'
);

if (failures) {
  console.error(`\nsmoke-test: ${failures} check(s) failed`);
  process.exit(1);
}
console.log('smoke-test: ok');
