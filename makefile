CC = emcc
CFLAGS = -O3 -flto -DNDEBUG -s ASSERTIONS=0 -s ALLOW_MEMORY_GROWTH=1 -s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 -s ASYNCIFY=1 -s ASYNCIFY_STACK_SIZE=2097152
TARGET = CLIPSraylib.js

all: raylib/src/libraylib.web.a $(TARGET) 

raylib/src/libraylib.web.a:
	[ -d "raylib" ] || git clone https://github.com/raysan5/raylib.git
	$(MAKE) -C raylib/src PLATFORM=PLATFORM_WEB -B

$(TARGET): raylib/src/libraylib.web.a
	[ -d "CLIPSraylib" ] || git clone https://github.com/mrryanjohnston/CLIPSraylib.git
	cp makefile.CLIPS CLIPSraylib/src/makefile
	$(MAKE) -C CLIPSraylib/src -sEXPORTED_FUNCTIONS=_CreateEnvironment,_BatchStar,_Clear,_Reset
	cp CLIPSraylib/clipsraylib .
	cp CLIPSraylib/clipsraylib.wasm .
	cp CLIPSraylib/examples/*.png .

clean:
	$(MAKE) clean -C raylib/src
	$(MAKE) clean -C CLIPSraylib/src
	rm -f $(TARGET) raylib/src/libraylib.web.a CLIPSraylib/clipsraylib CLIPSraylib/clipsraylib.wasm *.png clipsraylib clipsraylib.wasm
