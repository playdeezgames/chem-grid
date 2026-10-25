package game

// The turn loop: one Game ties the board, the supply, completion and scoring together.
// The page sends Commands and reads the Events a step produced (the list is cleared at the start of each step).

Phase :: enum u8 {
	Playing,
	Out_Of_Moves, // none of the atoms on offer can be placed anywhere: the attempt is over
	Out_Of_Atoms, // a finite supply has been used up
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
	endless:        bool,        // helium weight rises as the game goes on
	he_base_weight: int,
}

// Endless mode: a random queue whose helium weight climbs by one every HE_EVERY turns,
// so every game ends.
ENDLESS_WEIGHTS := [Kind]int {
	.H          = 6,
	.O_Straight = 2,
	.O_Bent     = 2,
	.N          = 2,
	.C          = 1,
	.He         = 1,
}
ENDLESS_PREVIEW :: 3
HE_EVERY :: 10

game_start :: proc(supply: Supply) -> Game {
	g := Game {
		supply = supply,
	}
	update_phase(&g)
	return g
}

game_endless :: proc(seed: u64) -> Game {
	g := game_start(supply_weighted(ENDLESS_WEIGHTS, .Queue, ENDLESS_PREVIEW, seed))
	g.endless = true
	g.he_base_weight = ENDLESS_WEIGHTS[.He]
	return g
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
		supply_take(&g.supply, g.selected)
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
		g.selected = 0
		g.rot = 0
		if g.endless {
			g.supply.weights[.He] = g.he_base_weight + g.turns / HE_EVERY
		}
		update_phase(g)
	}
}
