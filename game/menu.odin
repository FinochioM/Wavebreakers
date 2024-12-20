package main

import "core:fmt"

MENU_BUTTON_WIDTH :: 200.0
MENU_BUTTON_HEIGHT :: 50.0
PAUSE_MENU_BUTTON_WIDTH :: 200.0
PAUSE_MENU_BUTTON_HEIGHT :: 50.0
PAUSE_MENU_SPACING :: 20.0
WAVE_BUTTON_WIDTH :: 200.0
WAVE_BUTTON_HEIGHT :: 50.0

draw_menu :: proc(gs: ^Game_State) {
	play_button := make_centered_button(0, MENU_BUTTON_WIDTH, MENU_BUTTON_HEIGHT, "Play")

	if draw_button(play_button) {
		e := entity_create(gs)
		if e != nil {
			setup_player(e)
		}

		gs.state_kind = .PLAYING
	}
}

draw_pause_menu :: proc(gs: ^Game_State) {
	draw_rect_aabb(v2{-2000, -2000}, v2{4000, 4000}, col = v4{0.0, 0.0, 0.0, 0.5})

	resume_button := make_centered_button(
		PAUSE_MENU_SPACING + PAUSE_MENU_BUTTON_HEIGHT,
		PAUSE_MENU_BUTTON_WIDTH,
		PAUSE_MENU_BUTTON_HEIGHT,
		"Resume",
	)


	shop_button := make_centered_button(
		0,
		PAUSE_MENU_BUTTON_WIDTH,
		PAUSE_MENU_BUTTON_HEIGHT,
		"Shop",
	)

	menu_button := make_centered_button(
		-(PAUSE_MENU_SPACING + PAUSE_MENU_BUTTON_HEIGHT),
		PAUSE_MENU_BUTTON_WIDTH,
		PAUSE_MENU_BUTTON_HEIGHT,
		"Main Menu",
	)

	if draw_button(resume_button) {
		gs.state_kind = .PLAYING
	}

	if draw_button(menu_button) {
		gs.state_kind = .MENU
	}

	if draw_button(shop_button) {
		gs.state_kind = .SHOP
	}
}

draw_shop_menu :: proc(gs: ^Game_State) {
	draw_rect_aabb(v2{-2000, -2000}, v2{4000, 4000}, col = v4{0.0, 0.0, 0.0, 0.5})

	title_pos := v2{-200, 300}
	draw_text(title_pos, "Statistics", scale = 3.0)

	currency_pos := v2{-200, 250}
	currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
	draw_text(currency_pos, currency_text, scale = 2.0)

	y_start := 150.0
	spacing := 80.0
	column_spacing := 400.0

	player := find_player(gs)
	if player == nil do return

	column_count := 2
	items_per_column := (len(Upgrade_Kind) + column_count - 1) / column_count

	for upgrade, i in Upgrade_Kind {
		column := i / items_per_column
		row := i % items_per_column

		level := get_upgrade_level(player, upgrade)
		cost := calculate_upgrade_cost(level)

		button_text := fmt.tprintf("%v (Level %d) - Cost: %d", upgrade, level, cost)
		x_offset := f32(column) * auto_cast column_spacing - auto_cast column_spacing / 2
		y_offset := f32(y_start) - f32(row) * auto_cast spacing

		button := make_centered_button(
			y_offset,
			PAUSE_MENU_BUTTON_WIDTH * 1.5,
			PAUSE_MENU_BUTTON_HEIGHT,
			button_text,
			x_offset = x_offset,
		)

		if draw_button(button) {
			try_purchase_upgrade(gs, player, upgrade)
		}
	}

	back_button := make_centered_button(
		-350,
		PAUSE_MENU_BUTTON_WIDTH,
		PAUSE_MENU_BUTTON_HEIGHT,
		"Back",
	)

	if draw_button(back_button) {
		gs.state_kind = .PLAYING
	}
}

draw_game_over_screen :: proc(gs: ^Game_State){
	draw_rect_aabb(v2{-2000, -2000}, v2{4000, 4000}, col = v4{0.0, 0.0, 0.0, 0.7})

	title_pos := v2{-200, 100}
	draw_text(title_pos, "Game Over!", scale = 3.0)

	wave_text_pos := v2{-150, 0}
	wave_text := fmt.tprintf("Waves Completed %d", gs.wave_number - 1)
	draw_text(wave_text_pos, wave_text, scale = 2.0)

	menu_button := make_centered_button(
	   -100,
	   MENU_BUTTON_WIDTH,
	   MENU_BUTTON_HEIGHT,
	   "Main Menu",
	)

	if draw_button(menu_button){
	   gs.state_kind = .MENU
	}
}

draw_wave_button :: proc(gs: ^Game_State){
    button_pos := v2{0, 500}

    #partial switch gs.wave_status {
        case .WAITING:
            button := Button{
                bounds = {
                    button_pos.x - WAVE_BUTTON_WIDTH * 0.5,
                    button_pos.y - WAVE_BUTTON_HEIGHT * 0.5,
                    button_pos.x + WAVE_BUTTON_WIDTH * 0.5,
                    button_pos.y + WAVE_BUTTON_HEIGHT * 0.5,
                },
                text = fmt.tprintf("Start Wave %d", gs.wave_number),
                text_scale = 2.0,
                color = v4{0.2, 0.6, 0.2, 1.0},
            }

            if draw_button(button){
                gs.wave_status = .IN_PROGRESS
            }
        case .COMPLETED:
            button := Button{
                bounds = {
                    button_pos.x - WAVE_BUTTON_WIDTH * 0.5,
                    button_pos.y - WAVE_BUTTON_HEIGHT * 0.5,
                    button_pos.x + WAVE_BUTTON_WIDTH * 0.5,
                    button_pos.y + WAVE_BUTTON_HEIGHT * 0.5,
                },
                text = fmt.tprintf("Start Wave %d", gs.wave_number + 1),
                text_scale = 2.0,
                color = v4{0.2, 0.6, 0.2, 1.0},
            }

            if draw_button(button){
                init_wave(gs, gs.wave_number + 1)
                gs.wave_status = .IN_PROGRESS
            }
    }
}

draw_button :: proc(button: Button) -> bool {
	mouse_pos := screen_to_world_pos(app_state.input_state.mouse_pos)
	is_hovered := aabb_contains(button.bounds, mouse_pos)

	color := button.color
	if is_hovered {
		color.xyz *= 1.2
	}

	draw_rect_aabb(
		v2{button.bounds.x, button.bounds.y},
		v2{button.bounds.z - button.bounds.x, button.bounds.w - button.bounds.y},
		col = color,
	)

	text_width := f32(len(button.text)) * 8 * button.text_scale
	text_height := 16 * button.text_scale

	text_pos := v2 {
		button.bounds.x + (button.bounds.z - button.bounds.x - text_width) * 0.5,
		button.bounds.y + (button.bounds.w - button.bounds.y - text_height) * 0.5,
	}

	draw_text(text_pos, button.text, scale = auto_cast button.text_scale)

	return is_hovered && key_just_pressed(app_state.input_state, .LEFT_MOUSE)
}

make_centered_button :: proc(
	y_pos: f32,
	width: f32,
	height: f32,
	text: string,
	color := v4{0.2, 0.3, 0.8, 1.0},
	x_offset := f32(0),
) -> Button {
	return Button {
		bounds = {
			-width * 0.5 + x_offset,
			y_pos - height * 0.5,
			width * 0.5 + x_offset,
			y_pos + height * 0.5,
		},
		text = text,
		text_scale = 2.0,
		color = color,
	}
}