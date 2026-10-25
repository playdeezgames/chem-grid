package game

Pos :: struct {
	row, col: u8,
}

// A connected structure of bonded atoms.
Molecule :: struct {
	cells:    [BOARD_SIZE * BOARD_SIZE]Pos,
	kinds:    [BOARD_SIZE * BOARD_SIZE]Kind, // what each cell held, so scoring still works after removal
	sides:    [BOARD_SIZE * BOARD_SIZE]Sides,
	count:    int,
	bonds:    int,  // bonds inside the structure, each counted once
	complete: bool, // no bond faces an empty cell, and there is at least one bond
}

// Flood-fill the structure that contains (row, col). Atoms are joined where both have a bond across
// their shared edge, which is always the case for neighbouring bonds on a legally built board.
// A structure is complete when no bond faces an empty cell. Helium (no bonds) is never complete.
// Empty cell: count is 0.
molecule_at :: proc(board: ^Board, row, col: int) -> Molecule {
	m: Molecule
	if !in_bounds(row, col) || !board.cells[row][col].occupied {
		return m
	}
	seen: [BOARD_SIZE][BOARD_SIZE]bool
	seen[row][col] = true
	m.cells[0] = {u8(row), u8(col)}
	m.count = 1
	open := false
	bond_ends := 0
	for i := 0; i < m.count; i += 1 {
		r, c := int(m.cells[i].row), int(m.cells[i].col)
		bonds := board.cells[r][c].bonds
		bond_ends += card(bonds)
		for s in bonds {
			nr, nc := neighbour(r, c, s)
			if !in_bounds(nr, nc) || !board.cells[nr][nc].occupied || opposite(s) not_in board.cells[nr][nc].bonds {
				open = true
				continue
			}
			if !seen[nr][nc] {
				seen[nr][nc] = true
				m.cells[m.count] = {u8(nr), u8(nc)}
				m.count += 1
			}
		}
	}
	for i in 0 ..< m.count {
		cell := board.cells[m.cells[i].row][m.cells[i].col]
		m.kinds[i] = cell.kind
		m.sides[i] = cell.bonds
	}
	m.bonds = bond_ends / 2
	m.complete = !open && m.bonds > 0
	return m
}

remove_molecule :: proc(board: ^Board, m: ^Molecule) {
	for i in 0 ..< m.count {
		board.cells[m.cells[i].row][m.cells[i].col] = {}
	}
}

// After placing an atom at (row, col): if its structure is complete, remove it from the board and
// return it. Otherwise the board is untouched and the result has count 0.
// At most one structure can complete per placement, since only the placed atom's own structure changed.
resolve_placement :: proc(board: ^Board, row, col: int) -> Molecule {
	m := molecule_at(board, row, col)
	if m.complete {
		remove_molecule(board, &m)
		return m
	}
	return {}
}
