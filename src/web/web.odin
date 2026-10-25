// Thin browser layer: input, drawing and the frame loop. All rules are in package game.
#+build js
package main

import "base:runtime"
import "core:fmt"
import "core:sys/wasm/js"
import "core:time"
import "cg:game"

foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	// rgb is 0xRRGGBB; coordinates are logical pixels, y down.
	fill_rect :: proc(x, y, w, h: f32, rgb: u32, alpha: f32) ---
	// Draw sprite number `sprite` (game.Sprite) from the atlas with its top-left at x, y.
	blit :: proc(sprite: i32, x, y: f32, alpha: f32) ---
	// DINOBYTE text, 6 by 8 pixel cells times scale; x, y is the top-left.
	draw_text :: proc(x, y: f32, text: string, rgb: u32, scale: i32) ---
}

INK :: 0x2b2d42
DIM :: 0x6b6753
BACK :: 0xf2efe6
ACCENT :: 0xd62828
GOOD :: 0x1f7a3a

BOARD_X :: 8
BOARD_Y :: 8
BOARD_PX :: game.BOARD_SIZE * game.TILE
PANEL_X :: BOARD_X + BOARD_PX + 12 // 276
SLOT_PITCH :: 36
SLOTS_Y :: 74

Screen :: enum {
	Title,
	Play,
}

Rect :: struct {
	x, y, w, h: f32,
}

screen: Screen
play: game.Game
hover_row, hover_col: int
hover_set: bool

msg_buf: [40]u8
msg: string
msg_color: u32
msg_time: f32

main :: proc() {
	js.add_window_event_listener(.Key_Down, nil, on_key)
}

start_endless :: proc() {
	seed := u64(time.now()._nsec) | 1
	play = game.game_endless(seed)
	screen = .Play
	hover_set = false
	msg = ""
}

set_message :: proc(color: u32, format: string, args: ..any) {
	msg = fmt.bprintf(msg_buf[:], format, ..args)
	msg_color = color
	msg_time = 3
}

in_rect :: proc(r: Rect, x, y: f32) -> bool {
	return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
}

BUTTON_X :: f32(PANEL_X)
BUTTON_W :: f32(120)
rotate_button := Rect{BUTTON_X, 196, BUTTON_W, 20}
menu_button := Rect{BUTTON_X, 222, BUTTON_W, 20}
start_button := Rect{140, 150, 120, 28}

slot_rect :: proc(i: int) -> Rect {
	return {f32(PANEL_X + (i % 3) * SLOT_PITCH), f32(SLOTS_Y + (i / 3) * SLOT_PITCH), game.TILE, game.TILE}
}

cell_at :: proc(x, y: f32) -> (row, col: int, ok: bool) {
	if x < BOARD_X || y < BOARD_Y || x >= BOARD_X + BOARD_PX || y >= BOARD_Y + BOARD_PX {
		return 0, 0, false
	}
	return int(y - BOARD_Y) / game.TILE, int(x - BOARD_X) / game.TILE, true
}

// ---- input ----

take_events :: proc() {
	for e in game.events(&play) {
		#partial switch e.kind {
		case .Invalid:
			set_message(ACCENT, "NO ROOM THERE")
		case .Completed:
			name := game.MOLECULE_DEFS[e.id].name
			if e.id == .None { name = "MOLECULE" }
			set_message(GOOD, "%s +%d", name, e.score)
		}
	}
}

do_place :: proc(row, col: int) {
	game.step(&play, game.Place{row, col})
	take_events()
}

do_rotate :: proc(turns: int) {
	if screen == .Play && play.phase == .Playing {
		game.step(&play, game.Rotate{turns})
	}
}

do_select :: proc(slot: int) {
	if screen == .Play && play.phase == .Playing {
		game.step(&play, game.Select{slot})
	}
}

on_key :: proc(e: js.Event) {
	if e.key.repeat {
		return
	}
	code := e.key.code
	handled := true
	switch screen {
	case .Title:
		switch code {
		case "Enter", "Space": start_endless()
		case: handled = false
		}
	case .Play:
		if play.phase != .Playing {
			switch code {
			case "Enter", "Space": start_endless()
			case "Escape": screen = .Title
			case: handled = false
			}
			break
		}
		switch code {
		case "KeyR", "KeyE", "Space", "ArrowUp", "ArrowRight": do_rotate(1)
		case "KeyQ", "ArrowLeft", "ArrowDown": do_rotate(-1)
		case "Escape": screen = .Title
		case:
			if len(code) == 6 && code[:5] == "Digit" && code[5] >= '1' && code[5] <= '8' {
				do_select(int(code[5] - '1'))
			} else {
				handled = false
			}
		}
	}
	if handled {
		js.event_prevent_default()
	}
}

// Mouse moved (the page sends this only for a mouse): the ghost follows it.
@(export)
pointer_move :: proc "c" (x, y: f32) {
	context = runtime.default_context()
	row, col, ok := cell_at(x, y)
	hover_set = ok && screen == .Play
	hover_row, hover_col = row, col
}

@(export)
pointer_leave :: proc "c" () {
	hover_set = false
}

// A click or tap. precise is true for a mouse; a finger selects a cell first and a second tap there confirms.
@(export)
pointer_down :: proc "c" (x, y: f32, precise: i32) {
	context = runtime.default_context()
	switch screen {
	case .Title:
		if in_rect(start_button, x, y) {
			start_endless()
		}
	case .Play:
		if play.phase != .Playing {
			start_endless()
			return
		}
		if in_rect(rotate_button, x, y) {
			do_rotate(1)
		} else if in_rect(menu_button, x, y) {
			screen = .Title
		} else if row, col, ok := cell_at(x, y); ok {
			if precise != 0 || (hover_set && hover_row == row && hover_col == col) {
				do_place(row, col)
				hover_set = precise != 0
			} else {
				hover_set = true
				hover_row, hover_col = row, col
			}
			hover_row, hover_col = row, col
		} else {
			for i in 0 ..< play.supply.filled {
				if in_rect(slot_rect(i), x, y) {
					do_select(i)
				}
			}
		}
	}
}

// QA hook for scripted play: 0 title, 1 playing, 2 game over, 3 supply empty.
@(export)
qa_phase :: proc "c" () -> i32 {
	if screen == .Title { return 0 }
	return 1 + i32(play.phase)
}

// Wheel or right click: rotate.
@(export)
rotate_input :: proc "c" (turns: i32) {
	context = runtime.default_context()
	do_rotate(int(turns))
}

// ---- drawing ----

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = runtime.default_context()
	if msg_time > 0 {
		msg_time -= f32(dt)
		if msg_time <= 0 { msg = "" }
	}
	draw()
	free_all(context.temp_allocator)
	return true
}

draw_atom :: proc(kind: game.Kind, bonds: game.Sides, x, y, alpha: f32) {
	for s in bonds {
		blit(i32(game.bond_sprite(s)), x, y, alpha)
	}
	blit(i32(game.ball_sprite(kind)), x, y, alpha)
}

text_w :: proc(text: string, scale: i32) -> f32 {
	return f32(len(text)) * 6 * f32(scale)
}

draw_centered :: proc(cx, y: f32, text: string, rgb: u32, scale: i32) {
	draw_text(cx - text_w(text, scale) / 2, y, text, rgb, scale)
}

draw_button :: proc(r: Rect, label: string, enabled := true) {
	fill_rect(r.x, r.y, r.w, r.h, enabled ? INK : DIM, 1)
	fill_rect(r.x + 1, r.y + 1, r.w - 2, r.h - 2, BACK, 1)
	draw_centered(r.x + r.w / 2, r.y + (r.h - 8) / 2, label, enabled ? INK : DIM, 1)
}

draw :: proc() {
	fill_rect(0, 0, game.SCREEN_W, game.SCREEN_H, BACK, 1)
	switch screen {
	case .Title: draw_title()
	case .Play:  draw_play()
	}
}

draw_title :: proc() {
	draw_centered(200, 62, "CHEM-GRID", INK, 4)
	draw_centered(200, 108, "Place atoms. Match every bond.", DIM, 1)
	draw_centered(200, 120, "Close a molecule and it scores.", DIM, 1)
	draw_button(start_button, "ENDLESS")
	draw_centered(200, 196, "Mouse: click to place, R or wheel to rotate", DIM, 1)
	draw_centered(200, 208, "Touch: tap a cell, tap it again to place", DIM, 1)
	draw_centered(200, 284, "Font DINOBYTE by mby, CC BY 4.0", DIM, 1)
}

draw_board :: proc() {
	for row in 0 ..< game.BOARD_SIZE {
		for col in 0 ..< game.BOARD_SIZE {
			x := f32(BOARD_X + col * game.TILE)
			y := f32(BOARD_Y + row * game.TILE)
			blit(i32((row + col) % 2 == 0 ? game.Sprite.Cell_A : game.Sprite.Cell_B), x, y, 1)
			c := play.board.cells[row][col]
			if c.occupied {
				draw_atom(c.kind, c.bonds, x, y, 1)
			}
		}
	}
	kind, have := game.in_hand(&play)
	if have && hover_set && play.phase == .Playing {
		x := f32(BOARD_X + hover_col * game.TILE)
		y := f32(BOARD_Y + hover_row * game.TILE)
		if game.valid_placement(&play.board, hover_row, hover_col, kind, play.rot) {
			draw_atom(kind, game.bonds_of(kind, play.rot), x, y, 0.65)
			blit(i32(game.Sprite.Frame), x, y, 1)
		} else if !play.board.cells[hover_row][hover_col].occupied {
			draw_atom(kind, game.bonds_of(kind, play.rot), x, y, 0.22)
		}
	}
}

draw_panel :: proc() {
	x := f32(PANEL_X)
	draw_text(x, 10, "ENDLESS", DIM, 1)
	draw_text(x, 26, "SCORE", DIM, 1)
	buf: [16]u8
	draw_text(x, 38, fmt.bprintf(buf[:], "%d", play.score), INK, 2)

	draw_text(x, 62, play.supply.view == .Tray ? "TRAY" : "NEXT", DIM, 1)
	for kind, i in game.supply_visible(&play.supply) {
		r := slot_rect(i)
		blit(i32(game.Sprite.Cell_A), r.x, r.y, 1)
		selected := i == play.selected
		bonds := game.bonds_of(kind, selected ? play.rot : 0)
		faded := play.supply.view == .Queue && i > 0
		draw_atom(kind, bonds, r.x, r.y, faded ? 0.5 : 1)
		if selected {
			blit(i32(game.Sprite.Frame), r.x, r.y, 1)
		}
	}

	draw_button(rotate_button, "ROTATE (R)", play.phase == .Playing)
	draw_button(menu_button, "MENU (ESC)")
	if msg != "" {
		draw_text(x, 256, msg, msg_color, 1)
	}
	turns: [24]u8
	draw_text(x, 276, fmt.bprintf(turns[:], "TURN %d", play.turns), DIM, 1)
}

draw_play :: proc() {
	draw_board()
	draw_panel()
	if play.phase != .Playing {
		fill_rect(BOARD_X, BOARD_Y, BOARD_PX, BOARD_PX, BACK, 0.88)
		cx := f32(BOARD_X + BOARD_PX / 2)
		draw_centered(cx, 92, play.phase == .Out_Of_Moves ? "NO MOVES LEFT" : "ALL ATOMS USED", INK, 2)
		buf: [24]u8
		draw_centered(cx, 126, fmt.bprintf(buf[:], "SCORE %d", play.score), INK, 2)
		draw_centered(cx, 168, "Click or press Enter", DIM, 1)
		draw_centered(cx, 180, "to play again", DIM, 1)
	}
}
