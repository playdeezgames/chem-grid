#+build !js
package game

import "core:testing"

has_event :: proc(g: ^Game, k: Event_Kind) -> bool {
	for e in events(g) {
		if e.kind == k { return true }
	}
	return false
}

@(test)
placing_two_hydrogens_scores_h2_and_uses_up_the_bag :: proc(t: ^testing.T) {
	g := game_start(supply_bag({.H, .H}, false, .Queue, 2, 1))
	step(&g, Rotate{1}) // H now points East
	step(&g, Place{4, 3})
	testing.expect_value(t, g.turns, 1)
	testing.expect_value(t, g.score, 0)
	testing.expect_value(t, g.phase, Phase.Playing)
	step(&g, Rotate{-1}) // West
	step(&g, Place{4, 4})
	testing.expect(t, has_event(&g, .Completed))
	testing.expect_value(t, g.score, 40) // base 20 + bonus 20
	testing.expect_value(t, g.made[.H2], 1)
	testing.expect_value(t, g.atoms_cleared, 2)
	testing.expect_value(t, g.phase, Phase.Out_Of_Atoms)
	testing.expect(t, has_event(&g, .Supply_Empty))
}

@(test)
illegal_placement_changes_nothing :: proc(t: ^testing.T) {
	g := game_start(supply_bag({.H, .He}, false, .Queue, 2, 1))
	step(&g, Place{0, 0}) // H pointing North off the board
	testing.expect(t, has_event(&g, .Invalid))
	testing.expect_value(t, g.turns, 0)
	testing.expect(t, !g.board.cells[0][0].occupied)
	testing.expect_value(t, len(supply_visible(&g.supply)), 2)
	hand, _ := in_hand(&g)
	testing.expect_value(t, hand, Kind.H)
}

@(test)
rotation_wraps_and_resets_with_each_new_atom :: proc(t: ^testing.T) {
	g := game_start(supply_bag({.O_Straight, .C, .H}, false, .Queue, 3, 1))
	step(&g, Rotate{1})
	step(&g, Rotate{1})
	testing.expect_value(t, g.rot, 0) // straight O has two rotations
	step(&g, Rotate{-1})
	testing.expect_value(t, g.rot, 1)
	step(&g, Place{3, 3})
	testing.expect_value(t, g.rot, 0)
	step(&g, Rotate{5}) // C has one rotation
	testing.expect_value(t, g.rot, 0)
}

@(test)
tray_selection :: proc(t: ^testing.T) {
	g := game_start(supply_bag({.H, .N, .C}, false, .Tray, 3, 1))
	step(&g, Select{1})
	hand, _ := in_hand(&g)
	testing.expect_value(t, hand, Kind.N)
	step(&g, Rotate{1})
	step(&g, Select{2})
	testing.expect_value(t, g.rot, 0)
	step(&g, Select{9}) // no such slot
	testing.expect_value(t, g.selected, 2)
	// A queue ignores selecting anything but the front.
	q := game_start(supply_bag({.H, .N, .C}, false, .Queue, 3, 1))
	step(&q, Select{1})
	testing.expect_value(t, q.selected, 0)
}

@(test)
unplaceable_atom_ends_the_game :: proc(t: ^testing.T) {
	kinds: [65]Kind
	for i in 0 ..< 64 { kinds[i] = .He }
	kinds[64] = .C
	g := game_start(supply_bag(kinds[:], false, .Queue, 1, 1))
	for row in 0 ..< BOARD_SIZE {
		for col in 0 ..< BOARD_SIZE {
			testing.expect_value(t, g.phase, Phase.Playing)
			step(&g, Place{row, col})
		}
	}
	testing.expect_value(t, g.phase, Phase.Out_Of_Moves)
	testing.expect(t, has_event(&g, .Game_Over))
	// The attempt is over: commands do nothing.
	turns := g.turns
	step(&g, Place{0, 0})
	testing.expect_value(t, g.turns, turns)
	testing.expect_value(t, g.event_count, 0)
}

@(test)
tray_with_one_placeable_atom_is_not_over :: proc(t: ^testing.T) {
	// Board full except one corner cell that only a bondless or inward-bonded atom fits.
	g := game_start(supply_bag({.C, .He}, false, .Tray, 2, 1))
	for row in 0 ..< BOARD_SIZE {
		for col in 0 ..< BOARD_SIZE {
			if row == 0 && col == 0 { continue }
			g.board.cells[row][col] = {occupied = true, kind = .He}
		}
	}
	update_phase(&g)
	testing.expect_value(t, g.phase, Phase.Playing) // C cannot go, but He can
	step(&g, Select{1})
	step(&g, Place{0, 0})
	testing.expect_value(t, g.phase, Phase.Out_Of_Moves) // only the C is left, and the board is full
}

@(test)
helium_interval_shrinks_with_the_tray :: proc(t: ^testing.T) {
	expected := [?]int{10, 9, 8, 7, 6, 5}
	for want, i in expected {
		testing.expect_value(t, he_interval(i + 1), want)
	}
	testing.expect_value(t, he_interval(20), 5) // never below 5
}

@(test)
endless_random_supply_has_no_helium :: proc(t: ^testing.T) {
	g := game_endless(3)
	for _ in 0 ..< 5000 {
		k, ok := draw(&g.supply)
		testing.expect(t, ok)
		if k == .He {
			testing.expect(t, false)
			return
		}
	}
}

// Place the hand on the first legal spot, or (far) the last, so two placements do not touch.
place_somewhere :: proc(g: ^Game, far: bool) {
	kind, _ := in_hand(g)
	out: Placements
	valid_placements(&g.board, kind, &out)
	p := far ? out.items[out.count - 1] : out.items[0]
	g.rot = int(p.rot)
	step(g, Place{int(p.row), int(p.col)})
}

@(test)
helium_becomes_the_next_piece_when_the_countdown_ends :: proc(t: ^testing.T) {
	g := game_endless(11)
	testing.expect_value(t, g.moves_to_he, 10)
	g.moves_to_he = 2
	place_somewhere(&g, false)
	testing.expect_value(t, g.moves_to_he, 1)
	testing.expect(t, !has_event(&g, .He_Added))
	place_somewhere(&g, true)
	testing.expect(t, has_event(&g, .He_Added))
	hand, ok := in_hand(&g)
	testing.expect(t, ok)
	testing.expect_value(t, hand, Kind.He)
	testing.expect_value(t, g.moves_to_he, he_interval(1)) // counting again
}

@(test)
completing_a_molecule_restarts_the_countdown_without_helium :: proc(t: ^testing.T) {
	g := game_endless(11)
	g.moves_to_he = 2 // without the molecule, the second placement would bring the helium
	g.supply.slots[0] = .H
	g.rot = 1
	step(&g, Place{4, 3})
	testing.expect_value(t, g.moves_to_he, 1)
	g.supply.slots[0] = .H
	g.rot = 3
	step(&g, Place{4, 4}) // H2 closes
	testing.expect(t, has_event(&g, .Completed))
	testing.expect(t, !has_event(&g, .He_Added))
	testing.expect_value(t, g.moves_to_he, he_interval(1))
	hand, _ := in_hand(&g)
	testing.expect(t, hand != .He)
}

@(test)
helium_fills_the_slot_that_was_just_used :: proc(t: ^testing.T) {
	g := game_endless(11)
	g.supply = supply_weighted(ENDLESS_WEIGHTS, .Tray, 3, 9)
	g.moves_to_he = 1
	step(&g, Select{1})
	untouched0 := supply_visible(&g.supply)[0]
	untouched2 := supply_visible(&g.supply)[2]
	place_somewhere(&g, false)
	vis := supply_visible(&g.supply)
	testing.expect_value(t, len(vis), 3)
	testing.expect_value(t, vis[1], Kind.He) // the slot that was used
	testing.expect_value(t, vis[0], untouched0)
	testing.expect_value(t, vis[2], untouched2)
}

@(test)
random_endless_games_always_end :: proc(t: ^testing.T) {
	state: u64 = 0xdeadbeefcafe
	for seed in 1 ..= 40 {
		g := game_endless(u64(seed))
		steps := 0
		for g.phase == .Playing && steps < 5000 {
			steps += 1
			// Pick a random on-offer atom that can be placed, then a random legal spot.
			vis := supply_visible(&g.supply)
			slot := int(xorshift(&state) % u64(len(vis)))
			step(&g, Select{slot}) // a queue refuses all but the front, which is fine
			kind, _ := in_hand(&g)
			out: Placements
			valid_placements(&g.board, kind, &out)
			if out.count == 0 {
				continue
			}
			p := out.items[xorshift(&state) % u64(out.count)]
			g.rot = int(p.rot)
			step(&g, Place{int(p.row), int(p.col)})
			testing.expect(t, !has_event(&g, .Invalid))
		}
		testing.expectf(t, g.phase == .Out_Of_Moves, "seed %d ended in %v after %d steps", seed, g.phase, steps)
		testing.expect(t, g.score >= 0)
		testing.expect(t, g.turns <= 64 + g.atoms_cleared) // the board never holds more than 64 atoms
	}
}

@(test)
queue_front_stuck_ends_the_game_even_if_later_atoms_fit :: proc(t: ^testing.T) {
	g := game_start(supply_bag({.C, .He}, false, .Queue, 2, 1))
	for row in 0 ..< BOARD_SIZE {
		for col in 0 ..< BOARD_SIZE {
			if row == 0 && col == 0 { continue }
			g.board.cells[row][col] = {occupied = true, kind = .He}
		}
	}
	update_phase(&g)
	testing.expect_value(t, g.phase, Phase.Out_Of_Moves) // He is previewed and would fit, but C is in front
}

@(test)
endless_tray_size_follows_the_score :: proc(t: ^testing.T) {
	cases := [?][2]int{{0, 1}, {9999, 1}, {10000, 2}, {19999, 2}, {20000, 3}, {49999, 3}, {50000, 4}, {99999, 4}, {100000, 5}, {199999, 5}, {200000, 6}, {1_000_000, 6}}
	for c in cases {
		testing.expect_value(t, endless_tray_size(c[0]), c[1])
	}
}

@(test)
endless_starts_with_a_one_slot_tray :: proc(t: ^testing.T) {
	g := game_endless(5)
	testing.expect_value(t, g.supply.view, View.Tray)
	testing.expect_value(t, g.supply.size, 1)
	testing.expect_value(t, len(supply_visible(&g.supply)), 1)
}

@(test)
endless_tray_gains_a_slot_when_the_score_passes_a_threshold :: proc(t: ^testing.T) {
	g := game_endless(5)
	g.score = 10000 // as if a molecule had just scored; the next placement notices
	out: Placements
	kind, _ := in_hand(&g)
	valid_placements(&g.board, kind, &out)
	g.rot = int(out.items[0].rot)
	step(&g, Place{int(out.items[0].row), int(out.items[0].col)})
	testing.expect(t, g.turns > 0)
	testing.expect_value(t, g.supply.size, 2)
	testing.expect_value(t, len(supply_visible(&g.supply)), 2)
	testing.expect(t, has_event(&g, .Tray_Grew))
	// The size never shrinks and caps at six.
	g.score = 1_000_000
	for _ in 0 ..< 3 {
		out: Placements
		kind, ok := in_hand(&g)
		if !ok || g.phase != .Playing { break }
		valid_placements(&g.board, kind, &out)
		if out.count == 0 { break }
		g.rot = int(out.items[0].rot)
		step(&g, Place{int(out.items[0].row), int(out.items[0].col)})
	}
	testing.expect_value(t, g.supply.size, 6)
}

@(test)
level_tray_size_stays_what_the_level_says :: proc(t: ^testing.T) {
	g := game_level(4, 1) // Ammonia: a tray of 4
	testing.expect_value(t, g.supply.view, View.Tray)
	testing.expect_value(t, g.supply.size, 4)
}

@(test)
helium_in_the_tray_must_be_played_first :: proc(t: ^testing.T) {
	g := game_endless(5)
	supply_set_size(&g.supply, 3)
	g.supply.slots[0] = .C
	g.supply.slots[1] = .He
	g.supply.slots[2] = .H
	update_phase(&g)
	testing.expect(t, he_in_tray(&g))
	testing.expect_value(t, g.selected, 1) // the He is put in hand
	step(&g, Select{0})
	testing.expect_value(t, g.selected, 1) // other atoms cannot be taken
	testing.expect(t, !can_take(&g, 2))
	testing.expect(t, can_take(&g, 1))
	g.supply.slots[1] = .N
	update_phase(&g)
	testing.expect(t, !he_in_tray(&g))
	step(&g, Select{0})
	testing.expect_value(t, g.selected, 0)
}

@(test)
helium_rises_as_far_as_it_can_and_escapes_on_a_straight_shot :: proc(t: ^testing.T) {
	b: Board
	he := Cell{occupied = true, kind = .He}
	b.cells[0][1] = he // top row: escapes
	b.cells[1][1] = he // under it: escapes too once the top one has gone
	b.cells[6][2] = he // clear column: escapes from far down
	b.cells[2][4] = {occupied = true, kind = .C, bonds = {.North, .East, .South, .West}}
	b.cells[3][4] = he // right under an atom: stays
	b.cells[7][4] = he // rises to just under the one above (row 4)
	b.cells[7][6] = he
	b.cells[6][6] = he
	b.cells[1][6] = {occupied = true, kind = .H, bonds = {.South}}
	// column 6: the stack rises together to rows 2 and 3
	rises: He_Rises
	testing.expect_value(t, drift_helium(&b, &rises), 3)
	for col in 0 ..< BOARD_SIZE {
		if col != 4 && col != 6 {
			for row in 0 ..< BOARD_SIZE {
				testing.expectf(t, !b.cells[row][col].occupied, "cell %d,%d should be empty", row, col)
			}
		}
	}
	testing.expect(t, b.cells[3][4].occupied && b.cells[3][4].kind == .He)
	testing.expect(t, b.cells[4][4].occupied && b.cells[4][4].kind == .He)
	testing.expect(t, !b.cells[7][4].occupied)
	testing.expect(t, b.cells[2][6].occupied && b.cells[2][6].kind == .He)
	testing.expect(t, b.cells[3][6].occupied && b.cells[3][6].kind == .He)
	testing.expect(t, !b.cells[6][6].occupied && !b.cells[7][6].occupied)
	testing.expect_value(t, rises.count, 6) // everything but the blocked one at (3, 4)
	found := false
	for r in rises.items[:rises.count] {
		if r == {2, 6, -1} { found = true }
	}
	testing.expect(t, found)
}

@(test)
closing_a_molecule_records_it_and_the_helium_rise :: proc(t: ^testing.T) {
	g := game_endless(7)
	g.board = {}
	g.board.cells[5][3] = {occupied = true, kind = .He}
	g.board.cells[0][0] = {occupied = true, kind = .H, bonds = {.East}}
	g.supply.slots[0] = .H
	g.selected, g.rot = 0, 0
	// an H facing west at (0, 1) closes H2
	for r in 0 ..< rotation_count(.H) {
		if bonds_of(.H, r) == {.West} { g.rot = r }
	}
	step(&g, Place{0, 1})
	testing.expect_value(t, g.cleared.count, 2)
	testing.expect_value(t, g.rises.count, 1)
	testing.expect_value(t, g.rises.items[0], He_Rise{3, 5, -1})
	step(&g, Rotate{1})
	testing.expect_value(t, g.cleared.count, 0)
	testing.expect_value(t, g.rises.count, 0)
}
