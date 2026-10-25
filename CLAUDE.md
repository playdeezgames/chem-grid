# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## State of the repo

Design is settled in `DESIGN.md` (rules, scoring table, art direction, level structure); read it before changing rules. Endless mode is playable in the browser (rules, supply, scoring, art, web layer); sound is in; levels (6 placeholders) are playable from a level-select screen; progress is saved in the browser. Task status is in Coxswain (project `chem-grid`).

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

## Levels

`src/game/levels.odin`: a `Level` is a supply (Bag with an ordered string of atoms `H O I(straight O) N C E(helium)`, optionally shuffled; or Weighted) shown as a Queue or Tray of `size`, plus `Goals` (min score; N of a named molecule, or of any with the `.None` entry; use the whole bag; at most N atoms left when the bag runs out). Goals combine; `game_level(index, seed)` makes a `Game` with `has_goals`, and `goals_met` is checked after each placement (goals about the end of the supply can only be met once it is empty). `Phase.Won` and `Event_Kind.Won` are new; a level whose bag runs dry with goals unmet ends as `Out_Of_Atoms`. Enum-indexed literals with missing entries need `#partial`. `levels_test.odin` holds a solver (DFS with a state hash; it tries connecting moves first and, unless `exhaustive`, only a few start cells for isolated atoms, so it can prove "winnable" but not "unwinnable") that every fixed-bag level must pass; add every new fixed-bag level to `LEVELS` and the test covers it. Weighted levels have no proof.

## Saves

`src/game/save.odin` (rules package, no browser code): one line of text, `CG1 m=0 e=1200 l=180,-,250` (mute, endless high score, then per level `-` for not cleared or the best winning score; levels past the list are not cleared, so adding levels is safe). `save_decode` is strict and returns defaults whole on anything malformed or out of range (fuzz-tested); `record_level` and `record_endless` return whether a record was set. The page reads and writes it through `storage_get` and `storage_set` (localStorage key `chem-grid-save`), loading in `main` and saving after a win, an endless game over, and a mute change. Bump `SAVE_MAGIC` if the format ever changes incompatibly.

## Web layer

`src/web/web.odin` is the whole page logic: screens (`Title`, `Select`, `Play`; a level game shows a goals panel and a win or lose overlay), drawing through three imports (`fill_rect`, `blit(sprite, x, y, alpha)`, `draw_text(x, y, text, rgb, scale)`), and exports the page calls (`pointer_move`, `pointer_down(x, y, precise)`, `pointer_leave`, `rotate_input`, `qa_phase`, `qa_start`). Coordinates are the 400x300 logical screen; the board is at (8, 8) and the panel at x = 276. A mouse places on click and shows a ghost on hover; a finger (`precise` = 0) selects a cell on the first tap and places on a second tap at the same cell. Every empty cell is tinted by whether the atom in hand fits (`cell_hint`): green check at the current rotation, yellow ? only after rotating, red x at no rotation; icons are 7x7 bitmaps drawn with `fill_rect` runs so colour is not the only cue. Text is DINOBYTE (`assets/font/dbyte_1x.png`, 6x8 cells, CC BY 4.0, credited on the title screen and to be on the itch page), tinted at draw time in `web/index.html`; keep that credit. Sound: `assets/sfx/*.wav` are PLAY-text sounds exported from the Anvil world (`sound_export`); `Sound` in `src/game/art.odin` must match `SOUND_FILES` in `web/index.html`, the page unlocks audio on the first key or pointer press, and the mute flag (M key or the SOUND button) is not saved yet (task 98). To exercise a whole game without playing it, run a loop in the browser console that dispatches `pointerdown` events at random cells (after `memory.exports.qa_start(level)`, or -1 for endless) until `memory.exports.qa_phase()` is no longer 1 (2 no moves, 3 out of atoms, 4 won) (the pane repaints only after a real mouse event, so hover once before a screenshot).

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
