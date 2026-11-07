#+build !js
package lootlocker

import "core:testing"

@(test)
board_rows_are_capped_and_names_cleaned :: proc(t: ^testing.T) {
	b: Board
	for i in 0 ..< ROWS + 3 {
		board_add(&b, transmute([]u8)string("A very long player name\xff"), i)
	}
	testing.expect_value(t, b.count, ROWS)
	testing.expect_value(t, b.rows[0].name_len, NAME_LEN)
	testing.expect_value(t, entry_name(&b.rows[0]), "A very long play")
	board_clear(&b)
	testing.expect_value(t, b.count, 0)
	board_add(&b, {'o', 0xe9, 'k', '\n'}, -5)
	testing.expect_value(t, entry_name(&b.rows[0]), "o?k?")
	testing.expect_value(t, b.rows[0].score, 0)
}

@(test)
typing_keeps_upper_case_digits_dash_and_single_spaces :: proc(t: ^testing.T) {
	e: Name_Edit
	testing.expect(t, !name_type(&e, ' ')) // no leading space
	for c in transmute([]u8)string("dr  Who_-9!") {
		name_type(&e, c)
	}
	testing.expect_value(t, name_text(&e), "DR WHO-9")
	testing.expect(t, name_backspace(&e))
	testing.expect_value(t, name_text(&e), "DR WHO-")
}

@(test)
typing_stops_at_name_len :: proc(t: ^testing.T) {
	e: Name_Edit
	for _ in 0 ..< NAME_LEN + 4 {
		name_type(&e, 'x')
	}
	testing.expect_value(t, e.len, NAME_LEN)
	testing.expect(t, !name_type(&e, 'y'))
}

@(test)
finish_trims_and_refuses_empty :: proc(t: ^testing.T) {
	e: Name_Edit
	_, ok := name_finish(&e)
	testing.expect(t, !ok)
	name_load(&e, "  ab cd  ")
	name, ok2 := name_finish(&e)
	testing.expect(t, ok2)
	testing.expect_value(t, name, "AB CD")
	testing.expect(t, !name_backspace(&Name_Edit{}))
}

@(test)
load_drops_what_typing_could_not_make :: proc(t: ^testing.T) {
	e: Name_Edit
	name_load(&e, "Chemist-1234\x00é")
	testing.expect_value(t, name_text(&e), "CHEMIST-1234")
}

@(test)
mine_flag_is_kept :: proc(t: ^testing.T) {
	b: Board
	board_add(&b, transmute([]u8)string("ME"), 10, true)
	board_add(&b, transmute([]u8)string("YOU"), 5)
	testing.expect(t, b.rows[0].mine)
	testing.expect(t, !b.rows[1].mine)
}

@(test)
native_calls_fail_quietly :: proc(t: ^testing.T) {
	refresh("any")
	testing.expect_value(t, board.status, Board_Status.Failed)
	submit("any", 5)
	testing.expect_value(t, board.submit, Submit_Status.Failed)
}
