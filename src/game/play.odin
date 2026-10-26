package game

// The turn loop: one Game ties the board, the supply, completion and scoring together.
// The page sends Commands and reads the Events a step produced (the list is cleared at the start of each step).

Phase :: enum u8 {
	Playing,
	Out_Of_Moves, // none of the atoms on offer can be placed anywhere: the attempt is over
	Out_Of_Atoms, // a finite supply has been used up (in a level, with its goals unmet)
	Won,          // a level's goals are all met
}

Select :: struct {
	slot: int,
}
Rotate :: struct {
	turns: int, // +1 clockwise, -1 anticlockwise
}
Place :: struct {
	row, col: int,
}
Command :: union {
	Select,
	Rotate,
	Place,
}

Event_Kind :: enum u8 {
	Placed,
	Invalid,   // the placement was refused
	Rotated,
	Selected,
	Completed, // a molecule vanished; see the other fields
	Game_Over,
	Supply_Empty,
	Won,
	Tray_Grew, // endless mode: a new tray slot opened
	He_Added,  // endless mode: the helium countdown ran out and a He is coming
}

Event :: struct {
	kind:  Event_Kind,
	id:    Molecule_Id, // Completed: recognised molecule, or .None
	atoms: int,         // Completed: atoms removed
	score: int,         // Completed: points added, bonus included
	bonus: int,         // Completed: the recognised bonus part
}

MAX_EVENTS :: 8

Game :: struct {
	board:          Board,
	supply:         Supply,
	phase:          Phase,
	score:          int,
	turns:          int,         // atoms placed
	made:           [Molecule_Id]int, // molecules completed, by id (.None counts unlisted ones)
	atoms_cleared:  int,
	selected:       int,         // slot of the atom in hand
	rot:            int,         // its rotation
	events:         [MAX_EVENTS]Event,
	event_count:    int,
	endless:        bool,        // helium arrives on a countdown (see moves_to_he)
	moves_to_he:    int,         // endless: placements left before a He is the next piece
	has_goals:      bool,        // a level: the game is won when goals are met
	goals:          Goals,
	level:          int,         // index into LEVELS, when has_goals
}

// Endless mode: a tray that starts with one slot and gains one at each of these scores (six at most),
// filled from a random supply with no helium in it. Helium comes from a countdown instead: every
// he_interval(tray size) placements a He becomes the next piece, and completing a molecule restarts the
// countdown without one. So the board fills with helium unless the player keeps closing molecules.
ENDLESS_WEIGHTS := [Kind]int {
	.H          = 6,
	.O_Straight = 2,
	.O_Bent     = 2,
	.N          = 2,
	.C          = 1,
	.He         = 0,
}
TRAY_GROWTH_SCORES :: [5]int{1000, 2000, 5000, 10000, 20000}

// Placements between helium: 10 with a one-slot tray, one fewer for each slot gained, never below 5.
he_interval :: proc(tray_size: int) -> int {
	return max(11 - tray_size, 5)
}

// Tray slots an endless game has at this score.
endless_tray_size :: proc(score: int) -> int {
	size := 1
	for threshold in TRAY_GROWTH_SCORES {
		if score >= threshold { size += 1 }
	}
	return size
}

game_start :: proc(supply: Supply) -> Game {
	g := Game {
		supply = supply,
	}
	update_phase(&g)
	return g
}

game_endless :: proc(seed: u64) -> Game {
	g := game_start(supply_weighted(ENDLESS_WEIGHTS, .Tray, endless_tray_size(0), seed))
	g.endless = true
	g.moves_to_he = he_interval(g.supply.size)
	return g
}

// Number of atoms on the board (helium included).
atoms_on_board :: proc(g: ^Game) -> int {
	n := 0
	for row in g.board.cells {
		for c in row {
			if c.occupied { n += 1 }
		}
	}
	return n
}

molecules_made :: proc(g: ^Game) -> int {
	n := 0
	for k in g.made { n += k }
	return n
}

// Are all of the level's goals met right now? The goals about the end of the supply (use the whole bag,
// leave at most N atoms) can only be met once the supply is empty; the others can be met at any time.
goals_met :: proc(g: ^Game) -> bool {
	gl := g.goals
	if g.score < gl.min_score {
		return false
	}
	for id in Molecule_Id {
		need := gl.molecules[id]
		have := id == .None ? molecules_made(g) : g.made[id]
		if have < need {
			return false
		}
	}
	finished := supply_empty(&g.supply)
	if gl.use_whole_bag && !finished {
		return false
	}
	if limit, ok := gl.max_leftover.?; ok && (!finished || atoms_on_board(g) > limit) {
		return false
	}
	return true
}

// The atom in hand, if there is one.
in_hand :: proc(g: ^Game) -> (Kind, bool) {
	vis := supply_visible(&g.supply)
	if g.selected < 0 || g.selected >= len(vis) {
		return .He, false
	}
	return vis[g.selected], true
}

emit :: proc(g: ^Game, e: Event) {
	if g.event_count < MAX_EVENTS {
		g.events[g.event_count] = e
		g.event_count += 1
	}
}

events :: proc(g: ^Game) -> []Event {
	return g.events[:g.event_count]
}

// Over when none of the atoms the player can take can be placed; the supply being empty ends a finite game.
update_phase :: proc(g: ^Game) {
	if g.phase != .Playing {
		return
	}
	if supply_empty(&g.supply) {
		g.phase = .Out_Of_Atoms
		emit(g, {kind = .Supply_Empty})
		return
	}
	if g.selected >= g.supply.filled {
		g.selected = 0
	}
	// Only atoms the player can take count: the whole tray, but just the front of a queue.
	for k, slot in supply_visible(&g.supply) {
		if supply_can_take(&g.supply, slot) && has_placement(&g.board, k) {
			return
		}
	}
	g.phase = .Out_Of_Moves
	emit(g, {kind = .Game_Over})
}

step :: proc(g: ^Game, cmd: Command) {
	g.event_count = 0
	if g.phase != .Playing {
		return
	}
	switch c in cmd {
	case Select:
		if supply_can_take(&g.supply, c.slot) {
			g.selected = c.slot
			g.rot = 0
			emit(g, {kind = .Selected})
		}
	case Rotate:
		kind, ok := in_hand(g)
		if !ok { return }
		n := rotation_count(kind)
		g.rot = ((g.rot + c.turns) % n + n) % n
		emit(g, {kind = .Rotated})
	case Place:
		kind, ok := in_hand(g)
		if !ok { return }
		if !valid_placement(&g.board, c.row, c.col, kind, g.rot) {
			emit(g, {kind = .Invalid})
			return
		}
		place(&g.board, c.row, c.col, kind, g.rot)
		g.turns += 1
		emit(g, {kind = .Placed})
		m := resolve_placement(&g.board, c.row, c.col)
		if m.count > 0 {
			s := score_molecule(&m)
			g.score += total(s)
			g.made[s.id] += 1
			g.atoms_cleared += m.count
			emit(g, {kind = .Completed, id = s.id, atoms = m.count, score = total(s), bonus = s.bonus})
		}
		if g.endless {
			// Closing a molecule buys time; otherwise count down, and at zero a He takes the slot this
			// placement is about to refill.
			if m.count > 0 {
				g.moves_to_he = he_interval(g.supply.size)
			} else {
				g.moves_to_he -= 1
				if g.moves_to_he <= 0 {
					supply_inject(&g.supply, .He)
					g.moves_to_he = he_interval(g.supply.size)
					emit(g, {kind = .He_Added})
				}
			}
		}
		supply_take(&g.supply, g.selected)
		g.selected = 0
		g.rot = 0
		if g.has_goals && goals_met(g) {
			g.phase = .Won
			emit(g, {kind = .Won})
			return
		}
		if g.endless {
			if size := endless_tray_size(g.score); size > g.supply.size {
				supply_set_size(&g.supply, size)
				emit(g, {kind = .Tray_Grew})
			}
		}
		update_phase(g)
	}
}
