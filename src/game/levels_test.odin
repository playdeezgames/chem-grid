#+build !js
package game

import "core:fmt"
import "core:testing"

// ---- a solver: proves a level with a fixed bag can be won ----

Solver :: struct {
	seen:       map[u64]struct{},
	limit:      int,
	exceeded:   bool,
	exhaustive: bool, // false: an atom touching nothing is only tried on a few cells (fast, can only prove "winnable")
}

// Cells tried for an atom that touches no other atom, when not exhaustive.
SEED_CELLS := [?][2]int{{3, 3}, {3, 4}, {4, 3}, {4, 4}, {1, 1}, {1, 6}, {6, 1}, {6, 6}}

// Can skeleton sk be laid inside def (atoms of the same element, every bond of sk a bond of def)?
embeds :: proc(sk: ^Skeleton, def: ^Molecule_Def) -> bool {
	if sk.count > len(def.atoms) {
		return false
	}
	want: [MAX_SKELETON][MAX_SKELETON]bool
	for e in def.edges {
		want[e[0]][e[1]] = true
		want[e[1]][e[0]] = true
	}
	map_to: [MAX_SKELETON]int
	used: [MAX_SKELETON]bool
	place_atom :: proc(sk: ^Skeleton, def: ^Molecule_Def, want: ^[MAX_SKELETON][MAX_SKELETON]bool, map_to: ^[MAX_SKELETON]int, used: ^[MAX_SKELETON]bool, i: int) -> bool {
		if i == sk.count {
			return true
		}
		for j in 0 ..< len(def.atoms) {
			if used[j] || sk.atoms[i] != def.atoms[j] { continue }
			ok := true
			for k in 0 ..< i {
				if sk.adj[i][k] && !want[j][map_to[k]] { ok = false; break }
			}
			if !ok { continue }
			map_to[i] = j
			used[j] = true
			if place_atom(sk, def, want, map_to, used, i + 1) { return true }
			used[j] = false
		}
		return false
	}
	return place_atom(sk, def, &want, &map_to, &used, 0)
}

// A search heuristic for levels whose goals are named molecules: every unfinished structure on the
// board must still be able to become one of the molecules still needed. While heavy atoms are still
// to come its skeleton must fit inside such a molecule; once none are left it must be exactly one.
// Only used to cut the search; a state it rejects is never reported as a win.
can_still_finish :: proc(g: ^Game) -> bool {
	gl := g.goals
	if gl.min_score > 0 || gl.molecules[.None] > 0 {
		return true
	}
	heavy_left := false
	for k in supply_visible(&g.supply) {
		heavy_left ||= k != .H && k != .He
	}
	for i in g.supply.bag_next ..< g.supply.bag_count {
		k := g.supply.bag[i]
		heavy_left ||= k != .H && k != .He
	}
	seen: [BOARD_SIZE][BOARD_SIZE]bool
	for row in 0 ..< BOARD_SIZE {
		for col in 0 ..< BOARD_SIZE {
			if !g.board.cells[row][col].occupied || seen[row][col] { continue }
			m := molecule_at(&g.board, row, col)
			for i in 0 ..< m.count { seen[m.cells[i].row][m.cells[i].col] = true }
			sk, ok := skeleton_of(&m)
			if !ok { return false }
			if sk.count == 0 { continue }
			fits := false
			for id in Molecule_Id.H2O ..= Molecule_Id.C4H8 {
				if gl.molecules[id] - g.made[id] <= 0 { continue }
				def := &MOLECULE_DEFS[id]
				if heavy_left ? embeds(&sk, def) : skeleton_matches(&sk, def) {
					fits = true
					break
				}
			}
			if !fits { return false }
		}
	}
	return true
}

Move :: struct {
	slot, rot, row, col: int,
	rank:                int, // lower is tried first; see move_rank
}

// Order in which the solver tries moves, so it builds molecules the way a person would:
// close rings, then grow the skeleton of heavy atoms, then fill bonds with hydrogen, then start new
// molecules (biggest atom first), and leave helium until last.
move_rank :: proc(kind: Kind, links: int) -> int {
	heavy := kind != .H && kind != .He
	delta := clamp(card(BASE_BONDS[kind]) - 2 * links + 4, 0, 11) // open bonds gained: fewer is better
	switch {
	case kind == .He:  return 60
	case links >= 2:   return delta
	case links == 1 && heavy: return 12 + delta
	case links == 1:   return 24 + delta
	}
	return 36 + (4 - card(BASE_BONDS[kind]))
}

MAX_RANK :: 64

// A molecule completed that the level never asked for wastes atoms. The solver only needs to prove
// "winnable", so dropping such branches is safe: it can lose solutions but never invent one.
wasteful :: proc(g: ^Game) -> bool {
	gl := g.goals
	if gl.min_score > 0 || gl.molecules[.None] > 0 {
		return false
	}
	for id in Molecule_Id.H2 ..= Molecule_Id.C4H8 {
		if g.made[id] > gl.molecules[id] { return true }
	}
	return g.made[.None] > 0
}

fnv :: proc(h: ^u64, v: u64) {
	h^ = (h^ ~ v) * 0x100000001b3
}

// Everything that can change what happens next: the board, what is left of the supply, and progress to the goals.
state_key :: proc(g: ^Game) -> u64 {
	h := u64(0xcbf29ce484222325)
	for row in g.board.cells {
		for c in row {
			fnv(&h, c.occupied ? u64(c.kind) + 1 : 0)
			fnv(&h, u64(c.rot))
		}
	}
	fnv(&h, u64(g.supply.bag_next))
	fnv(&h, u64(g.supply.filled))
	// What the tray holds matters, not which slot holds it: hash the kinds in sorted order so that
	// taking the same atoms in a different order reaches the same state. (A queue is already in order.)
	kinds: [MAX_SLOTS]u64
	n := g.supply.filled
	for k, i in supply_visible(&g.supply) { kinds[i] = u64(k) }
	if g.supply.view == .Tray {
		for i in 1 ..< n {
			for j := i; j > 0 && kinds[j - 1] > kinds[j]; j -= 1 {
				kinds[j - 1], kinds[j] = kinds[j], kinds[j - 1]
			}
		}
	}
	for i in 0 ..< n { fnv(&h, kinds[i]) }
	fnv(&h, u64(g.score))
	for n in g.made { fnv(&h, u64(n)) }
	return h
}

solve_from :: proc(s: ^Solver, g: Game) -> bool {
	g := g
	if g.phase == .Won {
		return true
	}
	if g.phase != .Playing {
		return false
	}
	if !s.exhaustive && (wasteful(&g) || !can_still_finish(&g)) {
		return false
	}
	key := state_key(&g)
	if key in s.seen {
		return false
	}
	if len(s.seen) >= s.limit {
		s.exceeded = true
		return false
	}
	s.seen[key] = {}
	// Collect every legal move, then try the ones that join onto existing atoms first.
	moves: [MAX_SLOTS * 4 * BOARD_SIZE * BOARD_SIZE]Move
	count := 0
	vis := supply_visible(&g.supply)
	// Any finished board can be built heavy atoms first (a bond facing an empty cell is always legal),
	// so while a heavy atom can be placed the solver does not bother placing hydrogen or helium.
	heavy_takeable := false
	for slot in 0 ..< len(vis) {
		heavy_takeable ||= supply_can_take(&g.supply, slot) && vis[slot] != .H && vis[slot] != .He
	}
	for slot in 0 ..< len(vis) {
		if !supply_can_take(&g.supply, slot) { continue }
		kind := vis[slot]
		if !s.exhaustive && heavy_takeable && (kind == .H || kind == .He) { continue }
		for rot in 0 ..< rotation_count(kind) {
			bonds := bonds_of(kind, rot)
			for row in 0 ..< BOARD_SIZE {
				for col in 0 ..< BOARD_SIZE {
					if !valid_placement(&g.board, row, col, kind, rot) { continue }
					links := 0
					for side in Side {
						nr, nc := neighbour(row, col, side)
						if in_bounds(nr, nc) && g.board.cells[nr][nc].occupied && side in bonds {
							links += 1
						}
					}
					if links == 0 && !s.exhaustive {
						touching := false
						for side in Side {
							nr, nc := neighbour(row, col, side)
							touching ||= in_bounds(nr, nc) && g.board.cells[nr][nc].occupied
						}
						seed := false
						for c in SEED_CELLS { seed ||= c.x == row && c.y == col }
						if touching || !seed { continue }
					}
					moves[count] = {slot, rot, row, col, move_rank(kind, links)}
					count += 1
				}
			}
		}
	}
	// Counting sort by rank, stable, then try the moves in that order.
	tally: [MAX_RANK + 1]int
	for m in moves[:count] { tally[m.rank + 1] += 1 }
	for r in 1 ..= MAX_RANK { tally[r] += tally[r - 1] }
	ordered: [MAX_SLOTS * 4 * BOARD_SIZE * BOARD_SIZE]Move
	for m in moves[:count] {
		ordered[tally[m.rank]] = m
		tally[m.rank] += 1
	}
	for m in ordered[:count] {
		next := g
		game_step(&next, Select{m.slot})
		game_step(&next, Rotate{m.rot})
		game_step(&next, Place{m.row, m.col})
		if solve_from(s, next) {
			return true
		}
	}
	return false
}

game_step :: proc(g: ^Game, c: Command) {
	step(g, c)
}

// winnable: found a win. proven_unwinnable: searched everything and found none.
solve_level :: proc(l: ^Level, limit: int, exhaustive := false) -> (winnable: bool, proven_unwinnable: bool) {
	s := Solver{limit = limit, exhaustive = exhaustive}
	defer delete(s.seen)
	g := game_from_level(l, 0, 1)
	if solve_from(&s, g) {
		return true, false
	}
	return false, !s.exceeded
}

@(test)
every_fixed_bag_level_can_be_won :: proc(t: ^testing.T) {
	for &l, i in LEVELS {
		if l.source != .Bag || l.shuffle { continue }
		ok, _ := solve_level(&l, 200_000)
		testing.expectf(t, ok, "level %d (%s) could not be won", i, l.name)
	}
}

@(test)
shuffled_bag_levels_can_be_won_for_several_seeds :: proc(t: ^testing.T) {
	for &l, i in LEVELS {
		if l.source != .Bag || !l.shuffle { continue }
		for seed in u64(1) ..= 8 {
			// Solve with this seed's order by turning the shuffled bag into a fixed bag.
			g := game_from_level(&l, i, seed)
			fixed := l
			fixed.shuffle = false
			letters := [Kind]u8{.H = 'H', .O_Straight = 'I', .O_Bent = 'O', .N = 'N', .C = 'C', .He = 'E'}
			bag: [MAX_BAG]u8
			n := g.supply.bag_count
			for k, j in g.supply.bag[:n] {
				bag[j] = letters[k]
			}
			fixed.bag = string(bag[:n])
			ok, _ := solve_level(&fixed, 200_000)
			testing.expectf(t, ok, "level %d (%s) seed %d (%s) could not be won", i, l.name, seed, fixed.bag)
		}
	}
}

@(test)
solver_proves_an_impossible_level_unwinnable :: proc(t: ^testing.T) {
	l := Level {
		name = "Not enough hydrogen",
		source = .Bag, view = .Queue, size = 2,
		bag = "HO",
		goals = {molecules = #partial [Molecule_Id]int{.H2O = 1}},
	}
	won, proven := solve_level(&l, 1_000_000, true)
	testing.expect(t, !won)
	testing.expect(t, proven)
}

// ---- goals ----

@(test)
score_goal_wins_as_soon_as_it_is_met :: proc(t: ^testing.T) {
	l := Level {
		source = .Bag, view = .Queue, size = 2,
		bag = "HHHH",
		goals = {min_score = 40},
	}
	g := game_from_level(&l, 0, 1)
	step(&g, Rotate{1}); step(&g, Place{4, 3})
	step(&g, Rotate{3}); step(&g, Place{4, 4}) // H2: 20 + 20 = 40
	testing.expect_value(t, g.phase, Phase.Won)
	testing.expect_value(t, g.score, 40)
	// The attempt is over: more commands do nothing.
	turns := g.turns
	step(&g, Place{0, 0})
	testing.expect_value(t, g.turns, turns)
}

@(test)
bag_goals_wait_for_the_end_of_the_supply :: proc(t: ^testing.T) {
	l := Level {
		source = .Bag, view = .Queue, size = 2,
		bag = "HHE",
		goals = {molecules = #partial [Molecule_Id]int{.H2 = 1}, use_whole_bag = true},
	}
	g := game_from_level(&l, 0, 1)
	step(&g, Rotate{1}); step(&g, Place{4, 3})
	step(&g, Rotate{3}); step(&g, Place{4, 4}) // H2 made, but the helium is still to come
	testing.expect_value(t, g.phase, Phase.Playing)
	step(&g, Place{0, 0})
	testing.expect_value(t, g.phase, Phase.Won)
}

@(test)
leftover_limit_is_checked_when_the_bag_runs_out :: proc(t: ^testing.T) {
	l := Level {
		source = .Bag, view = .Queue, size = 2,
		bag = "EE",
		goals = {max_leftover = 1},
	}
	g := game_from_level(&l, 0, 1)
	step(&g, Place{0, 0})
	step(&g, Place{0, 1})
	// Two helium stay on the board, over the limit of one: the supply is used up and the level is lost.
	testing.expect_value(t, g.phase, Phase.Out_Of_Atoms)
	testing.expect_value(t, atoms_on_board(&g), 2)
}

@(test)
any_molecule_goal_counts_unlisted_ones_too :: proc(t: ^testing.T) {
	l := Level {
		source = .Bag, view = .Queue, size = 2,
		bag = "HHHH",
		goals = {molecules = #partial [Molecule_Id]int{.None = 2}},
	}
	g := game_from_level(&l, 0, 1)
	for pair in 0 ..< 2 {
		row := 2 + pair * 2
		step(&g, Rotate{1}); step(&g, Place{row, 3})
		step(&g, Rotate{3}); step(&g, Place{row, 4})
	}
	testing.expect_value(t, g.phase, Phase.Won)
}

// ---- the table ----

@(test)
level_table_is_well_formed :: proc(t: ^testing.T) {
	for &l, i in LEVELS {
		testing.expectf(t, l.name != "" && len(l.name) <= 20, "level %d: name %q must be 1 to 20 characters (it has to fit the side panel)", i, l.name)
		testing.expectf(t, l.size >= 1 && l.size <= MAX_SLOTS, "level %d: size %d", i, l.size)
		gl := l.goals
		has_goal := gl.min_score > 0 || gl.use_whole_bag
		for n in gl.molecules { has_goal ||= n > 0 }
		_, limited := gl.max_leftover.?
		has_goal ||= limited
		testing.expectf(t, has_goal, "level %d (%s) has no goal", i, l.name)
		switch l.source {
		case .Bag:
			testing.expectf(t, len(l.bag) > 0 && len(l.bag) <= MAX_BAG, "level %d: bag length %d", i, len(l.bag))
			for c in transmute([]u8)l.bag {
				_, ok := kind_from_char(c)
				testing.expectf(t, ok, "level %d: bad bag letter %c", i, c)
			}
		case .Weighted:
			total := 0
			for w in l.weights { total += w }
			testing.expectf(t, total > 0, "level %d: no weights", i)
			testing.expectf(t, !gl.use_whole_bag && !limited, "level %d: end-of-supply goal on an endless supply", i)
		}
	}
}

// ---- weighted levels have no proof, so check they are not hopeless: a simple greedy player ----

// Plays the front atom with the best-ranked legal move (see move_rank), starting new molecules on the
// seed cells. Not clever, but if it wins often the level is fair for a person.
greedy_win :: proc(l: ^Level, index: int, seed: u64, max_turns: int) -> (won: bool, turns: int) {
	g := game_from_level(l, index, seed)
	for g.phase == .Playing && g.turns < max_turns {
		kind, _ := in_hand(&g)
		best: Placement
		best_rank := 1 << 30
		for rot in 0 ..< rotation_count(kind) {
			bonds := bonds_of(kind, rot)
			for row in 0 ..< BOARD_SIZE {
				for col in 0 ..< BOARD_SIZE {
					if !valid_placement(&g.board, row, col, kind, rot) { continue }
					links := 0
					touching := false
					for side in Side {
						nr, nc := neighbour(row, col, side)
						occupied := in_bounds(nr, nc) && g.board.cells[nr][nc].occupied
						touching ||= occupied
						if occupied && side in bonds { links += 1 }
					}
					rank := move_rank(kind, links)
					if links == 0 && touching { rank += 20 } // do not crowd other atoms
					if links == 0 {
						// among isolated moves, prefer the middle of the board
						rank = rank * 10 + abs(row * 2 - 7) + abs(col * 2 - 7)
					} else {
						rank *= 10
					}
					if rank < best_rank {
						best_rank = rank
						best = {u8(row), u8(col), u8(rot)}
					}
				}
			}
		}
		if best_rank == 1 << 30 { break }
		step(&g, Rotate{int(best.rot)})
		step(&g, Place{int(best.row), int(best.col)})
	}
	return g.phase == .Won, g.turns
}

@(test)
weighted_levels_are_winnable_by_a_simple_player :: proc(t: ^testing.T) {
	for &l, i in LEVELS {
		if l.source != .Weighted { continue }
		wins := 0
		for seed in u64(1) ..= 100 {
			ok, _ := greedy_win(&l, i, seed, 300)
			if ok { wins += 1 }
		}
		fmt.printfln("level %d (%s): greedy bot won %d of 100", i, l.name, wins)
		testing.expectf(t, wins >= 20, "level %d (%s): greedy bot won only %d of 100", i, l.name, wins)
	}
}
