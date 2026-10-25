#+build !js
package game

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

Move :: struct {
	slot, rot, row, col, links: int,
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
	for k in supply_visible(&g.supply) { fnv(&h, u64(k)) }
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
	for slot in 0 ..< len(vis) {
		if !supply_can_take(&g.supply, slot) { continue }
		kind := vis[slot]
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
					moves[count] = {slot, rot, row, col, links}
					count += 1
				}
			}
		}
	}
	for want := 4; want >= 0; want -= 1 {
		for m in moves[:count] {
			if m.links != want { continue }
			next := g
			game_step(&next, Select{m.slot})
			game_step(&next, Rotate{m.rot})
			game_step(&next, Place{m.row, m.col})
			if solve_from(s, next) {
				return true
			}
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
		testing.expectf(t, l.name != "", "level %d has no name", i)
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
