package main

import sg "../sokol/gfx"

app_state: struct {
	pass_action:   sg.Pass_Action,
	pip:           sg.Pipeline,
	bind:          sg.Bindings,
	input_state:   Input_State,
	game:          Game_State,
	message_queue: [dynamic]Event,
	camera_pos:    Vector2,
}
