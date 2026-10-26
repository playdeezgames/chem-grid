# chem-grid design

Status: draft, rules as stated by the user on October 25, 2026. Open questions are at the bottom.

## Rules (agreed)

- Played on an **8x8 grid board**.
- Pieces are atoms: Hydrogen (H, 1 bond), Oxygen (O, 2), Nitrogen (N, 3), Carbon (C, 4), Helium (He, 0). Simplified covalent bonds.
- Each turn the player puts an atom on an empty cell and may **rotate** it so its bond(s) face the desired directions.
- **Valid placement:** every bond of the new atom either (a) matches a bond on the neighbouring atom facing it, or (b) faces an empty board cell. A bond may never face off the board. (Implied: a neighbouring atom's bond that faces the new cell must be matched by one of the new atom's bonds, and a bond facing a neighbour with no matching bond is invalid.)
- A **completed molecule** is a connected structure with no unmatched bonds. It disappears and scores.
- **Helium** has no bonds, never completes into anything, never disappears, and so clutters the board.
- The game ends when **there are no valid moves**.

## Decisions (October 25, 2026)

- **Bonds:** one bond per side, no double or triple bonds. An atom's bonds face distinct sides, so two atoms share at most one bond. O may be straight or bent, N is a T, C uses all four sides; rotation matters.
- **Atom supply: three modes, all wanted.**
  - Random queue with a visible preview.
  - Tray: the player picks which atom to place from a hand.
  - Fixed bag: a set list of atoms, configurable as levels or missions.
- **Game over:** when the atom to place has no valid cell and rotation. With a tray: no atom in the tray can be placed. With a queue: the front atom can't be placed (previewed atoms don't count, since they can't be played yet). Implemented this way in `src/game/play.odin`.
- **Scoring:** points by the atoms in the molecule, plus extra for recognised molecules (see the Scoring section). Recognised molecules can also be a level's objectives.

- **Oxygen comes in two forms, generated as either straight or bent.** They are effectively different pieces (separate supply entries, separate sprites, 2 vs 4 rotations) but both are O and score the same. Without doubles, recognised molecules are single-bond only (H2O, CH4, NH3, H2O2, CH3OH, C2H6, ...).
- **Isolated placement is allowed:** only the bond-matching rules constrain a placement; an atom need not touch another.
- **Dead molecules** (can never be completed) are just clutter, like helium. No cleanup action. Found while testing: on this grid any set of required bonds on an empty cell can be filled by some atom kind (sizes 0 to 4 all have a kind), so a structure is only ever dead for lack of the right atom in the supply (or the cell filled by something else), never by geometry alone.
- **One molecule per placement:** a placement can complete at most one molecule, because completion can only change the connected structure the new atom belongs to. So there is no combo or simultaneous-completion rule. A unit test should assert this.

- **Helium** is just another weighted atom: a weight in the queue, a listed entry in a bag or tray. A level may have none.
- **Levels** give a fixed bag (plus a supply mode) and objectives: a score, N of a named molecule, or similar. Win when met; lose on game over.
- **Endless mode** is a tray filled from the random supply. It starts with 1 slot and gains a slot at 10000, 20000, 50000, 100000 and 200000 points (6 at most); levels set their own tray or queue size. Helium is not random in endless mode: a countdown starts at 10 placements (one fewer for each tray slot gained, never below 5) and when it reaches zero a He becomes the next piece, filling the slot that was just used. Completing a molecule restarts the countdown with no He and makes every helium on the board rise one square (those on the top row escape; a He with an atom above it stays). While a He is in the tray it must be placed before any other atom. So the board fills with helium unless the player keeps closing molecules, and every game ends. High score saved in the browser (localStorage).

## Scoring (approved October 25, 2026; numbers to be tuned in play)

**Base score** of a completed molecule = (sum of atom points) x (number of bonds in it). Atom points are 10 x valence: H 10, O 20, N 30, C 40 (both O forms 20). A tree molecule has atoms - 1 bonds, so size is rewarded roughly quadratically; a ring has one more bond than a tree of the same atoms.

**Recognised bonus** is a flat addition, found by matching the molecule's element-labelled bond graph, not its drawn shape (straight or bent O both count, any rotation or reflection counts). Isomers are told apart by connectivity.

| Molecule | Atoms | Base | Bonus |
|---|---|---|---|
| H2 | H-H | 20 | +20 |
| H2O | O with 2 H | 80 | +100 |
| NH3 | N with 3 H | 180 | +150 |
| CH4 | C with 4 H | 320 | +200 |
| H2O2 | H-O-O-H | 180 | +200 |
| NH2OH (hydroxylamine) | | 320 | +300 |
| N2H4 (hydrazine) | H2N-NH2 | 500 | +250 |
| CH3OH (methanol) | | 500 | +300 |
| CH3NH2 (methylamine) | | 720 | +350 |
| C2H6 (ethane) | | 980 | +400 |
| C2H5OH (ethanol) | | 1,280 | +600 |
| CH3OCH3 (dimethyl ether) | | 1,280 | +600 |
| C3H8 (propane) | | 2,000 | +900 |
| C4H8 (cyclobutane) | ring on a 2x2 square | 2,880 | +1,500 |

Notes:
- Only single-bond molecules exist; no CO2, O2, N2, HCN, formaldehyde, ethene. The bonus table must be checked against what is actually buildable (each row above was checked for valence: sum of valences = 2 x bonds).
- H2 is deliberately cheap, the easy way to clear space.
- Numbers are a first guess for tuning once the game is playable. Bonus is one table in the pure rules package so levels can also reference molecule ids as objectives.

## Art direction (October 25, 2026)

- **Tiles are 32x32**; the board is 8x8, so 256x256 px. Logical screen around 400x300 (board plus a side panel for the queue/tray, score and objectives), scaled by whole numbers.
- **Atoms are round balls with the element letter**, bonds drawn as sticks from the ball to the cell edge so they meet the neighbour's stick. Circle colours: **H yellow, O red, N cyan, C black, He blue**. Letters need contrast against each (light on black, red and blue; dark on yellow and cyan).
- **Background is a light colour; bonds are a dark contrasting colour.**
- 16-colour Anvil palette, bright atoms. Sprites needed: H, O straight (2 rotations), O bent (4), N (4), C, He; rotations are either separate sprites or drawn by the page by rotating one (decide when building the atlas).
- **Sound:** sound effects only, made in Anvil: place, rotate, invalid placement, molecule complete (a bigger sound for a recognised molecule), game over. Mute control required.

Light background confirmed (the "dark lab" pick was a mistake). Note: black C against dark bonds may blur at the join; give the black circle a light outline or bond tips a lighter cap if it reads badly.

## Levels (October 25, 2026)

- **About 20 levels, all unlocked from the start**, with a best score per level saved in the browser. Endless mode is separate.
- **Each level declares its own supply mode** (random queue with preview length N, tray of N, or fixed bag) plus its atoms, so all three modes appear.
- **Objectives, combinable per level:** reach a score; make N of a named molecule; use up the whole bag without game over; finish with at most N leftover atoms on the board. Win when all of a level's objectives are met; game over ends the attempt.
- **Level data is an Odin table in the pure rules package** (not JSON), so native tests can validate every level, and a solver test (as in Roomba Rights) can prove each fixed-bag level is winnable.

## The 20 levels (draft, October 25, 2026)

Source of truth is the `LEVELS` table in `src/game/levels.odin`; every fixed-bag level is proved winnable by the solver test. Bags list the atoms in arrival order (H, O bent, I straight O, N, C, E helium). "Queue n" shows n atoms but only the front can be placed; "Tray n" lets you pick.

| # | Name | Supply | Goal | What it teaches |
|---|---|---|---|---|
| 1 | First Bond | HH, queue 2 | one H2 | place, rotate, match |
| 2 | Water | HOH, queue 3 | one H2O, use the bag | bent oxygen |
| 3 | Pair Up | HHHH, queue 3 | two H2, use the bag | more than one molecule |
| 4 | Straight Shooter | HIH, queue 3 | one H2O, use the bag | straight oxygen (the atoms are in a line) |
| 5 | Ammonia | HNHH, tray 4 | one NH3, use the bag | nitrogen, the tray |
| 6 | Methane | CHHHH, tray 5 | one CH4, use the bag | carbon |
| 7 | Peroxide | HOOH, queue 4 | one H2O2, use the bag | chains |
| 8 | Noble Neighbours | EHOHE, queue 3 | one H2O, use the bag, at most 2 atoms left | helium clutter |
| 9 | Two Waters | HOHHOH shuffled, queue 3 | two H2O, use the bag | adapting to a random order |
| 10 | Methane and a Friend | HHCHHE, tray 3 | one CH4, use the bag, at most 1 left | helium with a small tray |
| 11 | Double Duty | HHHNHOH, tray 4 | one NH3 and one H2O, use the bag | two molecules from one tray |
| 12 | Methanol | CHHHOH, tray 6 | one CH3OH, use the bag | mixed skeleton |
| 13 | Hydrazine | NNHHHH, tray 6 | one N2H4, use the bag | nitrogen chain |
| 14 | Score Race | random queue 3, helium weight 5 of 21 | reach 3000 | free play toward a target (a simple greedy bot wins about 79 of 100) |
| 15 | Methylamine | CNHHHHH, tray 6 | one CH3NH2, use the bag | C and N together |
| 16 | Clean Sweep | HOHNHHH, tray 4 | NH3 and H2O, use the bag, nothing left | no waste |
| 17 | Ethane | CCHHHHHH, tray 6 | one C2H6, use the bag | bigger skeleton |
| 18 | Ethanol | CCOHHHHHH, tray 6 | one C2H5OH, use the bag | three-atom skeleton |
| 19 | Same Atoms, Ether | CICHHHHHH, tray 6 | one CH3OCH3, use the bag | isomers: the same atoms as ethanol with the oxygen in the middle, and it must be straight (a bent oxygen would force two hydrogens onto one cell) |
| 20 | The Ring | CCCCHHHHHHHH, tray 6 | one C4H8, use the bag | a ring on a 2x2 square |

Found while building these: a bent oxygen between two carbons cannot work (the carbons end up diagonal and one cell would need a hydrogen with two bonds), so the ether level uses a straight oxygen.

## Open questions

- The 20 levels themselves: the progression curve and what each introduces (needs a later session once the rules package exists).
- Queue preview length and tray size defaults.
- Font for the HUD and atom letters (not the ROM 8x8 without asking; see the BOK's DINOBYTE and Public Pixel notes).
