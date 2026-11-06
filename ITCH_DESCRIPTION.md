# Itch.io page text

Page: https://thegrumpygamedev.itch.io/chem-grid
Pasted in by hand; nothing here is published by the repo.

## Short description

Place atoms on an 8x8 grid, match every bond, close molecules for points, and keep the helium from filling the board.

## Paste this as the page description

Atoms go on an 8x8 board, and every bond has to meet a bond (or an empty square). Close a molecule and it disappears and scores. Keep going until nothing you hold will fit.

**How it works**

- Pick an atom, turn it so its bonds face where you want them, and click a square. Hydrogen has one bond, oxygen two (straight or bent), nitrogen three, carbon four.
- A square is tinted by whether the atom in your hand fits there: a green check fits as it is, a yellow question mark fits if you rotate it, a red cross fits at no rotation. The icons differ in shape, so colour is not the only cue.
- A finished molecule scores the weight of its atoms times its bonds, and recognised ones (water, ammonia, methane, ethanol, propane, a ring of cyclobutane and more) earn a bonus.
- **Helium** has no bonds. It never completes and never leaves by itself, so it only takes up room. While one is in your tray it has to be placed before anything else.

**Endless:** a tray that starts with one atom and opens a new slot at 10,000, 20,000, 50,000, 100,000 and 200,000 points (six at most). A helium arrives every few placements, faster as the tray grows. Closing a molecule resets that countdown and lifts every helium on the board one square, and those on the top row escape. Your best score is saved in your browser, and goes on the online top scores (TOP SCORES on the title screen) under a name you choose.

**Levels:** twenty puzzles with their own supply of atoms and their own goals: build a named molecule, reach a score, use up the bag, or leave almost nothing behind. Your best score on each is saved.

**Controls:** click a square to place the atom in hand, R or the mouse wheel to rotate, Esc for the menu, M to mute. Touch: tap a square to select it, tap it again to place; use the ROTATE button.

**Online scores** are kept with LootLocker. All that is sent is your endless score, the name you type (or a random one), and an anonymous id made in your browser.

**Made with:** Odin, compiled to WebAssembly, drawing to a plain 2D canvas. The pixel art and sound effects were made with the Anvil of SPLORR!!, TheGrumpyGameDev's own asset tools. The text is DINOBYTE by mby (CC BY 4.0). The code, art and sounds were made with Claude (generative AI) working alongside TheGrumpyGameDev.

## Notes (not for the page)

- Push target: `thegrumpygamedev/chem-grid:html`. `tools/ship.sh` tests, builds with `-o:size` and zips; it only pushes with `--push`.
- On the page's Edit screen: "Kind of project" HTML, "This file will be played in the browser" ticked, embed 800 by 600 (the game is 400 by 300 and scales to fit).
- The cover is `assets/cover.png` (630 by 500, `tools/make_cover.py`); screenshots are in `assets/screenshots/` (1200 by 900, taken from the real build, in page order).
- Keep the DINOBYTE credit on the page. If the edit screen has a generative-AI disclosure field, fill it in to match.
- Saves use the localStorage key `chem-grid-save`.
- Online scores: do not paste the LootLocker lines until the board is live (the key is in `web/index.html` and `https://html-classic.itch.zone` is on the CORS Allowlist).
