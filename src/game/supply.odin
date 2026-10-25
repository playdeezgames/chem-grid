package game

// Where the next atoms come from. Two independent choices, which together give the three modes:
//  - the source: endless weighted random draws, or a finite bag (shuffled or in a fixed order);
//  - the view: a queue (only the front atom can be placed, the next few are previewed)
//    or a tray (several atoms shown, the player picks which to place).
// Queue + weighted is the "random queue"; tray + weighted is the "tray"; a bag source is the "fixed bag"
// (shown as a queue by default, or a tray when a level wants the player to choose the order).
// The RNG lives in the struct and is seeded by the caller, so a game is deterministic from its seed.

MAX_BAG :: 128
MAX_SLOTS :: 8

Source :: enum u8 {
	Weighted,
	Bag,
}

View :: enum u8 {
	Queue,
	Tray,
}

Supply :: struct {
	rng:       u64,
	source:    Source,
	view:      View,
	size:      int,            // slots shown: queue preview length including the front, or tray size
	weights:   [Kind]int,      // Weighted source: relative chance of each kind (0 never appears)
	bag:       [MAX_BAG]Kind,  // Bag source
	bag_count: int,
	bag_next:  int,            // next bag entry not yet shown
	slots:     [MAX_SLOTS]Kind,
	filled:    int,            // slots in use; fewer than size once a bag runs dry
}

next_random :: proc(s: ^Supply) -> u64 {
	// xorshift64*
	s.rng ~= s.rng >> 12
	s.rng ~= s.rng << 25
	s.rng ~= s.rng >> 27
	return s.rng * 0x2545F4914F6CDD1D
}

// A value in [0, n) for n > 0.
random_below :: proc(s: ^Supply, n: int) -> int {
	return int((next_random(s) >> 11) % u64(n))
}

supply_weighted :: proc(weights: [Kind]int, view: View, size: int, seed: u64) -> Supply {
	s: Supply
	s.rng = seed == 0 ? 0x9e3779b97f4a7c15 : seed
	s.source = .Weighted
	s.view = view
	s.size = clamp(size, 1, MAX_SLOTS)
	s.weights = weights
	refill(&s)
	return s
}

// A finite bag. With shuffle the order is random from the seed; without it the atoms come out in the given order.
supply_bag :: proc(kinds: []Kind, shuffle: bool, view: View, size: int, seed: u64) -> Supply {
	s: Supply
	s.rng = seed == 0 ? 0x9e3779b97f4a7c15 : seed
	s.source = .Bag
	s.view = view
	s.size = clamp(size, 1, MAX_SLOTS)
	s.bag_count = min(len(kinds), MAX_BAG)
	for i in 0 ..< s.bag_count {
		s.bag[i] = kinds[i]
	}
	if shuffle {
		for i := s.bag_count - 1; i > 0; i -= 1 {
			j := random_below(&s, i + 1)
			s.bag[i], s.bag[j] = s.bag[j], s.bag[i]
		}
	}
	refill(&s)
	return s
}

// Pull one atom from the source. false when a bag has run dry or every weight is zero.
draw :: proc(s: ^Supply) -> (Kind, bool) {
	switch s.source {
	case .Bag:
		if s.bag_next >= s.bag_count {
			return .He, false
		}
		k := s.bag[s.bag_next]
		s.bag_next += 1
		return k, true
	case .Weighted:
		total := 0
		for w in s.weights {
			total += max(w, 0)
		}
		if total == 0 {
			return .He, false
		}
		r := random_below(s, total)
		for k in Kind {
			r -= max(s.weights[k], 0)
			if r < 0 {
				return k, true
			}
		}
	}
	return .He, false
}

@(private = "file")
refill :: proc(s: ^Supply) {
	for s.filled < s.size {
		k, ok := draw(s)
		if !ok {
			return
		}
		s.slots[s.filled] = k
		s.filled += 1
	}
}

// Change how many slots are shown (a tray growing as the player scores). New slots fill straight away.
supply_set_size :: proc(s: ^Supply, size: int) {
	s.size = clamp(size, 1, MAX_SLOTS)
	refill(s)
}

supply_visible :: proc(s: ^Supply) -> []Kind {
	return s.slots[:s.filled]
}

// Atoms still to come, shown or not. Infinite sources report -1.
supply_remaining :: proc(s: ^Supply) -> int {
	if s.source == .Weighted {
		return -1
	}
	return s.filled + s.bag_count - s.bag_next
}

supply_empty :: proc(s: ^Supply) -> bool {
	return s.filled == 0
}

// Can the player take this slot? A queue only gives up its front.
supply_can_take :: proc(s: ^Supply, index: int) -> bool {
	if index < 0 || index >= s.filled {
		return false
	}
	return s.view == .Tray || index == 0
}

// Take an atom to place. A tray slot is refilled in place when the source has more; otherwise it
// closes up. The queue shifts forward. Returns false if that slot cannot be taken.
supply_take :: proc(s: ^Supply, index: int) -> (Kind, bool) {
	if !supply_can_take(s, index) {
		return .He, false
	}
	taken := s.slots[index]
	if s.view == .Tray {
		if k, ok := draw(s); ok {
			s.slots[index] = k
			return taken, true
		}
	}
	for i in index ..< s.filled - 1 {
		s.slots[i] = s.slots[i + 1]
	}
	s.filled -= 1
	refill(s)
	return taken, true
}
