# Wasm-CLIPSraylib

## Description

This repo builds
[Tour of CLIPSraylib](https://ryjo.codes/tour-of-clipsraylib.html),
a website that lets you render programs defined in a `textarea` built with
[CLIPSraylib](https://github.com/mrryanjohnston/CLIPSraylib)
and render them to a `canvas` element.

## Layout

Generate `tour-of-clipsraylib.html` by running `build.sh` which uses:

```
template/page.html    the page around the examples: head, canvas, prose, scripts
examples/<slug>.bat   one CLIPSraylib program per file
examples-index        which examples appear in the picker, and in what order
tour-of-clipsraylib.css
```

Each example becomes an `<option>` in the program picker and a hidden `<div>`
the page copies into the `textarea` when you pick it. The div id is the
filename, which is also what the url hash uses
(`tour-of-clipsraylib.html#program-key.bat`), so a link to a specific program
keeps working across rebuilds. The first entry in `examples-index` is the
program the `textarea` starts out holding.

To add an example, drop `examples/my-example.bat` in and add `my-example` to
`examples-index`. To reorder or hide one, move or remove its line in
`examples-index`.

`template/page.html` carries these placeholders:

| placeholder | expands to |
| --- | --- |
| `@CSS_URL@` `@ENGINE_URL@` | content-addressed `assets/` urls |
| `@PROGRAM_DEFAULT@` | the first indexed example, inside the `textarea` |
| `@PROGRAM_OPTIONS@` | the picker `<option>` list |
| `@PROGRAM_SOURCES@` | every example, as a hidden `<div>` |
| `@TEXTURE_FILES@` | `[emscripten FS name, published url]` per `*.png` |

## Toolchain

The emscripten version is pinned in `.emscripten-version`, and that one file is
the source of truth for both local builds and CI. `make` refuses to build if the
`emcc` on your `PATH` disagrees with it, because the emcc version determines the
generated glue and therefore the content hash in the published asset urls.

To switch to the pinned version:

```
make emsdk                    # needs $EMSDK set to your emsdk checkout
source $EMSDK/emsdk_env.sh
```

To move the pin, edit `.emscripten-version` and commit it; CI follows on the
next push.

raylib and CLIPSraylib are pinned the same way, as commits in the `makefile`
(`RAYLIB_REF`, `CLIPSRAYLIB_REF`). Both are compiled straight into the wasm that
gets deployed, so a moving upstream default branch would otherwise change the
published artifact without anything in this repo changing.

## Building locally

You can build this on your local machine
by cloning this repo, running `make`, starting an http server,
and then navigating to the app in your web browser. For example:

```
git clone https://github.com/mrryanjohnston/Wasm-CLIPSraylib
cd Wasm-CLIPSraylib
make
make html
python3 -m http.server
```

Then visit
[http://0.0.0.0:8000/tour-of-clipsraylib.html](http://0.0.0.0:8000/tour-of-clipsraylib.html)
in a browser.

`make` compiles raylib and CLIPSraylib to `clipsraylib` + `clipsraylib.wasm` and
copies the example textures here. `make html` generates
`tour-of-clipsraylib.html` and stages `assets/`, which holds content-addressed
copies of the engine, the stylesheet and the textures:

```
assets/clipsraylib-<engine-id>/clipsraylib.js
assets/clipsraylib-<engine-id>/clipsraylib.wasm
assets/tour-of-clipsraylib.<css-id>.css
assets/textures/<name>.<texture-id>.png
```

The ids are truncated sha256 of the file contents, so editing an example leaves
them untouched. Because the assets are addressed by content they can be served
`immutable`, and a stale cached page still references the exact engine it was
built against, so a visitor can never get a new page against an old wasm.

The glue and the wasm share one id because they are two halves of a single
compile. The textures get one id each, in their filenames: they are independent
files, and a single id over the whole set would move every texture url whenever
any one of them was added or changed, throwing away the cached copy of all the
others.

The emscripten glue is `clipsraylib` here but is published as `clipsraylib.js`,
so that every static host in the chain types it as javascript on its own. The
wasm filename is baked into the glue, so it keeps its name and sits beside it.

None of the build output is tracked in git; `make clean` removes all of it.

`node ci/smoke-test.js` checks the built page against `examples/` and against the
staged `assets/`: that every example survived into the page unchanged, that the
picker matches `examples-index`, and that every url the page names is present.

## Deploying

`.github/workflows/deploy.yml` builds on every push and pull request, and
deploys to S3 + CloudFront on pushes to `main`.

Because the assets are addressed by content, they are uploaded once and served
`immutable` for a year, and only `tour-of-clipsraylib.html` is ever invalidated.
That also means a stale cached page still references the exact engine it was
built against, so a visitor can never get a new page against an old wasm.
