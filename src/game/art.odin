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
