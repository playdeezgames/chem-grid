#+build !js
package game

import "core:testing"

place_ok :: proc(t: ^testing.T, b: ^Board, row, col: int, kind: Kind, rot: int) {
	testing.expectf(t, place(b, row, col, kind, rot), "placing %v rot %d at %d,%d", kind, rot, row, col)
}

occupied_count :: proc(b: ^Board) -> int {
	n := 0
	for row in 0 ..< BOARD_SIZE {
		for col in 0 ..< BOARD_SIZE {
			if b.cells[row][col].occupied { n += 1 }
		}
	}
	return n
}

@(test)
two_hydrogens_make_h2 :: proc(t: ^testing.T) {
	b: Board
	place_ok(t, &b, 4, 3, .H, 1)
	m := molecule_at(&b, 4, 3)
	testing.expect(t, !m.complete) // bond faces an empty cell
	place_ok(t, &b, 4, 4, .H, 3)
	m = resolve_placement(&b, 4, 4)
	testing.expect_value(t, m.count, 2)
	testing.expect_value(t, m.bonds, 1)
	testing.expect_value(t, occupied_count(&b), 0)
}

@(test)
water_completes_on_the_last_hydrogen :: proc(t: ^testing.T) {
	b: Board
	place_ok(t, &b, 4, 3, .H, 1)
	place_ok(t, &b, 4, 4, .O_Bent, 3) // West and North
	m := resolve_placement(&b, 4, 4)
	testing.expect_value(t, m.count, 0)
	testing.expect_value(t, occupied_count(&b), 2) // unfinished, left alone
	place_ok(t, &b, 3, 4, .H, 2)
	m = resolve_placement(&b, 3, 4)
	testing.expect_value(t, m.count, 3)
	testing.expect_value(t, m.bonds, 2)
	testing.expect_value(t, occupied_count(&b), 0)
}

@(test)
helium_is_never_a_molecule_and_stays :: proc(t: ^testing.T) {
	b: Board
	place_ok(t, &b, 4, 4, .He, 0)
	m := resolve_placement(&b, 4, 4)
	testing.expect_value(t, m.count, 0)
	testing.expect(t, b.cells[4][4].occupied)
	// A molecule beside helium still completes and leaves the helium.
	place_ok(t, &b, 4, 6, .H, 1)
	place_ok(t, &b, 4, 7, .H, 3)
	m = resolve_placement(&b, 4, 7)
	testing.expect_value(t, m.count, 2)
	testing.expect(t, b.cells[4][4].occupied)
	testing.expect_value(t, occupied_count(&b), 1)
}

@(test)
ring_of_four_carbons_completes_with_eight_hydrogens :: proc(t: ^testing.T) {
	b: Board
	place_ok(t, &b, 2, 2, .C, 0)
	place_ok(t, &b, 2, 3, .C, 0)
	place_ok(t, &b, 3, 2, .C, 0)
	place_ok(t, &b, 3, 3, .C, 0)
	// Outward bonds: (2,2) North and West, (2,3) North and East, (3,2) South and West, (3,3) South and East.
	hs := [8][3]int{
		{1, 2, 2}, {2, 1, 1}, // above and left of (2,2), pointing back
		{1, 3, 2}, {2, 4, 3},
		{4, 2, 0}, {3, 1, 1},
		{4, 3, 0}, {3, 4, 3},
	}
	for h, i in hs {
		place_ok(t, &b, h[0], h[1], .H, h[2])
		m := resolve_placement(&b, h[0], h[1])
		if i < 7 {
			testing.expect_value(t, m.count, 0)
		} else {
			testing.expect_value(t, m.count, 12)
			testing.expect_value(t, m.bonds, 12)
		}
	}
	testing.expect_value(t, occupied_count(&b), 0)
}

xorshift :: proc(s: ^u64) -> u64 {
	s^ ~= s^ << 13
	s^ ~= s^ >> 7
	s^ ~= s^ << 17
	return s^
}

// Play random legal moves and check, after every placement and before resolving, that at most one
// structure on the whole board is complete and that it is the one containing the placed atom.
@(test)
one_molecule_at_most_per_placement :: proc(t: ^testing.T) {
	kinds := [?]Kind{.H, .H, .H, .O_Straight, .O_Bent, .N, .C, .He}
	state: u64 = 0x9e3779b97f4a7c15
	completions := 0
	for game in 0 ..< 300 {
		b: Board
		out: Placements
		for _ in 0 ..< 400 {
			kind := kinds[xorshift(&state) % u64(len(kinds))]
			valid_placements(&b, kind, &out)
			if out.count == 0 {
				break
			}
			p := out.items[xorshift(&state) % u64(out.count)]
			place_ok(t, &b, int(p.row), int(p.col), kind, int(p.rot))

			seen: [BOARD_SIZE][BOARD_SIZE]bool
			complete_structures := 0
			contains_placed := false
			for row in 0 ..< BOARD_SIZE {
				for col in 0 ..< BOARD_SIZE {
					if !b.cells[row][col].occupied || seen[row][col] {
						continue
					}
					m := molecule_at(&b, row, col)
					for i in 0 ..< m.count {
						seen[m.cells[i].row][m.cells[i].col] = true
					}
					if m.complete {
						complete_structures += 1
						for i in 0 ..< m.count {
							if m.cells[i].row == p.row && m.cells[i].col == p.col {
								contains_placed = true
							}
						}
					}
				}
			}
			testing.expect(t, complete_structures <= 1)
			testing.expect(t, complete_structures == 0 || contains_placed)
			m := resolve_placement(&b, int(p.row), int(p.col))
			if m.count > 0 { completions += 1 }
			if complete_structures != 0 && m.count == 0 {
				testing.fail_now(t, "completed structure was not resolved")
			}
		}
	}
	testing.expect(t, completions > 100) // the test must actually exercise completions
}
