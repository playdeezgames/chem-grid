// SPLORR!! LootLocker package, version 1 (November 7, 2026). Source of truth: the bok-of-splorr vault,
// splorr/Tech/lootlocker/. Copy it into a game as src/lootlocker/ unchanged. How to use it: Tech/LootLocker.md.
//
// The page (lootlocker.js) does the network calls; this package holds one board's rows, the submit state
// and the rules for the name a player types. Pure apart from the `when ODIN_OS == .JS` block at the end,
// so its tests run natively.
package lootlocker

ROWS :: 10
NAME_LEN :: 16

Board_Status :: enum u8 {
	Idle, // nothing asked for yet
	Loading,
	Ready,
	Failed, // offline or the service said no; the game plays on regardless
}

Submit_Status :: enum u8 {
	None, // nothing sent
	Sending,
	Sent,
	Failed,
}

Entry :: struct {
	name:     [NAME_LEN]u8,
	name_len: int,
	score:    int,
	mine:     bool, // this player's own row
}

Board :: struct {
	status: Board_Status,
	rows:   [ROWS]Entry,
	count:  int,
	submit: Submit_Status,
}

// The one board the page fills in. A game shows one board at a time; refresh() reloads it for any key.
board: Board

entry_name :: proc(e: ^Entry) -> string {
	return string(e.name[:e.name_len])
}

// set_entry copies text into an entry, keeping printable ASCII (anything else becomes ?) and cutting it
// to NAME_LEN. Names on a board come from other players, so nothing about them is trusted.
set_entry :: proc(e: ^Entry, name: []u8, score: int, mine := false) {
	e.name_len = 0
	for c in name {
		if e.name_len >= NAME_LEN {
			break
		}
		e.name[e.name_len] = c >= 32 && c <= 126 ? c : '?'
		e.name_len += 1
	}
	e.score = max(score, 0)
	e.mine = mine
}

board_clear :: proc(b: ^Board) {
	b.count = 0
}

board_add :: proc(b: ^Board, name: []u8, score: int, mine := false) {
	if b.count >= ROWS {
		return
	}
	set_entry(&b.rows[b.count], name, score, mine)
	b.count += 1
}

// A name being typed. Letters are kept upper case, plus digits, '-' and single spaces between words.
Name_Edit :: struct {
	buf: [NAME_LEN]u8,
	len: int,
}

name_text :: proc(e: ^Name_Edit) -> string {
	return string(e.buf[:e.len])
}

// name_char maps a typed character to the one kept, or 0 when it is not allowed.
name_char :: proc(c: u8) -> u8 {
	switch c {
	case 'A' ..= 'Z', '0' ..= '9', '-', ' ':
		return c
	case 'a' ..= 'z':
		return c - 'a' + 'A'
	}
	return 0
}

// name_type adds one character; it reports whether the name changed. A space is refused at the start and
// after another space.
name_type :: proc(e: ^Name_Edit, c: u8) -> bool {
	k := name_char(c)
	if k == 0 || e.len >= NAME_LEN {
		return false
	}
	if k == ' ' && (e.len == 0 || e.buf[e.len - 1] == ' ') {
		return false
	}
	e.buf[e.len] = k
	e.len += 1
	return true
}

name_backspace :: proc(e: ^Name_Edit) -> bool {
	if e.len == 0 {
		return false
	}
	e.len -= 1
	return true
}

// name_load starts an edit from an existing name, dropping what typing could not have produced.
name_load :: proc(e: ^Name_Edit, text: string) {
	e.len = 0
	for i in 0 ..< len(text) {
		name_type(e, text[i])
	}
}

// name_finish drops trailing spaces and says whether anything is left to use.
name_finish :: proc(e: ^Name_Edit) -> (name: string, ok: bool) {
	for e.len > 0 && e.buf[e.len - 1] == ' ' {
		e.len -= 1
	}
	return name_text(e), e.len > 0
}

when ODIN_OS == .JS {
	foreign import ll "lootlocker"
	@(default_calling_convention = "contextless")
	foreign ll {
		@(link_name = "ll_name")
		_ll_name :: proc(name: string) ---
		@(link_name = "ll_refresh")
		_ll_refresh :: proc(board_key: string, count: i32) ---
		@(link_name = "ll_submit")
		_ll_submit :: proc(board_key: string, score: i32) ---
	}

	// set_name gives the page the player's name; it is renamed on the server with the next call.
	set_name :: proc(name: string) {
		_ll_name(name)
	}

	// refresh asks for the top rows of a board; board.status goes Loading, then Ready or Failed.
	refresh :: proc(board_key: string) {
		board.status = .Loading
		_ll_refresh(board_key, ROWS)
	}

	// submit sends a score; board.submit goes Sending, then Sent or Failed.
	submit :: proc(board_key: string, score: int) {
		board.submit = .Sending
		_ll_submit(board_key, i32(clamp(score, 0, int(max(i32)))))
	}

	@(private)
	scratch: [NAME_LEN]u8 // the page writes a row's name here before lootlocker_add

	@(export)
	lootlocker_scratch :: proc "contextless" () -> rawptr {
		return &scratch
	}

	@(export)
	lootlocker_begin :: proc "contextless" () {
		board.count = 0
	}

	@(export)
	lootlocker_add :: proc "contextless" (score, n, mine: i32) {
		if board.count >= ROWS {
			return
		}
		e := &board.rows[board.count]
		e.name_len = 0
		for c in scratch[:clamp(int(n), 0, NAME_LEN)] {
			e.name[e.name_len] = c >= 32 && c <= 126 ? c : '?'
			e.name_len += 1
		}
		e.score = max(int(score), 0)
		e.mine = mine != 0
		board.count += 1
	}

	// ok is 1 after the rows arrived, 0 when the request failed.
	@(export)
	lootlocker_status :: proc "contextless" (ok: i32) {
		board.status = ok != 0 ? .Ready : .Failed
	}

	// The answer to submit: ok is 1 when the score was taken.
	@(export)
	lootlocker_sent :: proc "contextless" (ok: i32) {
		if board.submit == .Sending {
			board.submit = ok != 0 ? .Sent : .Failed
		}
	}
} else {
	// Native builds (tests, an SDL client) have no service: everything fails quietly.
	set_name :: proc(name: string) {}
	refresh :: proc(board_key: string) {
		board.status = .Failed
	}
	submit :: proc(board_key: string, score: int) {
		board.submit = .Failed
	}
}
