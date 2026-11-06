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
	// Play sound number `sound` (game.Sound). The page unlocks audio on the first key or pointer press.
	play_sound :: proc(sound: i32) ---
	// localStorage. storage_get copies the value into buf and returns its byte length, or -1 when
	// there is none (or storage is unavailable) and -2 when it does not fit.
	storage_get :: proc(key: string, buf: [^]u8, cap: i32) -> i32 ---
	storage_set :: proc(key: string, value: string) ---
	// Online top scores (LootLocker, run by the page; endless mode only). scores_name gives the page the
	// player's name (it renames on the server); scores_refresh asks for the rows, which come back through
	// the scores_begin, scores_add and scores_status exports; scores_submit answers through scores_sent.
	scores_name :: proc(name: string) ---
	scores_refresh :: proc() ---
	scores_submit :: proc(score: i32) ---
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
	Select, // pick a level
	Play,
	Scores, // online top scores
	Name, // type the name shown on the scores
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
muted: bool
save: game.Save
new_best: bool // the run that just ended set a record

SAVE_KEY :: "chem-grid-save"
NAME_KEY :: "chem-grid-name" // the name on the online scores
ASKED_KEY :: "chem-grid-name-asked" // "1" once the name screen was skipped, "2" once a name was typed

board: game.Score_Board
board_scratch: [game.NAME_LEN]u8 // the page writes a row's name here before calling scores_add
player_name: game.Name_Edit // the name in use (never empty)
name_edit: game.Name_Edit // the name being typed on the Name screen
name_asked: bool
name_chosen: bool // the player typed the name in use (otherwise it is the random one)
name_back: Screen // where the Name screen returns to
scores_back: Screen // where the Scores screen returns to
pending_score: int // an endless score waiting for the Name screen before it is sent

main :: proc() {
	js.add_window_event_listener(.Key_Down, nil, on_key)
	load_save()
	load_name()
}

// The name and the asked flag live in their own keys, so the save line stays as it is.
load_name :: proc() {
	buf: [64]u8
	if n := storage_get(NAME_KEY, raw_data(buf[:]), i32(len(buf))); n > 0 {
		game.name_load(&player_name, string(buf[:n]))
	}
	if _, ok := game.name_finish(&player_name); !ok {
		game.name_load(&player_name, fmt.tprintf("CHEMIST-%d", 1000 + int(u64(time.now()._nsec) / 1_000_000 * 2654435761 % 9000)))
		storage_set(NAME_KEY, game.name_text(&player_name))
	}
	n := storage_get(ASKED_KEY, raw_data(buf[:]), i32(len(buf)))
	name_asked = n > 0
	name_chosen = n == 1 && buf[0] == '2'
	scores_name(game.name_text(&player_name))
}

// A save that fails to read or validate is ignored whole: defaults stay.
load_save :: proc() {
	buf: [game.SAVE_MAX_LEN]u8
	n := storage_get(SAVE_KEY, raw_data(buf[:]), i32(len(buf)))
	if n < 0 {
		return
	}
	if loaded, ok := game.save_decode(string(buf[:n])); ok {
		save = loaded
		muted = loaded.muted
	}
}

store_save :: proc() {
	save.muted = muted
	buf: [game.SAVE_MAX_LEN]u8
	storage_set(SAVE_KEY, game.save_encode(&save, buf[:]))
}

toggle_mute :: proc() {
	muted = !muted
	store_save()
}

new_seed :: proc() -> u64 {
	return u64(time.now()._nsec) | 1
}

begin :: proc() {
	screen = .Play
	hover_set = false
	new_best = false
	msg = ""
	board.submit = .None
	anim_on = false
}

open_scores :: proc(back: Screen) {
	scores_back = back
	screen = .Scores
	board.status = .Loading
	scores_refresh()
}

open_name :: proc(back: Screen) {
	name_edit = name_chosen ? player_name : {} // a random name is not worth editing
	name_back = back
	screen = .Name
}

// OK (accept) or Skip/Cancel on the Name screen. An empty name cannot be accepted. The first time, either
// answer counts as asked, and a score waiting for the name is sent.
close_name :: proc(accept: bool) {
	renamed := false
	if accept {
		name, ok := game.name_finish(&name_edit)
		if !ok {
			beep(.Invalid)
			return
		}
		if name != game.name_text(&player_name) {
			player_name = name_edit
			storage_set(NAME_KEY, game.name_text(&player_name))
			scores_name(game.name_text(&player_name))
			renamed = true
		}
	}
	if accept {
		name_chosen = true
	}
	if !name_asked || accept {
		name_asked = true
		storage_set(ASKED_KEY, name_chosen ? "2" : "1")
	}
	if name_back == .Scores {
		if renamed {
			open_scores(scores_back) // reload, which renames on the server first
		} else {
			screen = .Scores
		}
		return
	}
	screen = name_back
	if pending_score > 0 {
		score := pending_score
		pending_score = 0
		board.submit = .Sending
		scores_submit(i32(score))
	}
}

// An endless game ended: send its score, asking for a name first if that has never been done.
send_score :: proc(score: int) {
	board.submit = .None
	if score <= 0 {
		return
	}
	if !name_asked {
		pending_score = score
		open_name(.Play)
		return
	}
	board.submit = .Sending
	scores_submit(i32(score))
}

start_endless :: proc() {
	play = game.game_endless(new_seed())
	begin()
}

start_level :: proc(index: int) {
	if index >= 0 && index < len(game.LEVELS) {
		play = game.game_level(index, new_seed())
		begin()
	}
}

// Play the same mode again.
retry :: proc() {
	if play.has_goals {
		start_level(play.level)
	} else {
		start_endless()
	}
}

has_next_level :: proc() -> bool {
	return play.has_goals && play.level + 1 < len(game.LEVELS)
}

// The main button on the end-of-game overlay: next level after a win, otherwise try again.
overlay_primary :: proc() {
	if play.phase == .Won && has_next_level() {
		start_level(play.level + 1)
	} else {
		retry()
	}
}

// Back out of a game to where it was started from.
leave :: proc() {
	screen = play.has_goals ? .Select : .Title
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
rotate_button := Rect{BUTTON_X, 190, BUTTON_W, 20}
menu_button := Rect{BUTTON_X, 214, BUTTON_W, 20}
sound_button := Rect{BUTTON_X, 238, BUTTON_W, 20}
endless_button := Rect{140, 136, 120, 26}
levels_button := Rect{140, 170, 120, 26}
scores_button := Rect{140, 204, 120, 26}
back_button := Rect{12, 270, 100, 22}
change_name_button := Rect{140, 270, 120, 22}
overlay_primary_button := Rect{BOARD_X + BOARD_PX / 2 - 70, 176, 140, 22}
overlay_secondary_button := Rect{BOARD_X + BOARD_PX / 2 - 70, 204, 140, 22}
overlay_scores_button := Rect{BOARD_X + BOARD_PX / 2 - 70, 232, 140, 22} // endless only
name_ok_button := Rect{80, 236, 110, 24}
name_skip_button := Rect{210, 236, 110, 24}

// The on-screen keys of the Name screen; a last key, DEL, follows them. A variable, so it can be indexed.
name_keys := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- "
KEY_COLS :: 10

key_rect :: proc(i: int) -> Rect {
	return {f32(30 + (i % KEY_COLS) * 34), f32(96 + (i / KEY_COLS) * 30), 32, 26}
}

// press_key types on-screen key i (the last one is DEL).
press_key :: proc(i: int) {
	if i == len(name_keys) {
		game.name_backspace(&name_edit)
	} else if !game.name_type(&name_edit, name_keys[i]) {
		beep(.Invalid)
	}
}

LEVEL_ROWS :: 10 // levels per column on the select screen

level_button :: proc(i: int) -> Rect {
	return {f32(12 + (i / LEVEL_ROWS) * 196), f32(44 + (i % LEVEL_ROWS) * 22), 184, 20}
}

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

beep :: proc(sound: game.Sound) {
	if !muted {
		play_sound(i32(sound))
	}
}

// Messages and sounds for what the last step did.
take_events :: proc() {
	placed, completed, over := false, false, false
	for e in game.events(&play) {
		#partial switch e.kind {
		case .Placed:
			placed = true
		case .Rotated:
			beep(.Rotate)
		case .Invalid:
			set_message(ACCENT, "NO ROOM THERE")
			beep(.Invalid)
		case .Completed:
			completed = true
			name := game.MOLECULE_DEFS[e.id].name
			if e.id == .None { name = "MOLECULE" }
			set_message(GOOD, "%s +%d", name, e.score)
			beep(game.completion_sound(e.id, e.atoms))
		case .Game_Over, .Supply_Empty:
			over = true
			if !play.has_goals {
				new_best = game.record_endless(&save, play.score)
				store_save()
				send_score(play.score)
			}
		case .He_Drifted:
			if e.atoms > 0 {
				set_message(GOOD, "HELIUM ESCAPED")
			}
		case .He_Added:
			set_message(ACCENT, "HELIUM NEXT")
			beep(.Invalid)
		case .Tray_Grew:
			set_message(GOOD, "NEW TRAY SLOT")
			beep(.Win)
		case .Won:
			beep(.Win)
			new_best = game.record_level(&save, play.level, play.score)
			store_save()
		}
	}
	if placed && !completed {
		beep(.Place)
	}
	if over {
		beep(.Game_Over)
	}
}

do_place :: proc(row, col: int) {
	game.step(&play, game.Place{row, col})
	take_events()
	start_anim()
}

// ---- the animation of the last placement: the closed molecule fades out while the helium rises ----
// The board is already in its new state; this only changes how it is drawn for a moment. The next
// placement starts a new animation, so input is never held up.

FADE_TIME :: f32(0.35) // the closed molecule fades out
RISE_START :: f32(0.15) // the helium starts rising while the molecule is still fading
RISE_PER_CELL :: f32(0.07) // seconds per square risen

anim_on: bool
anim_t: f32
anim_fade: game.Molecule
anim_rises: game.He_Rises

start_anim :: proc() {
	anim_fade = play.cleared
	anim_rises = play.rises
	anim_t = 0
	anim_on = anim_fade.count > 0 || anim_rises.count > 0
}

// Rows an animated helium travels: to row -1 (just above the board) when it escapes.
rise_rows :: proc(r: game.He_Rise) -> f32 {
	return f32(r.from_row - r.to_row)
}

anim_length :: proc() -> f32 {
	length := anim_fade.count > 0 ? FADE_TIME : 0
	for r in anim_rises.items[:anim_rises.count] {
		length = max(length, RISE_START + rise_rows(r) * RISE_PER_CELL)
	}
	return length
}

advance_anim :: proc(dt: f32) {
	if anim_on {
		anim_t += dt
		if anim_t >= anim_length() {
			anim_on = false
		}
	}
}

// Where a rising helium is drawn now (in rows; -1 is one row above the board) and how opaque it is: it
// slows as it arrives, and one leaving the board fades as it goes past the top edge.
rise_at :: proc(r: game.He_Rise) -> (row, alpha: f32) {
	p := clamp((anim_t - RISE_START) / (rise_rows(r) * RISE_PER_CELL), 0, 1)
	eased := 1 - (1 - p) * (1 - p)
	row = f32(r.from_row) - rise_rows(r) * eased
	return row, clamp(1 + row, 0, 1)
}

// Whether a cell's atom is a helium still on its way there (drawn by draw_anim, not in its cell).
arriving :: proc(row, col: int) -> bool {
	if !anim_on { return false }
	for r in anim_rises.items[:anim_rises.count] {
		if r.to_row == row && r.col == col { return true }
	}
	return false
}

draw_anim :: proc() {
	if !anim_on { return }
	if fade := 1 - anim_t / FADE_TIME; fade > 0 {
		for i in 0 ..< anim_fade.count {
			p := anim_fade.cells[i]
			draw_atom(anim_fade.kinds[i], anim_fade.sides[i], f32(BOARD_X + int(p.col) * game.TILE), f32(BOARD_Y + int(p.row) * game.TILE), fade)
		}
	}
	for r in anim_rises.items[:anim_rises.count] {
		row, alpha := rise_at(r)
		if alpha > 0 {
			draw_atom(.He, {}, f32(BOARD_X + r.col * game.TILE), BOARD_Y + row * game.TILE, alpha)
		}
	}
}

do_rotate :: proc(turns: int) {
	if screen == .Play && play.phase == .Playing {
		game.step(&play, game.Rotate{turns})
		take_events()
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
	case .Name:
		switch code {
		case "Enter", "NumpadEnter": close_name(true)
		case "Escape": close_name(false)
		case "Backspace": game.name_backspace(&name_edit)
		case:
			k := e.key.key
			if len(k) == 1 && !e.key.ctrl && !e.key.meta && !e.key.alt {
				if !game.name_type(&name_edit, k[0]) {
					beep(.Invalid)
				}
			} else {
				handled = false
			}
		}
	case .Scores:
		switch code {
		case "Escape": screen = scores_back
		case "KeyN": open_name(.Scores)
		case "KeyM": toggle_mute()
		case: handled = false
		}
	case .Title:
		switch code {
		case "Enter", "Space": start_endless()
		case "KeyT": open_scores(.Title)
		case "KeyL": screen = .Select
		case "KeyM": toggle_mute()
		case: handled = false
		}
	case .Select:
		switch code {
		case "Escape": screen = .Title
		case "KeyM": toggle_mute()
		case:
			if len(code) == 6 && code[:5] == "Digit" && code[5] >= '1' && code[5] <= '9' {
				start_level(int(code[5] - '1'))
			} else {
				handled = false
			}
		}
	case .Play:
		if play.phase != .Playing {
			switch code {
			case "Enter", "Space": overlay_primary()
			case "Escape": leave()
			case "KeyM": toggle_mute()
			case "KeyT":
				if !play.has_goals {
					open_scores(.Play)
				} else {
					handled = false
				}
			case: handled = false
			}
			break
		}
		switch code {
		case "KeyR", "KeyE", "Space", "ArrowUp", "ArrowRight": do_rotate(1)
		case "KeyQ", "ArrowLeft", "ArrowDown": do_rotate(-1)
		case "Escape": leave()
		case "KeyM": toggle_mute()
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
	case .Name:
		for i in 0 ..= len(name_keys) {
			if in_rect(key_rect(i), x, y) {
				press_key(i)
			}
		}
		if in_rect(name_ok_button, x, y) {
			close_name(true)
		} else if in_rect(name_skip_button, x, y) {
			close_name(false)
		}
	case .Scores:
		if in_rect(back_button, x, y) {
			screen = scores_back
		} else if in_rect(change_name_button, x, y) {
			open_name(.Scores)
		}
	case .Title:
		if in_rect(endless_button, x, y) {
			start_endless()
		} else if in_rect(levels_button, x, y) {
			screen = .Select
		} else if in_rect(scores_button, x, y) {
			open_scores(.Title)
		}
	case .Select:
		if in_rect(back_button, x, y) {
			screen = .Title
		}
		for i in 0 ..< len(game.LEVELS) {
			if in_rect(level_button(i), x, y) {
				start_level(i)
				return
			}
		}
	case .Play:
		if play.phase != .Playing {
			if in_rect(overlay_primary_button, x, y) {
				overlay_primary()
			} else if in_rect(overlay_secondary_button, x, y) {
				leave()
			} else if !play.has_goals && in_rect(overlay_scores_button, x, y) {
				open_scores(.Play)
			}
			return
		}
		if in_rect(rotate_button, x, y) {
			do_rotate(1)
		} else if in_rect(menu_button, x, y) {
			leave()
		} else if in_rect(sound_button, x, y) {
			toggle_mute()
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

// QA hook for scripted play: 0 not in a game, then 1 playing, 2 no moves left, 3 out of atoms, 4 won.
@(export)
qa_phase :: proc "c" () -> i32 {
	if screen != .Play { return 0 }
	return 1 + i32(play.phase)
}

// QA hook: -1 when no animation is playing, else 100 times the rising helium plus the fading atoms.
@(export)
qa_anim :: proc "c" () -> i32 {
	return anim_on ? i32(anim_rises.count * 100 + anim_fade.count) : -1
}

// QA hook: start level `index`, or endless mode when index is negative.
@(export)
qa_start :: proc "c" (index: i32) {
	context = runtime.default_context()
	if index < 0 {
		start_endless()
	} else {
		start_level(int(index))
	}
}

// ---- online scores, answered by the page ----

// The page writes a row's name (printable ASCII, at most NAME_LEN bytes) here before scores_add.
@(export)
scores_scratch :: proc "c" () -> rawptr {
	return &board_scratch
}

// scores_begin clears the rows; the page then calls scores_add for each, then scores_status.
@(export)
scores_begin :: proc "c" () {
	context = runtime.default_context()
	game.scores_begin(&board)
}

@(export)
scores_add :: proc "c" (score, n: i32) {
	context = runtime.default_context()
	game.scores_add(&board, board_scratch[:clamp(int(n), 0, len(board_scratch))], int(score))
}

// s is a game.Board_Status: 2 Ready after the rows, 3 Failed when the request did not work.
@(export)
scores_status :: proc "c" (s: i32) {
	if s >= 0 && s <= i32(max(game.Board_Status)) {
		board.status = game.Board_Status(s)
	}
}

// The answer to scores_submit: ok is 1 when the score was taken.
@(export)
scores_sent :: proc "c" (ok: i32) {
	if board.submit == .Sending {
		board.submit = ok != 0 ? .Sent : .Failed
	}
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
	advance_anim(f32(dt))
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
	case .Title:  draw_title()
	case .Select: draw_select()
	case .Play:   draw_play()
	case .Scores: draw_scores()
	case .Name:   draw_name()
	}
}

draw_scores :: proc() {
	draw_centered(200, 10, "TOP SCORES", INK, 2)
	draw_centered(200, 30, "Endless mode, online", DIM, 1)
	me := game.name_text(&player_name)
	switch board.status {
	case .Idle, .Loading:
		draw_centered(200, 120, "LOADING...", DIM, 1)
	case .Failed:
		draw_centered(200, 114, "COULD NOT REACH THE SCORES", ACCENT, 1)
		draw_centered(200, 128, "Offline? The game plays on without them.", DIM, 1)
	case .Ready:
		if board.count == 0 {
			draw_centered(200, 120, "NO SCORES YET. BE THE FIRST!", DIM, 1)
		}
		for i in 0 ..< board.count {
			e := &board.rows[i]
			y := f32(48 + i * 18)
			color: u32 = game.entry_name(e) == me ? GOOD : INK
			rank := fmt.tprintf("%d.", i + 1)
			draw_text(110 - text_w(rank, 1), y, rank, DIM, 1)
			draw_text(118, y, game.entry_name(e), color, 1)
			score := fmt.tprintf("%d", e.score)
			draw_text(290 - text_w(score, 1), y, score, color, 1)
		}
	}
	draw_centered(200, 240, fmt.tprintf("You: %s", me), INK, 1)
	draw_button(back_button, "BACK (ESC)")
	draw_button(change_name_button, "CHANGE NAME (N)")
}

draw_name :: proc() {
	draw_centered(200, 14, "YOUR NAME", INK, 2)
	note := "Shown on the online top scores."
	if pending_score > 0 {
		note = fmt.tprintf("Your score of %d goes on the online top scores.", pending_score)
	}
	draw_centered(200, 38, note, DIM, 1)
	fill_rect(98, 56, 204, 28, INK, 1)
	fill_rect(99, 57, 202, 26, BACK, 1)
	draw_text(104, 62, game.name_text(&name_edit), INK, 2)
	if name_edit.len < game.NAME_LEN {
		fill_rect(f32(104 + name_edit.len * 12), 77, 10, 2, ACCENT, 1)
	}
	for i in 0 ..= len(name_keys) {
		label := "DEL"
		if i < len(name_keys) {
			label = name_keys[i] == ' ' ? "SPC" : name_keys[i:i + 1]
		}
		draw_button(key_rect(i), label)
	}
	draw_button(name_ok_button, "OK (ENTER)", name_edit.len > 0)
	draw_button(name_skip_button, name_asked ? "CANCEL (ESC)" : "SKIP (ESC)")
}

draw_title :: proc() {
	draw_centered(200, 44, "CHEM-GRID", INK, 4)
	draw_centered(200, 92, "Place atoms. Match every bond.", DIM, 1)
	draw_centered(200, 104, "Close a molecule and it scores.", DIM, 1)
	draw_button(endless_button, "ENDLESS")
	draw_button(levels_button, "LEVELS (L)")
	draw_button(scores_button, "TOP SCORES (T)")
	if save.endless_best > 0 {
		draw_centered(200, 238, fmt.tprintf("Best endless score: %d", save.endless_best), DIM, 1)
	}
	draw_centered(200, 254, "Mouse: click to place, R or wheel to rotate", DIM, 1)
	draw_centered(200, 266, "Touch: tap a cell, tap it again to place", DIM, 1)
	draw_centered(200, 284, "Font DINOBYTE by mby, CC BY 4.0", DIM, 1)
}

draw_select :: proc() {
	draw_centered(200, 16, "LEVELS", INK, 2)
	for l, i in game.LEVELS {
		r := level_button(i)
		draw_button(r, "")
		draw_text(r.x + 6, r.y + 6, fmt.tprintf("%d %s", i + 1, l.name), INK, 1)
		if save.cleared[i] {
			best := fmt.tprintf("%d", save.best[i])
			draw_text(r.x + r.w - 6 - text_w(best, 1), r.y + 6, best, GOOD, 1)
		}
	}
	draw_button(back_button, "BACK (ESC)")
}

// Can the atom in hand go in this empty cell?
Hint :: enum {
	Blocked, // at no rotation
	Rotate,  // only after rotating it
	Ready,   // at the current rotation
}

HINT_TINT := [Hint]u32{.Blocked = 0xd62828, .Rotate = 0xf2b705, .Ready = 0x2e9e4f}
HINT_ICON := [Hint]u32{.Blocked = 0x7a1414, .Rotate = 0x7a5a00, .Ready = 0x145a2c}

// 7 by 7 pixel icons so the hint does not rely on colour alone: x, ?, and a check mark.
HINT_BITMAPS := [Hint][7]string {
	.Blocked = {"X.....X", ".X...X.", "..X.X..", "...X...", "..X.X..", ".X...X.", "X.....X"},
	.Rotate  = {".XXXXX.", "X.....X", "......X", "....XX.", "...X...", ".......", "...X..."},
	.Ready   = {".......", "......X", ".....XX", "X...XX.", "XX.XX..", ".XXX...", "..X...."},
}

cell_hint :: proc(kind: game.Kind, row, col: int) -> Hint {
	if game.valid_placement(&play.board, row, col, kind, play.rot) {
		return .Ready
	}
	for rot in 0 ..< game.rotation_count(kind) {
		if game.valid_placement(&play.board, row, col, kind, rot) {
			return .Rotate
		}
	}
	return .Blocked
}

draw_hint :: proc(h: Hint, x, y: f32) {
	fill_rect(x + 1, y + 1, game.TILE - 2, game.TILE - 2, HINT_TINT[h], 0.3)
	// Icon at 2x, centred, drawn as horizontal runs.
	ox := x + (game.TILE - 14) / 2
	oy := y + (game.TILE - 14) / 2
	for row, ry in HINT_BITMAPS[h] {
		start := -1
		for cx in 0 ..= len(row) {
			on := cx < len(row) && row[cx] == 'X'
			if on && start < 0 {
				start = cx
			} else if !on && start >= 0 {
				fill_rect(ox + f32(start * 2), oy + f32(ry * 2), f32((cx - start) * 2), 2, HINT_ICON[h], 0.6)
				start = -1
			}
		}
	}
}

draw_board :: proc() {
	for row in 0 ..< game.BOARD_SIZE {
		for col in 0 ..< game.BOARD_SIZE {
			x := f32(BOARD_X + col * game.TILE)
			y := f32(BOARD_Y + row * game.TILE)
			blit(i32((row + col) % 2 == 0 ? game.Sprite.Cell_A : game.Sprite.Cell_B), x, y, 1)
			c := play.board.cells[row][col]
			if c.occupied && !arriving(row, col) {
				draw_atom(c.kind, c.bonds, x, y, 1)
			}
		}
	}
	kind, have := game.in_hand(&play)
	if have && play.phase == .Playing {
		for row in 0 ..< game.BOARD_SIZE {
			for col in 0 ..< game.BOARD_SIZE {
				if !play.board.cells[row][col].occupied {
					draw_hint(cell_hint(kind, row, col), f32(BOARD_X + col * game.TILE), f32(BOARD_Y + row * game.TILE))
				}
			}
		}
	}
	draw_anim()
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
	draw_text(x, 10, play.has_goals ? game.LEVELS[play.level].name : fmt.tprintf("ENDLESS BEST %d", save.endless_best), DIM, 1)
	draw_text(x, 26, "SCORE", DIM, 1)
	buf: [16]u8
	draw_text(x, 38, fmt.bprintf(buf[:], "%d", play.score), INK, 2)

	draw_text(x, 62, play.supply.view == .Tray ? "TRAY" : "NEXT", DIM, 1)
	for kind, i in game.supply_visible(&play.supply) {
		r := slot_rect(i)
		blit(i32(game.Sprite.Cell_A), r.x, r.y, 1)
		selected := i == play.selected
		bonds := game.bonds_of(kind, selected ? play.rot : 0)
		faded := (play.supply.view == .Queue && i > 0) || !game.can_take(&play, i)
		draw_atom(kind, bonds, r.x, r.y, faded ? 0.5 : 1)
		if selected {
			blit(i32(game.Sprite.Frame), r.x, r.y, 1)
		}
	}

	if play.has_goals {
		draw_goals(x, 146)
	} else if play.phase == .Playing {
		// Endless: how many placements until a helium becomes the next piece (red when close).
		soon := play.moves_to_he <= 2
		draw_text(x, 148, fmt.tprintf("HELIUM IN %d", play.moves_to_he), soon ? ACCENT : INK, 1)
	}
	draw_button(rotate_button, "ROTATE (R)", play.phase == .Playing)
	draw_button(menu_button, play.has_goals ? "LEVELS (ESC)" : "MENU (ESC)")
	draw_button(sound_button, muted ? "SOUND OFF (M)" : "SOUND ON (M)")
	if msg != "" {
		draw_text(x, 264, msg, msg_color, 1)
	}
	turns: [24]u8
	draw_text(x, 280, fmt.bprintf(turns[:], "TURN %d", play.turns), DIM, 1)
}

// What the level asks for, one line each, green once met.
draw_goals :: proc(x, y: f32) {
	gl := play.goals
	y := y
	put :: proc(x, y: f32, met: bool, text: string) {
		draw_text(x, y, text, met ? GOOD : INK, 1)
	}
	if gl.min_score > 0 {
		put(x, y, play.score >= gl.min_score, fmt.tprintf("SCORE %d/%d", play.score, gl.min_score))
		y += 9
	}
	for id in game.Molecule_Id {
		need := gl.molecules[id]
		if need == 0 { continue }
		have := id == .None ? game.molecules_made(&play) : play.made[id]
		name := id == .None ? "MOLECULES" : game.MOLECULE_DEFS[id].name
		put(x, y, have >= need, fmt.tprintf("%s %d/%d", name, have, need))
		y += 9
	}
	finished := game.supply_empty(&play.supply)
	if gl.use_whole_bag {
		put(x, y, finished, fmt.tprintf("BAG LEFT %d", game.supply_remaining(&play.supply)))
		y += 9
	}
	if limit, ok := gl.max_leftover.?; ok {
		atoms := game.atoms_on_board(&play)
		put(x, y, finished && atoms <= limit, fmt.tprintf("MAX LEFT %d (NOW %d)", limit, atoms))
	}
}

draw_play :: proc() {
	draw_board()
	draw_panel()
	if play.phase != .Playing {
		fill_rect(BOARD_X, BOARD_Y, BOARD_PX, BOARD_PX, BACK, 0.9)
		cx := f32(BOARD_X + BOARD_PX / 2)
		title, note: string
		color: u32 = INK
		switch play.phase {
		case .Won:
			title, note, color = "LEVEL CLEAR!", "All goals met.", GOOD
		case .Out_Of_Moves:
			title, note = "NO MOVES LEFT", "Nothing in hand fits."
		case .Out_Of_Atoms:
			title, note = play.has_goals ? "GOALS MISSED" : "ALL ATOMS USED", "No atoms left."
		case .Playing:
		}
		draw_centered(cx, 70, title, color, 2)
		draw_centered(cx, 100, fmt.tprintf("SCORE %d", play.score), INK, 2)
		draw_centered(cx, 132, note, DIM, 1)
		if new_best {
			draw_centered(cx, 148, "NEW BEST!", GOOD, 1)
		}
		#partial switch board.submit {
		case .Sending: draw_centered(cx, 160, "SENDING SCORE...", DIM, 1)
		case .Sent:    draw_centered(cx, 160, "SCORE SENT ONLINE", GOOD, 1)
		case .Failed:  draw_centered(cx, 160, "COULD NOT SEND SCORE", ACCENT, 1)
		}
		if !play.has_goals {
			draw_button(overlay_scores_button, "TOP SCORES (T)")
		}
		primary := "PLAY AGAIN"
		if play.has_goals {
			primary = play.phase == .Won && has_next_level() ? "NEXT LEVEL" : "RETRY"
		}
		draw_button(overlay_primary_button, primary)
		draw_button(overlay_secondary_button, play.has_goals ? "LEVELS (ESC)" : "MENU (ESC)")
	}
}
