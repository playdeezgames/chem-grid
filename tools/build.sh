#!/usr/bin/env bash
# Build the wasm game into build/web. Pass --size for the shipping build.
set -euo pipefail
cd "$(dirname "$0")/.."
opt=speed
[[ "${1:-}" == "--size" ]] && opt=size
mkdir -p build/web
odin build src/web -collection:cg=src -target:js_wasm32 -out:build/web/game.wasm -o:$opt -vet-shadowing -vet-unused
cp "$(odin root)/core/sys/wasm/js/odin.js" build/web/
cp web/index.html web/lootlocker.js build/web/
cp assets/font/dbyte_1x.png build/web/font.png
python3 tools/gen_atlas.py assets/art/world.json build/web/art.png
mkdir -p build/web/sfx
cp assets/sfx/*.wav build/web/sfx/
echo "built build/web ($opt)"
