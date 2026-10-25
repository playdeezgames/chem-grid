package game

// Score of a completed molecule = (sum of atom points) x (bonds in it) + the bonus for a recognised one.
// Atom points are 10 x valence. Both forms of oxygen count as O.

Molecule_Id :: enum u8 {
	None,
	H2,
	H2O,
	NH3,
	CH4,
	H2O2,
	NH2OH,
	N2H4,
	CH3OH,
	CH3NH2,
	C2H6,
	C2H5OH,
	CH3OCH3,
	C3H8,
	C4H8,
}

Element :: enum u8 {
	O,
	N,
	C,
}

// Every complete molecule built from single bonds is fixed by its skeleton of non-hydrogen atoms:
// the hydrogens are whatever fills each atom's valence. So a recognised molecule is a skeleton
// (atoms and bonds between them) plus a bonus. H2 has an empty skeleton.
Edge :: [2]u8

Molecule_Def :: struct {
	name:  string,
	atoms: []Element,
	edges: []Edge,
	bonus: int,
}

MOLECULE_DEFS := [Molecule_Id]Molecule_Def {
	.None    = {name = "", bonus = 0},
	.H2      = {name = "H2", bonus = 20},
	.H2O     = {name = "H2O", atoms = {.O}, bonus = 100},
	.NH3     = {name = "NH3", atoms = {.N}, bonus = 150},
	.CH4     = {name = "CH4", atoms = {.C}, bonus = 200},
	.H2O2    = {name = "H2O2", atoms = {.O, .O}, edges = {{0, 1}}, bonus = 200},
	.NH2OH   = {name = "NH2OH", atoms = {.N, .O}, edges = {{0, 1}}, bonus = 300},
	.N2H4    = {name = "N2H4", atoms = {.N, .N}, edges = {{0, 1}}, bonus = 250},
	.CH3OH   = {name = "CH3OH", atoms = {.C, .O}, edges = {{0, 1}}, bonus = 300},
	.CH3NH2  = {name = "CH3NH2", atoms = {.C, .N}, edges = {{0, 1}}, bonus = 350},
	.C2H6    = {name = "C2H6", atoms = {.C, .C}, edges = {{0, 1}}, bonus = 400},
	.C2H5OH  = {name = "C2H5OH", atoms = {.C, .C, .O}, edges = {{0, 1}, {1, 2}}, bonus = 600},
	.CH3OCH3 = {name = "CH3OCH3", atoms = {.C, .O, .C}, edges = {{0, 1}, {1, 2}}, bonus = 600},
	.C3H8    = {name = "C3H8", atoms = {.C, .C, .C}, edges = {{0, 1}, {1, 2}}, bonus = 900},
	.C4H8    = {name = "C4H8", atoms = {.C, .C, .C, .C}, edges = {{0, 1}, {1, 2}, {2, 3}, {3, 0}}, bonus = 1500},
}

MAX_SKELETON :: 4

atom_points :: proc(kind: Kind) -> int {
	switch kind {
	case .H:                  return 10
	case .O_Straight, .O_Bent: return 20
	case .N:                  return 30
	case .C:                  return 40
	case .He:                 return 0
	}
	return 0
}

Skeleton :: struct {
	count: int,
	atoms: [MAX_SKELETON]Element,
	adj:   [MAX_SKELETON][MAX_SKELETON]bool,
	edges: int,
}

// The non-hydrogen atoms of a molecule and the bonds between them. ok is false when there are more
// than MAX_SKELETON of them, since no recognised molecule is that big.
skeleton_of :: proc(m: ^Molecule) -> (sk: Skeleton, ok: bool) {
	index: [BOARD_SIZE * BOARD_SIZE]int
	for i in 0 ..< m.count {
		index[i] = -1
		element: Element
		#partial switch m.kinds[i] {
		case .H, .He:
			continue // not part of the skeleton (helium has no bonds, so it is alone anyway)
		case .O_Straight, .O_Bent:
			element = .O
		case .N:
			element = .N
		case .C:
			element = .C
		}
		if sk.count == MAX_SKELETON {
			return sk, false
		}
		index[i] = sk.count
		sk.atoms[sk.count] = element
		sk.count += 1
	}
	for i in 0 ..< m.count {
		if index[i] < 0 { continue }
		for s in m.sides[i] {
			nr, nc := neighbour(int(m.cells[i].row), int(m.cells[i].col), s)
			for j in 0 ..< m.count {
				if int(m.cells[j].row) == nr && int(m.cells[j].col) == nc && index[j] > index[i] {
					sk.adj[index[i]][index[j]] = true
					sk.adj[index[j]][index[i]] = true
					sk.edges += 1
				}
			}
		}
	}
	return sk, true
}

// Does skeleton sk equal def, up to renumbering the atoms?
skeleton_matches :: proc(sk: ^Skeleton, def: ^Molecule_Def) -> bool {
	if sk.count != len(def.atoms) || sk.edges != len(def.edges) {
		return false
	}
	want: [MAX_SKELETON][MAX_SKELETON]bool
	for e in def.edges {
		want[e[0]][e[1]] = true
		want[e[1]][e[0]] = true
	}
	map_to: [MAX_SKELETON]int // sk atom i stands for def atom map_to[i]
	used: [MAX_SKELETON]bool
	return assign(sk, def, &want, &map_to, &used, 0)
}

@(private = "file")
assign :: proc(sk: ^Skeleton, def: ^Molecule_Def, want: ^[MAX_SKELETON][MAX_SKELETON]bool, map_to: ^[MAX_SKELETON]int, used: ^[MAX_SKELETON]bool, i: int) -> bool {
	if i == sk.count {
		return true
	}
	for j in 0 ..< sk.count {
		if used[j] || sk.atoms[i] != def.atoms[j] {
			continue
		}
		ok := true
		for k in 0 ..< i {
			if sk.adj[i][k] != want[j][map_to[k]] {
				ok = false
				break
			}
		}
		if !ok { continue }
		map_to[i] = j
		used[j] = true
		if assign(sk, def, want, map_to, used, i + 1) {
			return true
		}
		used[j] = false
	}
	return false
}

recognise :: proc(m: ^Molecule) -> Molecule_Id {
	if m.count == 0 || !m.complete {
		return .None
	}
	sk, ok := skeleton_of(m)
	if !ok {
		return .None
	}
	if sk.count == 0 {
		return m.count == 2 ? .H2 : .None // two hydrogens bonded to each other
	}
	for id in Molecule_Id.H2O ..= Molecule_Id.C4H8 {
		if skeleton_matches(&sk, &MOLECULE_DEFS[id]) {
			return id
		}
	}
	return .None
}

Score :: struct {
	id:    Molecule_Id,
	base:  int,
	bonus: int,
}

total :: proc(s: Score) -> int {
	return s.base + s.bonus
}

score_molecule :: proc(m: ^Molecule) -> Score {
	if m.count == 0 || !m.complete {
		return {}
	}
	points := 0
	for i in 0 ..< m.count {
		points += atom_points(m.kinds[i])
	}
	id := recognise(m)
	return {id = id, base = points * m.bonds, bonus = MOLECULE_DEFS[id].bonus}
}
