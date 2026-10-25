package game

// Levels: a supply plus goals. The goals can be combined; the level is won when all are met.

Goals :: struct {
	min_score:     int,                // 0: no score goal
	molecules:     [Molecule_Id]int,   // how many of each to complete; the entry for .None counts molecules of any kind
	use_whole_bag: bool,               // the supply must be used up (finite supplies only)
	max_leftover:  Maybe(int),         // when the supply is used up, at most this many atoms may remain on the board
}

Level :: struct {
	name:    string,
	source:  Source,
	view:    View,
	size:    int,         // queue preview length or tray size
	bag:     string,      // Bag source, in order: H, O (bent), I (straight O), N, C, E (helium)
	shuffle: bool,        // Bag source: shuffle it from the game's seed
	weights: [Kind]int,   // Weighted source
	goals:   Goals,
}

// A first few levels to prove the machinery; the real set is designed in a later task.
LEVELS := [?]Level {
	{
		name = "First Bond",
		source = .Bag, view = .Queue, size = 2,
		bag = "HH",
		goals = {molecules = #partial [Molecule_Id]int{.H2 = 1}},
	},
	{
		name = "Water",
		source = .Bag, view = .Queue, size = 3,
		bag = "HOH",
		goals = {molecules = #partial [Molecule_Id]int{.H2O = 1}, use_whole_bag = true},
	},
	{
		name = "Ammonia",
		source = .Bag, view = .Tray, size = 4,
		bag = "HNHH",
		goals = {molecules = #partial [Molecule_Id]int{.NH3 = 1}, use_whole_bag = true},
	},
	{
		name = "Methane and a Friend",
		source = .Bag, view = .Tray, size = 3,
		bag = "HHCHHE",
		goals = {molecules = #partial [Molecule_Id]int{.CH4 = 1}, use_whole_bag = true, max_leftover = 1},
	},
	{
		name = "Two Waters",
		source = .Bag, view = .Queue, size = 3,
		bag = "HOHHOH",
		shuffle = true,
		goals = {molecules = #partial [Molecule_Id]int{.H2O = 2}, use_whole_bag = true},
	},
	{
		name = "Keep Going",
		source = .Weighted, view = .Queue, size = 3,
		weights = #partial [Kind]int{.H = 6, .O_Bent = 3, .N = 2, .C = 1, .He = 1},
		goals = {min_score = 500},
	},
}

kind_from_char :: proc(c: u8) -> (Kind, bool) {
	switch c {
	case 'H': return .H, true
	case 'O': return .O_Bent, true
	case 'I': return .O_Straight, true
	case 'N': return .N, true
	case 'C': return .C, true
	case 'E': return .He, true
	}
	return .He, false
}

// The supply a level starts with, from a seed. A bad bag character is skipped (the level test rejects those).
level_supply :: proc(l: ^Level, seed: u64) -> Supply {
	if l.source == .Weighted {
		return supply_weighted(l.weights, l.view, l.size, seed)
	}
	kinds: [MAX_BAG]Kind
	n := 0
	for c in transmute([]u8)l.bag {
		if k, ok := kind_from_char(c); ok && n < MAX_BAG {
			kinds[n] = k
			n += 1
		}
	}
	return supply_bag(kinds[:n], l.shuffle, l.view, l.size, seed)
}

game_from_level :: proc(l: ^Level, index: int, seed: u64) -> Game {
	g := game_start(level_supply(l, seed))
	g.has_goals = true
	g.goals = l.goals
	g.level = index
	return g
}

game_level :: proc(index: int, seed: u64) -> Game {
	return game_from_level(&LEVELS[index], index, seed)
}
