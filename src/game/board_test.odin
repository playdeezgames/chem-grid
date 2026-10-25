#+build !js
package game

import "core:testing"

@(test)
rotations_are_distinct_and_counted :: proc(t: ^testing.T) {
	for kind in Kind {
		seen: [dynamic]Sides
		defer delete(seen)
		for rot in 0 ..< 4 {
			b := bonds_of(kind, rot)
			testing.expect_value(t, card(b), card(BASE_BONDS[kind]))
			found := false
			for s in seen {
				found ||= s == b
			}
			if !found {
				append(&seen, b)
			}
		}
		testing.expect_value(t, len(seen), rotation_count(kind))
	}
}

@(test)
valence_matches_the_elements :: proc(t: ^testing.T) {
	testing.expect_value(t, card(BASE_BONDS[.H]), 1)
	testing.expect_value(t, card(BASE_BONDS[.O_Straight]), 2)
	testing.expect_value(t, card(BASE_BONDS[.O_Bent]), 2)
	testing.expect_value(t, card(BASE_BONDS[.N]), 3)
	testing.expect_value(t, card(BASE_BONDS[.C]), 4)
	testing.expect_value(t, card(BASE_BONDS[.He]), 0)
}

@(test)
straight_o_is_opposite_sides_and_bent_o_is_adjacent :: proc(t: ^testing.T) {
	testing.expect_value(t, bonds_of(.O_Straight, 1), Sides{.East, .West})
	testing.expect_value(t, bonds_of(.O_Bent, 0), Sides{.North, .East})
	testing.expect_value(t, bonds_of(.O_Bent, 3), Sides{.West, .North})
}

@(test)
bond_may_not_face_the_edge :: proc(t: ^testing.T) {
	b: Board
	// H at rotation 0 points North: illegal on the top row, fine on row 1.
	testing.expect(t, !valid_placement(&b, 0, 3, .H, 0))
	testing.expect(t, valid_placement(&b, 1, 3, .H, 0))
	// Corner: C has four bonds and can never go there.
	testing.expect(t, !valid_placement(&b, 0, 0, .C, 0))
	// A corner H must point South (rot 2) or East (rot 1).
	testing.expect(t, valid_placement(&b, 0, 0, .H, 1))
	testing.expect(t, valid_placement(&b, 0, 0, .H, 2))
	testing.expect(t, !valid_placement(&b, 0, 0, .H, 0))
	testing.expect(t, !valid_placement(&b, 0, 0, .H, 3))
}

@(test)
off_board_cells_and_occupied_cells_are_rejected :: proc(t: ^testing.T) {
	b: Board
	testing.expect(t, !valid_placement(&b, -1, 0, .He, 0))
	testing.expect(t, !valid_placement(&b, 0, 8, .He, 0))
	testing.expect(t, place(&b, 4, 4, .He, 0))
	testing.expect(t, !valid_placement(&b, 4, 4, .He, 0))
}

@(test)
matching_bonds_connect :: proc(t: ^testing.T) {
	b: Board
	testing.expect(t, place(&b, 4, 4, .H, 1)) // H pointing East
	// Right neighbour must have a West bond: H pointing West (rot 3).
	testing.expect(t, valid_placement(&b, 4, 5, .H, 3))
	testing.expect(t, !valid_placement(&b, 4, 5, .H, 1)) // East: no bond back at the H
	testing.expect(t, !valid_placement(&b, 4, 5, .H, 0))
	testing.expect(t, !valid_placement(&b, 4, 5, .He, 0)) // He cannot answer the H's bond
}

@(test)
bond_facing_a_plain_neighbour_is_rejected :: proc(t: ^testing.T) {
	b: Board
	testing.expect(t, place(&b, 4, 4, .He, 0))
	// An H pointing at Helium (which has no bonds) is illegal from any side.
	testing.expect(t, !valid_placement(&b, 4, 5, .H, 3))
	testing.expect(t, !valid_placement(&b, 3, 4, .H, 2))
	// An H pointing away from Helium is fine.
	testing.expect(t, valid_placement(&b, 4, 5, .H, 1))
	testing.expect(t, valid_placement(&b, 3, 4, .H, 0))
}

@(test)
neighbour_bond_must_be_answered :: proc(t: ^testing.T) {
	b: Board
	testing.expect(t, place(&b, 4, 4, .H, 1)) // points East
	// Helium next door would leave the H's bond facing a bondless atom.
	testing.expect(t, !valid_placement(&b, 4, 5, .He, 0))
	// Putting any atom with no bond facing West there is wrong; one with a West bond is right.
	testing.expect(t, valid_placement(&b, 4, 5, .O_Bent, 3)) // West and North
	testing.expect(t, !valid_placement(&b, 4, 5, .O_Bent, 0)) // North and East
}

@(test)
unmatched_bond_may_face_an_empty_cell :: proc(t: ^testing.T) {
	b: Board
	testing.expect(t, place(&b, 4, 4, .C, 0))
	testing.expect_value(t, b.cells[4][4].bonds, Sides{.North, .East, .South, .West})
}

@(test)
two_sided_check_at_once :: proc(t: ^testing.T) {
	b: Board
	testing.expect(t, place(&b, 4, 3, .H, 1)) // points East
	testing.expect(t, place(&b, 4, 5, .H, 3)) // points West
	// A straight O at (4,4) with East and West bonds meets both. Rotation 1.
	testing.expect(t, valid_placement(&b, 4, 4, .O_Straight, 1))
	testing.expect(t, !valid_placement(&b, 4, 4, .O_Straight, 0))
	testing.expect(t, !valid_placement(&b, 4, 4, .O_Bent, 0))
	// N missing its West bond cannot sit there either (West neighbour's bond unanswered).
	testing.expect(t, !valid_placement(&b, 4, 4, .N, 0))
}

@(test)
placements_list_matches_validity :: proc(t: ^testing.T) {
	b: Board
	out: Placements
	// Empty board: He fits everywhere; O straight fits each interior-ish cell in rotations that avoid edges.
	valid_placements(&b, .He, &out)
	testing.expect_value(t, out.count, 64)
	// H on empty board: 4 rotations x 64 cells minus the ones facing the edge: 4 sides x 8 cells.
	valid_placements(&b, .H, &out)
	testing.expect_value(t, out.count, 256 - 32)
	// C only fits where all four neighbours exist: the 6x6 interior.
	valid_placements(&b, .C, &out)
	testing.expect_value(t, out.count, 36)
	for i in 0 ..< out.count {
		p := out.items[i]
		testing.expect(t, valid_placement(&b, int(p.row), int(p.col), .C, int(p.rot)))
	}
	testing.expect(t, has_placement(&b, .C))
}

@(test)
full_board_has_no_placement :: proc(t: ^testing.T) {
	b: Board
	for row in 0 ..< BOARD_SIZE {
		for col in 0 ..< BOARD_SIZE {
			testing.expect(t, place(&b, row, col, .He, 0))
		}
	}
	for kind in Kind {
		testing.expect(t, !has_placement(&b, kind))
	}
}

@(test)
sprite_enum_matches_the_art_world :: proc(t: ^testing.T) {
	// The atlas packs the world's sprites in order; the enum must have as many.
	testing.expect_value(t, len(Sprite), 12)
	testing.expect_value(t, len(Sound), 7)
	testing.expect_value(t, ball_sprite(.O_Bent), Sprite.Ball_O)
	testing.expect_value(t, ball_sprite(.O_Straight), Sprite.Ball_O)
	for s in Side {
		testing.expect_value(t, int(bond_sprite(s)) - int(Sprite.Bond_North), int(s))
	}
}
