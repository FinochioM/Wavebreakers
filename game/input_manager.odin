package main

import sapp "../sokol/app"
import slog "../sokol/log"
import "core:math/linalg"

Input_State_Flags :: enum {
	down,
	just_pressed,
	just_released,
	repeat,
}

Input_State :: struct {
	keys:      [MAX_KEYCODES]bit_set[Input_State_Flags],
	mouse_pos: Vector2,
	prev_mouse_pos: Vector2,
	click_consumed: bool,
}

reset_input_state_for_next_frame :: proc(state: ^Input_State) {
	state.prev_mouse_pos = state.mouse_pos
	state.click_consumed = false
	for &set in state.keys {
		set -= {.just_pressed, .just_released, .repeat}
	}
}

key_just_pressed :: proc(input_state: Input_State, code: Key_Code) -> bool {
	return .just_pressed in input_state.keys[code]
}
key_down :: proc(input_state: Input_State, code: Key_Code) -> bool {
	return .down in input_state.keys[code]
}
key_just_released :: proc(input_state: Input_State, code: Key_Code) -> bool {
	return .just_released in input_state.keys[code]
}
key_repeat :: proc(input_state: Input_State, code: Key_Code) -> bool {
	return .repeat in input_state.keys[code]
}

event :: proc "c" (event: ^sapp.Event) {
	input_state := &app_state.input_state

	#partial switch event.type {
	case .MOUSE_UP:
		if .down in input_state.keys[map_sokol_mouse_button(event.mouse_button)] {
			input_state.keys[map_sokol_mouse_button(event.mouse_button)] -= {.down}
			input_state.keys[map_sokol_mouse_button(event.mouse_button)] += {.just_released}
		}
	case .MOUSE_DOWN:
		if !(.down in input_state.keys[map_sokol_mouse_button(event.mouse_button)]) {
			input_state.keys[map_sokol_mouse_button(event.mouse_button)] += {.down, .just_pressed}
		}

	case .KEY_UP:
		if .down in input_state.keys[event.key_code] {
			input_state.keys[event.key_code] -= {.down}
			input_state.keys[event.key_code] += {.just_released}
		}
	case .KEY_DOWN:
		if !event.key_repeat && !(.down in input_state.keys[event.key_code]) {
			input_state.keys[event.key_code] += {.down, .just_pressed}
		}
		if event.key_repeat {
			input_state.keys[event.key_code] += {.repeat}
		}
	case .MOUSE_MOVE:
		input_state.mouse_pos = {event.mouse_x, event.mouse_y}
  	case .RESIZED:
	   window_w = event.window_width
	   window_h = event.window_height
	}
}
