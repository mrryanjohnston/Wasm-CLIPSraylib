CC = emcc
CFLAGS = -O3 -flto -DNDEBUG -s ASSERTIONS=0 -s ALLOW_MEMORY_GROWTH=1 -s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 -s ASYNCIFY=1 -s ASYNCIFY_STACK_SIZE=2097152
TARGET = clipsraylib
PAGE   = tour-of-clipsraylib.html

# Both dependencies are compiled straight into the wasm that gets deployed, so
# a moving upstream default branch would change the published artifact without
# anything in this repo changing. Pinned commits also give CI a cache key, and
# keep the content-addressed asset urls stable across rebuilds.
RAYLIB_REPO      = https://github.com/raysan5/raylib.git
RAYLIB_REF       = 1893226cb79506a7cad3658e76a11d9133dbeba0
CLIPSRAYLIB_REPO = https://github.com/mrryanjohnston/CLIPSraylib.git
CLIPSRAYLIB_REF  = cafcf5572bc9d20d5240440efc4f0dcaa9017f96

EMSDK_VERSION = $(shell cat .emscripten-version)
EMCC_VERSION  = $(shell $(CC) --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

.PHONY: all clean html check-emcc emsdk

all: $(TARGET)

# Generate the page from template/page.html + examples/ in the order set by
# examples-index. The engine, the stylesheet and the textures are inputs too:
# build.sh hashes the contents of each to name the assets/ copies the page links
# to, so any of them changing changes the page.
#
# Regenerated every time rather than dependency-tracked, because one of those
# textures is called "purple hero running.png" and make splits prerequisite
# lists on spaces. build.sh takes a fraction of a second, so there is nothing to
# save here. Writing through a temporary keeps a failed run from leaving a
# truncated page behind.
html: $(TARGET)
	sh build.sh > $(PAGE).tmp
	mv $(PAGE).tmp $(PAGE)

# Fail loudly on a toolchain mismatch
check-emcc:
	@[ -n "$(EMCC_VERSION)" ] || { echo "makefile: $(CC) not found on PATH (source \$$EMSDK/emsdk_env.sh)"; exit 1; }
	@[ "$(EMCC_VERSION)" = "$(EMSDK_VERSION)" ] || { \
		echo "makefile: emcc is $(EMCC_VERSION) but .emscripten-version pins $(EMSDK_VERSION)"; \
		echo "          run 'make emsdk' to switch, or edit .emscripten-version to move the pin"; \
		exit 1; }

emsdk:
	@[ -n "$$EMSDK" ] || { echo "makefile: set EMSDK to your emsdk checkout first"; exit 1; }
	$$EMSDK/emsdk install $(EMSDK_VERSION)
	$$EMSDK/emsdk activate $(EMSDK_VERSION)
	@echo "now run: source $$EMSDK/emsdk_env.sh"

raylib/src/libraylib.web.a: | check-emcc
	[ -d "raylib" ] || git clone $(RAYLIB_REPO) raylib
	git -C raylib rev-parse --verify --quiet $(RAYLIB_REF)^{commit} >/dev/null \
		|| git -C raylib fetch --quiet origin
	git -C raylib checkout --quiet --detach $(RAYLIB_REF)
	$(MAKE) -C raylib/src PLATFORM=PLATFORM_WEB -B

# Leaves clipsraylib (the emscripten glue), clipsraylib.wasm and the example
# textures in this directory; build.sh copies all three into assets/.
$(TARGET): raylib/src/libraylib.web.a makefile.CLIPS | check-emcc
	[ -d "CLIPSraylib" ] || git clone $(CLIPSRAYLIB_REPO) CLIPSraylib
	git -C CLIPSraylib rev-parse --verify --quiet $(CLIPSRAYLIB_REF)^{commit} >/dev/null \
		|| git -C CLIPSraylib fetch --quiet origin
	git -C CLIPSraylib checkout --quiet --detach $(CLIPSRAYLIB_REF)
	cp makefile.CLIPS CLIPSraylib/src/makefile
	$(MAKE) -C CLIPSraylib/src -sEXPORTED_FUNCTIONS=_CreateEnvironment,_BatchStar,_Clear,_Reset
	cp CLIPSraylib/clipsraylib .
	cp CLIPSraylib/clipsraylib.wasm .
	cp CLIPSraylib/examples/*.png .

clean:
	$(MAKE) clean -C raylib/src
	$(MAKE) clean -C CLIPSraylib/src
	rm -f raylib/src/libraylib.web.a CLIPSraylib/clipsraylib CLIPSraylib/clipsraylib.wasm
	rm -f $(TARGET) clipsraylib.wasm *.png $(PAGE) $(PAGE).tmp
	rm -rf assets
