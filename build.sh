#!/bin/sh
# Generate tour-of-clipsraylib.html from template/page.html + examples/ in the
# order given by examples-index. Each examples/<slug>.bat holds one CLIPSraylib
# program; it becomes an <option> in the program picker and a hidden <div> the
# page copies into the textarea. The first entry in the index is what the
# textarea starts out holding.
#
# As a side effect this also stages assets/ : the content-addressed copies of
# the engine, the stylesheet and the textures that the emitted page points at.
set -eu                 # abort on any error (-e) or use of an unset variable (-u)
cd "$(dirname "$0")"    # run from the script's own dir so relative paths resolve

for f in clipsraylib clipsraylib.wasm tour-of-clipsraylib.css; do
  [ -f "$f" ] || { echo "build.sh: missing $f (run 'make' first)" >&2; exit 1; }
done

# The textures the example programs load by name; 'make' copies them out of
# CLIPSraylib/examples. Collected through the glob rather than a hand-kept list
# so a new example texture only has to be dropped in.
set -- *.png
[ -e "$1" ] || { echo "build.sh: no *.png textures found (run 'make' first)" >&2; exit 1; }

# generate ids based on contents of the files
# in order to avoid issues that could arise from old tour-of-clipsraylib.html
# files referencing old versions of the engine, css or textures
#
# The glue and the wasm share one id because they are two halves of a single
# compile and can never meaningfully differ. The textures do not: they are
# independent files, so one id over the whole set would move every texture url
# whenever any one of them was added or changed, and throw away the cached copy
# of all the others. They get one hash each instead.
ENGINE_ID=$(cat clipsraylib clipsraylib.wasm | sha256sum | cut -c1-12)
CSS_ID=$(sha256sum tour-of-clipsraylib.css | cut -c1-12)

rm -rf assets
mkdir -p "assets/clipsraylib-$ENGINE_ID" assets/textures
# The glue is published with a .js extension it does not carry here, so that
# every static host in the chain types it as javascript on its own. The wasm
# filename is baked into the glue, so it has to keep its name and sit beside it.
cp clipsraylib "assets/clipsraylib-$ENGINE_ID/clipsraylib.js"
cp clipsraylib.wasm "assets/clipsraylib-$ENGINE_ID/"
cp tour-of-clipsraylib.css "assets/tour-of-clipsraylib.$CSS_ID.css"

# The textures go to awk through a file, as alternating name/url lines: some of
# them contain spaces, so they can neither ride along in a space-separated -v
# variable nor share a line with a delimiter between them.
TEXTURE_LIST=$(mktemp)
trap 'rm -f "$TEXTURE_LIST"' EXIT
for png in "$@"; do
  id=$(sha256sum -- "$png" | cut -c1-12)
  published="${png%.png}.$id.png"
  cp -- "$png" "assets/textures/$published"
  printf '%s\n/assets/textures/%s\n' "$png" "$published" >> "$TEXTURE_LIST"
done

awk \
  -v template=template/page.html \
  -v indexfile=examples-index \
  -v texturelist="$TEXTURE_LIST" \
  -v css_url="/assets/tour-of-clipsraylib.$CSS_ID.css" \
  -v engine_url="/assets/clipsraylib-$ENGINE_ID/clipsraylib.js" '
# Everything below is one shell-quoted awk program, so an apostrophe in here
# (even inside a comment) ends the quote: write "does not", never a contraction,
# and spell a literal quote as the four-character dance jsq() uses.
#
# die(): report a build error against the generated page and stop.
function die(msg){ print "build.sh: " msg > "/dev/stderr"; exit 1 }

# trim(): strip leading and trailing whitespace from a string and return it.
function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }

# slurp(): read a whole file into one string, keeping newlines. Errors out if
# the file cannot be read, so a typo in examples-index fails the build rather
# than emitting a silently empty program.
function slurp(f,   line,o,got){ o=""; got=0
  while((getline line < f) > 0){ o = o line "\n"; got=1 }
  close(f)
  if(!got) die("cannot read " f)
  sub(/\n$/,"",o)                                # drop the single trailing newline
  return o }

# esc(): escape the three characters that would otherwise be markup once the
# program text is inlined into the page. "\\&" is how a literal & is written in
# a gsub replacement, where a bare & means "the matched text".
function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }

# jsq(): quote a filename as a JavaScript single-quoted string literal. Built a
# character at a time rather than with gsub, whose replacement string has its
# own backslash rules to fight with.
function jsq(s,   o,i,c){ o="'"'"'"
  for(i=1;i<=length(s);i++){ c=substr(s,i,1)
    if(c=="\\" || c=="'"'"'") o = o "\\"
    o = o c }
  return o "'"'"'" }

# emit(): write one template line, expanding any placeholder on it. The scalar
# urls are substituted in place; a block placeholder (which may carry many
# lines) is spliced between whatever text sat either side of it, so it works
# both on a line of its own and inline, as inside the <textarea> tag.
function emit(line,   name,p,pre,post){
  gsub(/@CSS_URL@/, css_url, line)
  gsub(/@ENGINE_URL@/, engine_url, line)
  for(name in block){
    p = index(line, "@" name "@")
    if(p > 0){
      pre  = substr(line, 1, p-1)
      post = substr(line, p + length(name) + 2)
      printf "%s%s%s\n", pre, block[name], post
      return
    }
  }
  print line
}

# BEGIN: no input files are read as records; everything is driven from here.
BEGIN{
  N=0                                            # N = number of examples found
  while((getline s < indexfile) > 0){ if(s ~ /[^ \t]/){ slug[N]=trim(s); N++ } }  # read ordered, non-blank slugs
  close(indexfile)
  if(N==0) die("no examples listed in " indexfile)

  # The id is the filename, which is also what the url hash uses (#program-key.bat),
  # so a link into a specific program keeps working across rebuilds.
  for(i=0;i<N;i++){
    id[i] = slug[i] ".bat"
    if(id[i] ~ /["<>&]/) die("example name is not usable as an html id: " id[i])
    code[i] = esc(slurp("examples/" id[i]))
  }

  block["PROGRAM_DEFAULT"] = code[0]             # the program the textarea opens with

  o=""                                           # the <option> list for the picker
  for(i=0;i<N;i++) o = o (i?"\n":"") "	    <option value=\"" id[i] "\">" id[i] "</option>"
  block["PROGRAM_OPTIONS"] = o

  o=""                                           # every program, hidden, for the picker to copy from
  for(i=0;i<N;i++) o = o (i?"\n":"") "  <div id=\"" id[i] "\" class=\"hidden\">" code[i] "</div>"
  block["PROGRAM_SOURCES"] = o

  o=""; T=0                                      # the textures, as [fs name, published url] pairs
  while((getline t < texturelist) > 0){
    if((getline u < texturelist) <= 0) die("texture list ended mid-pair, after " t)
    o = o (T?",\n":"") "		[" jsq(t) ", " jsq(u) "]"; T++
  }
  close(texturelist)
  if(T==0) die("no textures in the texture list")
  block["TEXTURE_FILES"] = o

  while((getline line < template) > 0) emit(line)
  close(template)
}
'
