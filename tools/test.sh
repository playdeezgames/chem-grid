#!/usr/bin/env bash
# Native tests of the pure rules, plus type-checks of both packages for wasm.
# One test: tools/test.sh -define:ODIN_TEST_NAMES=game.test_name
set -euo pipefail
cd "$(dirname "$0")/.."
odin test src/game -collection:cg=src -o:speed -define:ODIN_TEST_THREADS=1 "$@"
odin check src/game -collection:cg=src -target:js_wasm32 -no-entry-point -vet-shadowing -vet-unused
odin check src/web -collection:cg=src -target:js_wasm32 -vet-shadowing -vet-unused
