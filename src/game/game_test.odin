#+build !js
package game

import "core:testing"

@(test)
board_is_eight_by_eight :: proc(t: ^testing.T) {
	testing.expect_value(t, BOARD_SIZE, 8)
}
