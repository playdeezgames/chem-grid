#!/usr/bin/env python3
"""Draw assets/cover.png (630x500) from the game's own sprite atlas and font.

Needs Pillow and a built build/web/art.png (tools/build.sh). The text is DINOBYTE (CC BY 4.0).
Sprite order is the Anvil sprite set: ball_h, ball_o, ball_n, ball_c, ball_he, bond_n/e/s/w, cell_a, cell_b, frame.
"""
from PIL import Image
W, H, S = 630, 500, 32
atlas = Image.open("build/web/art.png").convert("RGBA")
font = Image.open("assets/font/dbyte_1x.png").convert("RGBA")
BALL = dict(h=0, o=1, n=2, c=3, he=4)
BOND = dict(n=5, e=6, s=7, w=8)
sprite = lambda i: atlas.crop((i * S, 0, i * S + S, S))
BACK, INK, ACCENT = (0xf2, 0xef, 0xe6), (0x2b, 0x2d, 0x42), (0xd6, 0x28, 0x28)

img = Image.new("RGBA", (W, H), BACK + (255,))
K = 2                      # sprite scale
T = S * K                  # one board cell on the cover
def atom(kind, bonds, col, row):
    x, y = 91 + col * T, 250 + row * T
    cell = sprite(9).resize((T, T), Image.NEAREST)
    img.alpha_composite(cell, (x, y))
    for b in bonds:
        img.alpha_composite(sprite(BOND[b]).resize((T, T), Image.NEAREST), (x, y))
    img.alpha_composite(sprite(BALL[kind]).resize((T, T), Image.NEAREST), (x, y))

# A methane and a water, a helium in the way.
atom("c", "nesw", 1, 1)
atom("h", "s", 1, 0); atom("h", "n", 1, 2); atom("h", "w", 2, 1); atom("h", "e", 0, 1)
atom("o", "nw", 5, 1); atom("h", "e", 4, 1); atom("h", "s", 5, 0)
atom("he", "", 3, 2); atom("he", "", 6, 0)

def text(s, x, y, scale, rgb):
    tint = Image.new("RGBA", font.size, rgb + (255,))
    sheet = Image.composite(tint, Image.new("RGBA", font.size, (0, 0, 0, 0)), font.split()[3])
    for i, ch in enumerate(s):
        c = ord(ch) & 255
        g = sheet.crop(((c % 16) * 6, (c // 16) * 8, (c % 16) * 6 + 6, (c // 16) * 8 + 8))
        img.alpha_composite(g.resize((6 * scale, 8 * scale), Image.NEAREST), (x + i * 6 * scale, y))
def centred(s, y, scale, rgb):
    text(s, (W - len(s) * 6 * scale) // 2, y, scale, rgb)

centred("CHEM-GRID", 60, 10, INK)
centred("BUILD MOLECULES. DODGE HELIUM.", 160, 3, ACCENT)
centred("A METAPHOR", 462, 3, INK)
img.convert("RGB").save("assets/cover.png")
print("assets/cover.png", img.size)
