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
	g := game_start(supply_bag({.H, .N, .He}, false, .Tray, 3, 1))
	step(&g, Select{1})
	hand, _ := in_hand(&g)
	testing.expect_value(t, hand, Kind.N)
	step(&g, Rotate{1})
	step(&g, Select{2})
	testing.expect_value(t, g.rot, 0)
	step(&g, Select{9}) // no such slot
	testing.expect_value(t, g.selected, 2)
	// A queue ignores selecting anything but the front.
	q := game_start(supply_bag({.H, .N, .He}, false, .Queue, 3, 1))
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
endless_helium_weight_climbs :: proc(t: ^testing.T) {
	g := game_endless(77)
	testing.expect_value(t, g.supply.weights[.He], 1)
	for _ in 0 ..< 25 {
		out: Placements
		kind, _ := in_hand(&g)
		valid_placements(&g.board, kind, &out)
		if out.count == 0 { break }
		p := out.items[0]
		g.rot = int(p.rot)
		step(&g, Place{int(p.row), int(p.col)})
		if g.phase != .Playing { break }
	}
	testing.expect_value(t, g.supply.weights[.He], 1 + g.turns / HE_EVERY)
	testing.expect(t, g.turns >= 10)
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
	cases := [?][2]int{{0, 1}, {999, 1}, {1000, 2}, {1999, 2}, {2000, 3}, {4999, 3}, {5000, 4}, {9999, 4}, {10000, 5}, {19999, 5}, {20000, 6}, {1_000_000, 6}}
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
	g.score = 1000 // as if a molecule had just scored; the next placement notices
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
