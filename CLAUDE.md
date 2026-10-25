# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## State of the repo

Design is settled in `DESIGN.md` (rules, scoring table, art direction, level structure); read it before changing rules. The scaffold exists and renders an empty 8x8 board; the game itself is not built yet. Task status is in Coxswain (project `chem-grid`).

```bash
tools/test.sh                 # native tests of src/game + odin check of both packages for js_wasm32
tools/test.sh -define:ODIN_TEST_NAMES=game.board_is_eight_by_eight   # a single test (extra args go to odin test)
tools/build.sh [--size]       # builds build/web (game.wasm, odin.js, index.html); --size for shipping
python3 -m http.server -d build/web 8000   # serve it; wasm cannot load from file://
```

Layout: `src/game` is the pure rules (no platform imports; clock and RNG passed in); `src/web` is `#+build js` (package `main`) and owns `step`, input and drawing through the `fill_rect` import; `web/index.html` holds the JS canvas shim and is copied by the build. Both import via `-collection:cg=src` (`import "cg:game"`). Logical screen is 400x300 with 32x32 tiles. Test files are `#+build !js`.

## Tools

- **Coxswain** (MCP server `coxswain`) tracks tasks. Project: `chem-grid`. **Your agent id is `heisenberg`**: pass `agent: "heisenberg"` and `agent_register` first. File work with `task_create` / `task_claim` / `task_complete` instead of keeping TODO lists in the repo.
- **Anvil** (MCP server `anvil-prod`, source `/home/yermom/git/anvil-of-splorr`) makes sprites, tiles, maps, palettes and sounds (`world_*`, `sprite_*`, `map_*`, `sound_*`, `render_*`). Worlds are saved as JSON in `/home/yermom/anvil-worlds`; use `world_export` / `sound_export` to get assets into the build, and keep the export in the repo (`assets/art/world.json`).
- **The BOK** (`/home/yermom/git/bok-of-splorr/splorr`, an additional working directory) is the user's knowledge base. Read `Home.md` first, then `Tech/Odin wasm recipe.md` (build, frame loop, input, and a catalogue of architecture variants to pick from), `Tech/Release standard.md`, `Tech/Shipping to itch.io.md`, `Tech/jsfxr sound effects.md` and `Gotchas.md`. Put new lessons in the BOK's `Gotchas.md`, not here. A sibling game to crib from: `/home/yermom/git/tggd-20seconds` (pure `src/game`, thin `src/web`, Anvil atlas and WAVs, touch buttons, ship script).

## Art

`assets/art/world.json` is an Anvil world export (copy to `/home/yermom/anvil-worlds/chem-grid.json` to open it with `world_open`): 32x32 sprites in one sprite set `art`, 16-colour palette (index 0, the board light, is the transparent colour of balls and bonds). `tools/gen_atlas.py` packs them into `build/web/art.png` in sprite-set order (run by `tools/build.sh`), and the `Sprite` enum in `src/game/art.odin` must list them in the same order. An atom is drawn as a bond stick for each side it has (`bond_north` etc.), then its ball (`ball_h` ...) on top, so nothing is rotated at draw time. `tools/gen_art.py` made the first version of the world (it reads a sibling game's world only as a schema template); after hand-editing in Anvil and re-exporting, do not rerun it over the export.

## Odin/wasm notes

- `tools/test.sh` also runs `odin check -vet-shadowing -vet-unused` on both packages for `js_wasm32`, because `odin check` does not apply those vet flags on its own; the build uses them too.
- Seed the RNG yourself (`rand.reset`); Odin constant arrays cannot be indexed by a runtime value (declare with `:=`); `int` is 32-bit on wasm.

## Release (itch.io)

Follows the BOK's `Release standard`: `ITCH_DESCRIPTION.md`, `assets/cover.png` (630x500), `assets/screenshots/`, `devlog/YYYYMMDD/`, `tools/ship.sh` plus a root `shippit.sh` that is exactly `exec "$(dirname "$0")/tools/ship.sh" "$@"`. `ship.sh` tests, builds, zips `build/web` (with `index.html` at the zip root) and pushes with butler **only with `--push`**; it never runs `git add` or `git commit`. New pages use channel `html`.

Rules that apply here:

- **Never** run `shippit.sh --push`, `butler push` or `git push` unless the user explicitly says so; if "push" is ambiguous, ask whether git or itch.
- In itch page copy and devlogs a game is a **"Metaphor"** (a non-game is a "Toy"), never a "Game". The user sets the project kind, pastes page copy and posts devlogs by hand.
- State generative-AI use honestly on the itch page; art and sound made through Anvil were made by Claude.
- If a font is needed, do not use the ROM font 8x8 without asking the user (offer DINOBYTE, then Public Pixel).
- Steam is out of scope unless the user raises it (free games only, no marketing, no prices).
