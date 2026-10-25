#!/usr/bin/env python3
"""Draw chem-grid's 32x32 sprites and write them as an Anvil world (stdlib only).

Usage: gen_art.py assets/art/world.json
Open the result in Anvil (world_open) to look at or tweak it; re-export to the same path.
Sprite order is the order of SPRITES below; the Odin `Sprite` enum must list them the same way.

Atoms are balls with a letter; bonds are separate sticks drawn first, so rotation needs no
rotated sprites: draw a bond stick for each side the atom has, then the ball over them.
"""
import json, sys

T = 32
GAP = 2  # pixels between letters
# Palette index: meaning
PAL = [
    "#f2efe6",  # 0 board light (also the transparent colour of the balls and bonds)
    "#e4dfd0",  # 1 board alternate cell
    "#cdc6b0",  # 2 cell border
    "#2b2d42",  # 3 bond / dark ink
    "#f5c518",  # 4 H yellow
    "#a98a0c",  # 5 H rim
    "#d62828",  # 6 O red
    "#7a1414",  # 7 O rim
    "#28c4d6",  # 8 N cyan
    "#0d7482",  # 9 N rim
    "#111118",  # A C black
    "#7b7f99",  # B C rim (light grey, so a dark bond still reads against the ball)
    "#2f6fe0",  # C He blue
    "#173f8f",  # D He rim
    "#ffffff",  # E white (letters on dark balls)
    "#e8590c",  # F highlight orange
]

# 5x7 capital letters and a 5x5 lowercase e, drawn at 2x.
GLYPHS = {
    "H": ["X...X", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
    "O": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
    "N": ["X...X", "XX..X", "XX..X", "X.X.X", "X..XX", "X..XX", "X...X"],
    "C": [".XXX.", "X...X", "X....", "X....", "X....", "X...X", ".XXX."],
    "e": [".XXX.", "X...X", "XXXXX", "X....", ".XXXX"],
    # narrower pair for "He", which has to fit one ball
    "h": ["X..X", "X..X", "X..X", "XXXX", "X..X", "X..X", "X..X"],
    "n": [".XX.", "X..X", "XXXX", "X...", ".XXX"],  # a narrow "e"
}

def blank(c=0):
    return [[c] * T for _ in range(T)]

def ball(fill, rim, ink, text):
    g = blank(0)
    for y in range(T):
        for x in range(T):
            d2 = (x - 15.5) ** 2 + (y - 15.5) ** 2
            if d2 <= 13 ** 2:
                g[y][x] = rim if d2 > 11 ** 2 else fill
    # text: list of glyph names laid out left to right, 2x scale, 2 px gap, centred
    cells = [GLYPHS[ch] for ch in text]
    widths = [len(c[0]) * 2 for c in cells]
    total = sum(widths) + GAP * (len(cells) - 1)
    x0 = (T - total) // 2
    for c, w in zip(cells, widths):
        h = len(c) * 2
        y0 = 16 - 7 + (14 - h)  # bottoms of all letters line up on the same baseline
        for ry, row in enumerate(c):
            for rx, ch in enumerate(row):
                if ch == "X":
                    for dy in range(2):
                        for dx in range(2):
                            g[y0 + ry * 2 + dy][x0 + rx * 2 + dx] = ink
        x0 += w + GAP
    return g

def bond(side):
    g = blank(0)
    for y in range(T):
        for x in range(T):
            near = 14 <= x <= 17 and y <= 16     # north half
            if side == "north" and 14 <= x <= 17 and y <= 16: g[y][x] = 3
            if side == "south" and 14 <= x <= 17 and y >= 15: g[y][x] = 3
            if side == "west" and 14 <= y <= 17 and x <= 16: g[y][x] = 3
            if side == "east" and 14 <= y <= 17 and x >= 15: g[y][x] = 3
    return g

def cell(fill):
    g = blank(fill)
    for i in range(T):
        g[0][i] = g[T - 1][i] = g[i][0] = g[i][T - 1] = 2
    return g

def frame(c, thick):
    g = blank(0)
    for i in range(T):
        for k in range(thick):
            g[k][i] = g[T - 1 - k][i] = g[i][k] = g[i][T - 1 - k] = c
    return g

# name, pixels, transparent colour (-1 for none)
SPRITES = [
    ("ball_h", ball(4, 5, 3, "H"), 0),
    ("ball_o", ball(6, 7, 14, "O"), 0),
    ("ball_n", ball(8, 9, 3, "N"), 0),
    ("ball_c", ball(10, 11, 14, "C"), 0),
    ("ball_he", ball(12, 13, 14, "hn"), 0),
    ("bond_north", bond("north"), 0),
    ("bond_east", bond("east"), 0),
    ("bond_south", bond("south"), 0),
    ("bond_west", bond("west"), 0),
    ("cell_a", cell(0), -1),
    ("cell_b", cell(1), -1),
    ("frame", frame(15, 2), 0),
]

def pack(grid):
    out = []
    for row in grid:
        for x in range(0, T, 2):
            out.append(row[x] << 4 | row[x + 1])
    return out

def main(dst):
    w = json.load(open("/home/yermom/anvil-worlds/nice-apocalypse.json"))  # template for the schema
    w["tile_width"] = w["tile_height"] = T
    w["palette"] = [{"r": int(c[1:3], 16), "g": int(c[3:5], 16), "b": int(c[5:7], 16)} for c in PAL]
    w["tags"] = ["solid"]
    w["tilesets"] = [{"name": "art", "tileset": {"width": T, "height": T,
        "images": [{"name": n, "bytes": pack(g)} for n, g, _ in SPRITES]}}]
    w["sprite_sets"] = [{"name": "art", "sprites": [
        {"name": n, "tileset": "art", "image": n, "transparent": None if t < 0 else t} for n, _, t in SPRITES]}]
    w["sounds"] = []
    w["terrain_sets"] = []
    w["maps"] = []
    w["params"] = []
    w["feature_types"] = []
    w["features"] = []
    w["character_types"] = []
    w["characters"] = []
    w["player"] = None
    json.dump(w, open(dst, "w"))
    print(f"{dst}: {len(SPRITES)} sprites {T}x{T}: " + ", ".join(n for n, _, _ in SPRITES))

if __name__ == "__main__":
    main(sys.argv[1])
