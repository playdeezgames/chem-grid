#+build !js
package game

import "core:testing"

@(test)
round_trip_keeps_everything :: proc(t: ^testing.T) {
	s: Save
	s.muted = true
	s.endless_best = 1234
	s.cleared[0], s.best[0] = true, 180
	s.cleared[3], s.best[3] = true, 0
	s.cleared[MAX_SAVED_LEVELS - 1], s.best[MAX_SAVED_LEVELS - 1] = true, MAX_SAVED_SCORE
	buf: [SAVE_MAX_LEN]u8
	text := save_encode(&s, buf[:])
	got, ok := save_decode(text)
	testing.expectf(t, ok, "could not decode %q", text)
	testing.expect_value(t, got, s)
}

@(test)
encoding_is_short_and_readable :: proc(t: ^testing.T) {
	s: Save
	s.endless_best = 50
	s.cleared[1], s.best[1] = true, 7
	buf: [SAVE_MAX_LEN]u8
	testing.expect_value(t, save_encode(&s, buf[:]), "CG1 m=0 e=50 l=-,7")
	empty: Save
	testing.expect_value(t, save_encode(&empty, buf[:]), "CG1 m=0 e=0 l=")
	got, ok := save_decode("CG1 m=0 e=0 l=")
	testing.expect(t, ok)
	testing.expect_value(t, got, Save{})
}

@(test)
worst_case_fits_the_buffer :: proc(t: ^testing.T) {
	s := Save{muted = true, endless_best = MAX_SAVED_SCORE}
	for i in 0 ..< MAX_SAVED_LEVELS {
		s.cleared[i] = true
		s.best[i] = MAX_SAVED_SCORE
	}
	buf: [SAVE_MAX_LEN]u8
	text := save_encode(&s, buf[:])
	_, ok := save_decode(text)
	testing.expect(t, ok)
	testing.expect(t, len(text) <= SAVE_MAX_LEN)
}

@(test)
bad_saves_are_refused :: proc(t: ^testing.T) {
	bad := []string {
		"", "CG1", "CG1 m=0 e=0", "CG1 m=0 e=0 l= extra", "CG2 m=0 e=0 l=",
		"CG1 m=2 e=0 l=", "CG1 m=0 e=-1 l=", "CG1 m=0 e=1000000000 l=", "CG1 m=0 e=1.5 l=",
		"CG1 m=0 e=0 l=,", "CG1 m=0 e=0 l=1,,2", "CG1 m=0 e=0 l=x", "CG1 m=0 e=0 l=-1",
		"CG1 m=0 e=0 l=1,2,", "CG1  m=0 e=0 l=", "cg1 m=0 e=0 l=", " CG1 m=0 e=0 l=",
		"CG1 e=0 m=0 l=", "CG1 m=0 e=+5 l=", "CG1 m=0 e=0 l=99999999999999999999",
	}
	for text in bad {
		_, ok := save_decode(text)
		testing.expectf(t, !ok, "accepted %q", text)
	}
	// Too many levels.
	long := make([dynamic]u8)
	defer delete(long)
	append(&long, "CG1 m=0 e=0 l=")
	for i in 0 ..< MAX_SAVED_LEVELS + 1 {
		if i > 0 { append(&long, ',') }
		append(&long, '-')
	}
	_, ok := save_decode(string(long[:]))
	testing.expect(t, !ok)
}

@(test)
a_refused_save_gives_defaults :: proc(t: ^testing.T) {
	s, ok := save_decode("CG1 m=1 e=77 l=oops")
	testing.expect(t, !ok)
	testing.expect_value(t, s, Save{})
}

@(test)
levels_beyond_the_list_are_not_cleared :: proc(t: ^testing.T) {
	s, ok := save_decode("CG1 m=0 e=0 l=10,-,20")
	testing.expect(t, ok)
	testing.expect(t, s.cleared[0] && !s.cleared[1] && s.cleared[2] && !s.cleared[3])
	testing.expect_value(t, s.best[2], 20)
}

@(test)
records_keep_only_improvements :: proc(t: ^testing.T) {
	s: Save
	testing.expect(t, record_level(&s, 2, 100)) // first clear
	testing.expect(t, !record_level(&s, 2, 100))
	testing.expect(t, !record_level(&s, 2, 50))
	testing.expect(t, record_level(&s, 2, 101))
	testing.expect_value(t, s.best[2], 101)
	testing.expect(t, record_level(&s, 4, 0)) // a clear with no score still counts as cleared
	testing.expect(t, s.cleared[4])
	testing.expect(t, !record_level(&s, -1, 10))
	testing.expect(t, !record_level(&s, MAX_SAVED_LEVELS, 10))
	testing.expect(t, record_endless(&s, 300))
	testing.expect(t, !record_endless(&s, 300))
	testing.expect(t, record_endless(&s, 301))
	testing.expect_value(t, s.endless_best, 301)
	record_endless(&s, 5_000_000_000)
	testing.expect_value(t, s.endless_best, MAX_SAVED_SCORE)
}

// Random damage to a good save must never crash the loader, and whatever it accepts must be in range.
@(test)
fuzzed_saves_never_break_the_loader :: proc(t: ^testing.T) {
	s := Save{muted = true, endless_best = 4242}
	s.cleared[0], s.best[0] = true, 10
	s.cleared[2], s.best[2] = true, 999
	buf: [SAVE_MAX_LEN]u8
	good := save_encode(&s, buf[:])
	alphabet := "0123456789-,= mel CG1\x00\xff"
	state: u64 = 0x1234abcd5678
	accepted := 0
	for _ in 0 ..< 20000 {
		mutated: [SAVE_MAX_LEN]u8
		n := copy(mutated[:], good)
		for _ in 0 ..< 1 + int(xorshift(&state) % 4) {
			switch xorshift(&state) % 3 {
			case 0: mutated[xorshift(&state) % u64(n)] = alphabet[xorshift(&state) % u64(len(alphabet))]
			case 1: n = max(1, n - 1 - int(xorshift(&state) % 3))
			case 2:
				if n < len(mutated) - 1 {
					mutated[n] = alphabet[xorshift(&state) % u64(len(alphabet))]
					n += 1
				}
			}
		}
		got, ok := save_decode(string(mutated[:n]))
		if ok {
			accepted += 1
			testing.expect(t, got.endless_best >= 0 && got.endless_best <= MAX_SAVED_SCORE)
			for i in 0 ..< MAX_SAVED_LEVELS {
				testing.expect(t, got.best[i] >= 0 && got.best[i] <= MAX_SAVED_SCORE)
				testing.expect(t, got.cleared[i] || got.best[i] == 0)
			}
		} else {
			testing.expect_value(t, got, Save{})
		}
	}
	testing.expect(t, accepted > 0) // some mutations (a digit changed to another) stay valid
}
