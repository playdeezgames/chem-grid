// Online top scores (LootLocker, endless mode only). The page fetches and sends; this file only holds
// the rows it hands over and the rules for the name a player types.
package game

BOARD_ROWS :: 10
NAME_LEN :: 16

Board_Status :: enum u8 {
	Idle, // nothing asked for yet
	Loading,
	Ready,
	Failed, // offline or the service said no; the game plays on regardless
}

// What happened to the score of the endless game that just ended.
Submit_Status :: enum u8 {
	None, // nothing to send (a level game, or a score of 0)
	Sending,
	Sent,
	Failed,
}

Board_Entry :: struct {
	name:     [NAME_LEN]u8,
	name_len: int,
	score:    int,
}

Score_Board :: struct {
	status: Board_Status,
	rows:   [BOARD_ROWS]Board_Entry,
	count:  int,
	submit: Submit_Status,
}

entry_name :: proc(e: ^Board_Entry) -> string {
	return string(e.name[:e.name_len])
}

// set_entry copies text into an entry, keeping printable ASCII (anything else becomes ?) and cutting it
// to NAME_LEN. Names on the board come from other players, so nothing about them is trusted.
set_entry :: proc(e: ^Board_Entry, name: []u8, score: int) {
	e.name_len = 0
	for c in name {
		if e.name_len >= NAME_LEN {
			break
		}
		e.name[e.name_len] = c >= 32 && c <= 126 ? c : '?'
		e.name_len += 1
	}
	e.score = max(score, 0)
}

scores_begin :: proc(b: ^Score_Board) {
	b.count = 0
}

scores_add :: proc(b: ^Score_Board, name: []u8, score: int) {
	if b.count >= BOARD_ROWS {
		return
	}
	set_entry(&b.rows[b.count], name, score)
	b.count += 1
}

// A name being typed. Letters are kept upper case (the on-screen keys are), plus digits, '-' and single
// spaces between words.
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
