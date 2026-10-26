#+build !js
package game

import "core:testing"

only :: proc(kinds: ..Kind) -> [Kind]int {
	w: [Kind]int
	for k in kinds {
		w[k] = 1
	}
	return w
}

@(test)
same_seed_gives_the_same_sequence :: proc(t: ^testing.T) {
	w := only(.H, .O_Bent, .N, .C, .He)
	a := supply_weighted(w, .Queue, 3, 1234)
	b := supply_weighted(w, .Queue, 3, 1234)
	c := supply_weighted(w, .Queue, 3, 4321)
	differs := false
	for _ in 0 ..< 50 {
		ka, _ := supply_take(&a, 0)
		kb, _ := supply_take(&b, 0)
		kc, _ := supply_take(&c, 0)
		testing.expect_value(t, ka, kb)
		differs ||= ka != kc
	}
	testing.expect(t, differs)
}

@(test)
zero_weight_never_appears_and_single_weight_always_does :: proc(t: ^testing.T) {
	s := supply_weighted(only(.H), .Queue, 2, 7)
	for _ in 0 ..< 100 {
		k, ok := supply_take(&s, 0)
		testing.expect(t, ok)
		testing.expect_value(t, k, Kind.H)
	}
	none: [Kind]int
	e := supply_weighted(none, .Queue, 2, 7)
	testing.expect(t, supply_empty(&e)) // nothing can be drawn
}

@(test)
weights_set_the_odds_roughly :: proc(t: ^testing.T) {
	w: [Kind]int
	w[.H] = 3
	w[.He] = 1
	s := supply_weighted(w, .Queue, 1, 99)
	he := 0
	for _ in 0 ..< 4000 {
		k, _ := supply_take(&s, 0)
		if k == .He { he += 1 }
	}
	testing.expectf(t, he > 800 && he < 1200, "He count %d, expected about 1000", he)
}

@(test)
queue_shows_preview_and_shifts_forward :: proc(t: ^testing.T) {
	order := []Kind{.H, .O_Bent, .N, .C, .He}
	s := supply_bag(order, false, .Queue, 3, 5)
	testing.expect_value(t, len(supply_visible(&s)), 3)
	testing.expect_value(t, supply_visible(&s)[0], Kind.H)
	testing.expect_value(t, supply_visible(&s)[2], Kind.N)
	testing.expect(t, !supply_can_take(&s, 1)) // only the front
	k, ok := supply_take(&s, 0)
	testing.expect(t, ok)
	testing.expect_value(t, k, Kind.H)
	testing.expect_value(t, supply_visible(&s)[0], Kind.O_Bent)
	testing.expect_value(t, supply_visible(&s)[2], Kind.C)
	_, ok = supply_take(&s, 2)
	testing.expect(t, !ok)
}

@(test)
bag_runs_out_exactly :: proc(t: ^testing.T) {
	order := []Kind{.H, .H, .O_Straight, .C}
	s := supply_bag(order, false, .Queue, 2, 5)
	testing.expect_value(t, supply_remaining(&s), 4)
	got: [dynamic]Kind
	defer delete(got)
	for !supply_empty(&s) {
		k, ok := supply_take(&s, 0)
		testing.expect(t, ok)
		append(&got, k)
	}
	testing.expect_value(t, len(got), 4)
	for k, i in order {
		testing.expect_value(t, got[i], k)
	}
	testing.expect_value(t, supply_remaining(&s), 0)
	_, ok := supply_take(&s, 0)
	testing.expect(t, !ok)
}

@(test)
shuffled_bag_keeps_the_same_atoms :: proc(t: ^testing.T) {
	order := []Kind{.H, .H, .H, .O_Straight, .O_Bent, .N, .C, .C, .He}
	s := supply_bag(order, true, .Queue, 1, 31337)
	counts: [Kind]int
	n := 0
	for !supply_empty(&s) {
		k, _ := supply_take(&s, 0)
		counts[k] += 1
		n += 1
	}
	want: [Kind]int
	for k in order { want[k] += 1 }
	testing.expect_value(t, n, len(order))
	testing.expect_value(t, counts, want)
}

@(test)
tray_lets_the_player_choose_and_refills_in_place :: proc(t: ^testing.T) {
	order := []Kind{.H, .O_Bent, .N, .C, .He}
	s := supply_bag(order, false, .Tray, 3, 5)
	testing.expect(t, supply_can_take(&s, 2))
	k, ok := supply_take(&s, 1) // O_Bent
	testing.expect(t, ok)
	testing.expect_value(t, k, Kind.O_Bent)
	// Slot 1 now holds the next atom from the bag; the others did not move.
	testing.expect_value(t, supply_visible(&s)[0], Kind.H)
	testing.expect_value(t, supply_visible(&s)[1], Kind.C)
	testing.expect_value(t, supply_visible(&s)[2], Kind.N)
}

@(test)
tray_shrinks_when_the_bag_is_dry :: proc(t: ^testing.T) {
	order := []Kind{.H, .O_Bent, .N}
	s := supply_bag(order, false, .Tray, 3, 5)
	testing.expect_value(t, supply_remaining(&s), 3)
	_, _ = supply_take(&s, 0)
	testing.expect_value(t, len(supply_visible(&s)), 2)
	testing.expect_value(t, supply_visible(&s)[0], Kind.O_Bent)
	_, _ = supply_take(&s, 1)
	_, _ = supply_take(&s, 0)
	testing.expect(t, supply_empty(&s))
}

@(test)
weights_can_be_changed_during_play :: proc(t: ^testing.T) {
	w := only(.H, .He)
	s := supply_weighted(w, .Queue, 1, 3)
	s.weights[.He] = 0
	_, _ = supply_take(&s, 0) // the atom already visible was drawn under the old weights
	for _ in 0 ..< 50 {
		k, _ := supply_take(&s, 0)
		testing.expect_value(t, k, Kind.H)
	}
}

@(test)
injected_atoms_come_out_next :: proc(t: ^testing.T) {
	s := supply_weighted(only(.H), .Tray, 3, 4)
	supply_inject(&s, .He, 2)
	_, _ = supply_take(&s, 1) // refills slot 1 with the first injected atom
	testing.expect_value(t, supply_visible(&s)[1], Kind.He)
	_, _ = supply_take(&s, 0) // and slot 0 with the second
	testing.expect_value(t, supply_visible(&s)[0], Kind.He)
	_, _ = supply_take(&s, 2) // then back to the source
	testing.expect_value(t, supply_visible(&s)[2], Kind.H)
}
