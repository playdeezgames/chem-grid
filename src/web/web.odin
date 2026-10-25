// Thin browser layer: input, drawing and the frame loop. Everything else is in package game.
#+build js
package main

import "base:runtime"
import "cg:game"

foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	// rgb is 0xRRGGBB; coordinates are logical pixels, y down.
	fill_rect :: proc(x, y, w, h: f32, rgb: u32, alpha: f32) ---
}

main :: proc() {}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = runtime.default_context()
	draw()
	free_all(context.temp_allocator)
	return true
}

draw :: proc() {
	fill_rect(0, 0, game.SCREEN_W, game.SCREEN_H, 0xf2efe6, 1)
	ox := f32(8)
	oy := f32(8)
	for row in 0 ..< game.BOARD_SIZE {
		for col in 0 ..< game.BOARD_SIZE {
			shade: u32 = (row + col) % 2 == 0 ? 0xe4e0d2 : 0xdad5c4
			fill_rect(ox + f32(col * game.TILE), oy + f32(row * game.TILE), game.TILE, game.TILE, shade, 1)
		}
	}
}
