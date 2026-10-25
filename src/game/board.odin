package game

// Rows run top (0) to bottom (BOARD_SIZE-1), columns left to right. North is row - 1.
Side :: enum u8 {
	North,
	East,
	South,
	West,
}
Sides :: bit_set[Side;u8]

// O comes in two forms that are separate pieces but both score as O.
Kind :: enum u8 {
	H,
	O_Straight,
	O_Bent,
	N,
	C,
	He,
}

// Bond sides at rotation 0. A rotation turns every bond one side clockwise (North to East to South to West).
BASE_BONDS := [Kind]Sides {
	.H          = {.North},
	.O_Straight = {.North, .South},
	.O_Bent     = {.North, .East},
	.N          = {.North, .East, .South},
	.C          = {.North, .East, .South, .West},
	.He         = {},
}

// Number of rotations that give distinct bond layouts.
rotation_count :: proc(kind: Kind) -> int {
	switch kind {
	case .H, .O_Bent, .N:
		return 4
	case .O_Straight:
		return 2
	case .C, .He:
		return 1
	}
	return 1
}

opposite :: proc(s: Side) -> Side {
	return Side((u8(s) + 2) % 4)
}

rotate_sides :: proc(sides: Sides, turns: int) -> Sides {
	out: Sides
	for s in sides {
		out += {Side((int(s) + turns) % 4)}
	}
	return out
}

bonds_of :: proc(kind: Kind, rot: int) -> Sides {
	return rotate_sides(BASE_BONDS[kind], rot)
}

Cell :: struct {
	occupied: bool,
	kind:     Kind,
	rot:      u8,
	bonds:    Sides,
}

Board :: struct {
	cells: [BOARD_SIZE][BOARD_SIZE]Cell,
}

Placement :: struct {
	row, col, rot: u8,
}

// Every legal (cell, rotation) for one kind. At most 64 cells times 4 rotations.
Placements :: struct {
	items: [BOARD_SIZE * BOARD_SIZE * 4]Placement,
	count: int,
}

in_bounds :: proc(row, col: int) -> bool {
	return row >= 0 && row < BOARD_SIZE && col >= 0 && col < BOARD_SIZE
}

neighbour :: proc(row, col: int, s: Side) -> (int, int) {
	switch s {
	case .North: return row - 1, col
	case .East:  return row, col + 1
	case .South: return row + 1, col
	case .West:  return row, col - 1
	}
	return row, col
}

// A placement is legal when the cell is empty and, on every side:
//  - off the board: no bond;
//  - next to an atom: either both atoms have a bond there or neither does;
//  - next to an empty cell: anything (an unmatched bond is fine, the molecule is just not complete yet).
valid_placement :: proc(board: ^Board, row, col: int, kind: Kind, rot: int) -> bool {
	if !in_bounds(row, col) || board.cells[row][col].occupied {
		return false
	}
	bonds := bonds_of(kind, rot)
	for s in Side {
		nr, nc := neighbour(row, col, s)
		if !in_bounds(nr, nc) {
			if s in bonds {
				return false
			}
			continue
		}
		other := board.cells[nr][nc]
		if !other.occupied {
			continue
		}
		if (s in bonds) != (opposite(s) in other.bonds) {
			return false
		}
	}
	return true
}

place :: proc(board: ^Board, row, col: int, kind: Kind, rot: int) -> bool {
	if !valid_placement(board, row, col, kind, rot) {
		return false
	}
	board.cells[row][col] = {
		occupied = true,
		kind     = kind,
		rot      = u8(rot),
		bonds    = bonds_of(kind, rot),
	}
	return true
}

valid_placements :: proc(board: ^Board, kind: Kind, out: ^Placements) {
	out.count = 0
	for row in 0 ..< BOARD_SIZE {
		for col in 0 ..< BOARD_SIZE {
			for rot in 0 ..< rotation_count(kind) {
				if valid_placement(board, row, col, kind, rot) {
					out.items[out.count] = {u8(row), u8(col), u8(rot)}
					out.count += 1
				}
			}
		}
	}
}

has_placement :: proc(board: ^Board, kind: Kind) -> bool {
	for row in 0 ..< BOARD_SIZE {
		for col in 0 ..< BOARD_SIZE {
			for rot in 0 ..< rotation_count(kind) {
				if valid_placement(board, row, col, kind, rot) {
					return true
				}
			}
		}
	}
	return false
}
