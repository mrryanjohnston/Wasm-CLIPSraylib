# Wasm-CLIPSraylib

## Description

This repo builds
[Tour of CLIPSraylib](https://ryjo.codes/tour-of-clipsraylib.html),
a website that lets you render programs defined in a `textarea` built with
[CLIPSraylib](https://github.com/mrryanjohnston/CLIPSraylib)
and render them to a `canvas` element.

## Building locally

You can build this on your local machine
by cloning this repo, running `make`, starting an http server,
and then navigating to the app in your web browser. For example:

```
git clone https://github.com/mrryanjohnston/Wasm-CLIPSraylib
make
python3 -m http.server
```

Then visit
[http://0.0.0.0:8000](http://0.0.0.0:8000)
in a browser.
