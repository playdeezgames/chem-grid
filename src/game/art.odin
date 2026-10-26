package game

// One entry per sprite in the Anvil world's "art" sprite set, in the same order (tools/gen_art.py SPRITES).
// tools/gen_atlas.py packs them into build/web/art.png left to right, each 32x32 (TILE).
// Atoms are drawn as: a bond stick for each side the atom has, then the ball on top, so rotating an
// atom needs no rotated sprites.
Sprite :: enum u8 {
	Ball_H,
	Ball_O,
	Ball_N,
	Ball_C,
	Ball_He,
	Bond_North,
	Bond_East,
	Bond_South,
	Bond_West,
	Cell_A,   // board cell, light
	Cell_B,   // board cell, slightly darker (checker)
	Frame,    // orange outline for the selected or hovered cell
}

ball_sprite :: proc(kind: Kind) -> Sprite {
	switch kind {
	case .H:                   return .Ball_H
	case .O_Straight, .O_Bent: return .Ball_O
	case .N:                   return .Ball_N
	case .C:                   return .Ball_C
	case .He:                  return .Ball_He
	}
	return .Ball_He
}

bond_sprite :: proc(s: Side) -> Sprite {
	switch s {
	case .North: return .Bond_North
	case .East:  return .Bond_East
	case .South: return .Bond_South
	case .West:  return .Bond_West
	}
	return .Bond_North
}

// One entry per exported sound, in the same order as SOUND_FILES in web/index.html (assets/sfx/*.wav, made in Anvil).
Sound :: enum u8 {
	Place,
	Rotate,
	Invalid,
	Molecule,   // a molecule closed and vanished
	Recognised, // ... and it was a known one (bigger sound)
	Game_Over,
	Win,        // a level objective met, or an endless tray slot gained
	Molecule_Big, // a big molecule vanished: a longer fanfare
}

// Molecules this size or bigger get the long fanfare, recognised or not.
BIG_MOLECULE_ATOMS :: 7

// Which sound a completed molecule makes: longer for bigger ones, and a recognised one sounds richer than a plain one.
completion_sound :: proc(id: Molecule_Id, atoms: int) -> Sound {
	if atoms >= BIG_MOLECULE_ATOMS {
		return .Molecule_Big
	}
	return id == .None ? .Molecule : .Recognised
}
