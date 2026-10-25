package game

import "core:fmt"
import "core:strconv"
import "core:strings"

// What the browser remembers between visits: the mute setting, the endless high score, and for each
// level whether it has been cleared and the best score of a winning run.
//
// Stored as one line of text, for example  "CG1 m=0 e=1200 l=180,-,-,250"  where l= lists levels in
// order ("-" is not cleared, a number is the best winning score). Levels past the end of the list are
// not cleared, so adding levels never invalidates a save. Loading is strict: anything that does not
// parse or is out of range is refused whole, and the caller keeps its defaults.

MAX_SAVED_LEVELS :: 64
MAX_SAVED_SCORE :: 999_999_999
SAVE_MAGIC :: "CG1"
SAVE_MAX_LEN :: 8 + 2 + 12 + 3 + MAX_SAVED_LEVELS * 11 // generous upper bound for the encoded text

Save :: struct {
	muted:        bool,
	endless_best: int,
	cleared:      [MAX_SAVED_LEVELS]bool,
	best:         [MAX_SAVED_LEVELS]int, // meaningful only when cleared
}

// Encode into buf (use SAVE_MAX_LEN bytes); returns the text, a slice of buf.
save_encode :: proc(s: ^Save, buf: []u8) -> string {
	last := -1 // keep the list short: stop after the last cleared level
	for i in 0 ..< MAX_SAVED_LEVELS {
		if s.cleared[i] { last = i }
	}
	b := strings.builder_from_bytes(buf)
	fmt.sbprintf(&b, "%s m=%d e=%d l=", SAVE_MAGIC, s.muted ? 1 : 0, s.endless_best)
	for i in 0 ..= last {
		if i > 0 { strings.write_byte(&b, ',') }
		if s.cleared[i] {
			fmt.sbprintf(&b, "%d", s.best[i])
		} else {
			strings.write_byte(&b, '-')
		}
	}
	return strings.to_string(b)
}

@(private = "file")
parse_score :: proc(text: string) -> (int, bool) {
	if len(text) == 0 || len(text) > 9 {
		return 0, false
	}
	for c in transmute([]u8)text {
		if c < '0' || c > '9' { return 0, false }
	}
	n, ok := strconv.parse_int(text, 10)
	return n, ok && n >= 0 && n <= MAX_SAVED_SCORE
}

// Decode a save. ok is false for anything malformed; the Save is then all defaults.
save_decode :: proc(text: string) -> (s: Save, ok: bool) {
	rest := text
	magic, _ := strings.split_iterator(&rest, " ")
	m_tok, _ := strings.split_iterator(&rest, " ")
	e_tok, _ := strings.split_iterator(&rest, " ")
	l_tok, _ := strings.split_iterator(&rest, " ")
	if magic != SAVE_MAGIC || len(rest) != 0 {
		return {}, false
	}
	if !strings.has_prefix(m_tok, "m=") || !strings.has_prefix(e_tok, "e=") || !strings.has_prefix(l_tok, "l=") {
		return {}, false
	}
	switch m_tok[2:] {
	case "0": s.muted = false
	case "1": s.muted = true
	case: return {}, false
	}
	if s.endless_best, ok = parse_score(e_tok[2:]); !ok {
		return {}, false
	}
	list := l_tok[2:]
	if strings.has_suffix(list, ",") {
		return {}, false
	}
	i := 0
	for len(list) > 0 {
		if i >= MAX_SAVED_LEVELS {
			return {}, false
		}
		item, more := strings.split_iterator(&list, ",")
		if item == "-" {
			// not cleared
		} else if n, good := parse_score(item); good {
			s.cleared[i] = true
			s.best[i] = n
		} else {
			return {}, false
		}
		i += 1
		_ = more
	}
	return s, true
}

// A winning run on level i. Returns true when it is a new best (or the first clear).
record_level :: proc(s: ^Save, i, score: int) -> bool {
	if i < 0 || i >= MAX_SAVED_LEVELS {
		return false
	}
	capped := clamp(score, 0, MAX_SAVED_SCORE)
	if !s.cleared[i] || capped > s.best[i] {
		s.cleared[i] = true
		s.best[i] = capped
		return true
	}
	return false
}

// A finished endless run. Returns true for a new high score.
record_endless :: proc(s: ^Save, score: int) -> bool {
	capped := clamp(score, 0, MAX_SAVED_SCORE)
	if capped > s.endless_best {
		s.endless_best = capped
		return true
	}
	return false
}
