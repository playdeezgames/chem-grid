#+build !js
package game

import "core:testing"

// Builds a board from a picture. Atoms sit on even rows and columns of the text; '-' and '|' between
// two atoms are a bond. Letters H O N C and E (helium). Each atom's bonds come from the neighbours
// drawn around it, so a bond that leads nowhere is left dangling (an incomplete molecule).
// Atoms are placed in reading order through the real placement rules, so the picture must be legal.
board_from_picture :: proc(t: ^testing.T, rows: []string) -> Board {
	b: Board
	at :: proc(rows: []string, r, c: int) -> u8 {
		if r < 0 || r >= len(rows) || c < 0 || c >= len(rows[r]) {
			return ' '
		}
		return rows[r][c]
	}
	for r := 0; r < len(rows); r += 2 {
		for c := 0; c < len(rows[r]); c += 2 {
			ch := at(rows, r, c)
			if ch == ' ' { continue }
			sides: Sides
			if at(rows, r - 1, c) == '|' { sides += {.North} }
			if at(rows, r, c + 1) == '-' { sides += {.East} }
			if at(rows, r + 1, c) == '|' { sides += {.South} }
			if at(rows, r, c - 1) == '-' { sides += {.West} }
			kind: Kind
			switch ch {
			case 'H': kind = .H
			case 'N': kind = .N
			case 'C': kind = .C
			case 'E': kind = .He
			case 'O': kind = sides == {.North, .South} || sides == {.East, .West} ? .O_Straight : .O_Bent
			}
			found := false
			for rot in 0 ..< rotation_count(kind) {
				if bonds_of(kind, rot) == sides {
					testing.expectf(t, place(&b, r / 2, c / 2, kind, rot), "placing %c at %d,%d", ch, r / 2, c / 2)
					found = true
					break
				}
			}
			testing.expectf(t, found, "no rotation of %v gives bonds %v at %d,%d", kind, sides, r / 2, c / 2)
		}
	}
	return b
}

// Complete the picture and score the molecule at row 0's first atom.
score_picture :: proc(t: ^testing.T, rows: []string) -> Score {
	b := board_from_picture(t, rows)
	for r in 0 ..< BOARD_SIZE {
		for c in 0 ..< BOARD_SIZE {
			if b.cells[r][c].occupied {
				m := molecule_at(&b, r, c)
				testing.expect(t, m.complete)
				return score_molecule(&m)
			}
		}
	}
	return {}
}

expect_score :: proc(t: ^testing.T, rows: []string, id: Molecule_Id, base: int) {
	s := score_picture(t, rows)
	testing.expect_value(t, s.id, id)
	testing.expect_value(t, s.base, base)
	testing.expect_value(t, s.bonus, MOLECULE_DEFS[id].bonus)
}

@(test)
every_listed_molecule_scores_the_documented_numbers :: proc(t: ^testing.T) {
	expect_score(t, {"H-H"}, .H2, 20)
	expect_score(t, {"H-O-H"}, .H2O, 80)
	expect_score(t, {"H-O", "  |", "  H"}, .H2O, 80) // bent oxygen is the same molecule
	expect_score(t, {"  H", "  |", "H-N-H"}, .NH3, 180)
	expect_score(t, {"  H", "  |", "H-C-H", "  |", "  H"}, .CH4, 320)
	expect_score(t, {"H-O-O-H"}, .H2O2, 180)
	expect_score(t, {"H-N-O-H", "  |", "  H"}, .NH2OH, 320)
	expect_score(t, {"H-N-N-H", "  | |", "  H H"}, .N2H4, 500)
	expect_score(t, {"  H", "  |", "H-C-O-H", "  |", "  H"}, .CH3OH, 500)
	expect_score(t, {"  H H", "  | |", "H-C-N-H", "  |", "  H"}, .CH3NH2, 720)
	expect_score(t, {"  H H", "  | |", "H-C-C-H", "  | |", "  H H"}, .C2H6, 980)
	expect_score(t, {"  H H", "  | |", "H-C-C-O-H", "  | |", "  H H"}, .C2H5OH, 1280)
	expect_score(t, {"  H   H", "  |   |", "H-C-O-C-H", "  |   |", "  H   H"}, .CH3OCH3, 1280)
	expect_score(t, {"  H H H", "  | | |", "H-C-C-C-H", "  | | |", "  H H H"}, .C3H8, 2000)
	expect_score(t, {"  H H", "  | |", "H-C-C-H", "  | |", "H-C-C-H", "  | |", "  H H"}, .C4H8, 2880)
}

@(test)
unlisted_molecule_scores_base_only :: proc(t: ^testing.T) {
	// Ethylamine, CH3CH2NH2: complete (10 atoms, 9 bonds) but not in the table.
	s := score_picture(t, {"  H H", "  | |", "H-C-C-N-H", "  | | |", "  H H H"})
	testing.expect_value(t, s, Score{id = .None, base = 1620, bonus = 0})
}

@(test)
isomers_are_told_apart :: proc(t: ^testing.T) {
	a := score_picture(t, {"  H H", "  | |", "H-C-C-O-H", "  | |", "  H H"})
	b := score_picture(t, {"  H   H", "  |   |", "H-C-O-C-H", "  |   |", "  H   H"})
	testing.expect_value(t, a.id, Molecule_Id.C2H5OH)
	testing.expect_value(t, b.id, Molecule_Id.CH3OCH3)
	testing.expect_value(t, a.base, b.base)
}

@(test)
table_is_consistent_with_valence :: proc(t: ^testing.T) {
	// For each def, the hydrogens that fill the skeleton's valences must pair up with the bonds:
	// valence sum of all atoms = 2 x bonds, and bonds = skeleton edges + hydrogens.
	for id in Molecule_Id.H2O ..= Molecule_Id.C4H8 {
		def := MOLECULE_DEFS[id]
		valence := 0
		for e in def.atoms {
			switch e {
			case .O: valence += 2
			case .N: valence += 3
			case .C: valence += 4
			}
		}
		hydrogens := valence - 2 * len(def.edges)
		testing.expectf(t, hydrogens > 0, "%s has no hydrogens", def.name)
	}
}

@(test)
helium_scores_nothing :: proc(t: ^testing.T) {
	b: Board
	testing.expect(t, place(&b, 3, 3, .He, 0))
	m := molecule_at(&b, 3, 3)
	s := score_molecule(&m)
	testing.expect_value(t, s, Score{})
}

@(test)
helium_is_not_part_of_a_skeleton :: proc(t: ^testing.T) {
	b: Board
	testing.expect(t, place(&b, 3, 3, .He, 0))
	m := molecule_at(&b, 3, 3)
	sk, ok := skeleton_of(&m)
	testing.expect(t, ok)
	testing.expect_value(t, sk.count, 0)
}
