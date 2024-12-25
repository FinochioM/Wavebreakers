package main

import "core:fmt"

MENU_BUTTON_WIDTH :: 40.0
MENU_BUTTON_HEIGHT :: 20.0
PAUSE_MENU_BUTTON_WIDTH :: 50.0
PAUSE_MENU_BUTTON_HEIGHT :: 20.0
PAUSE_MENU_SPACING :: 10.0
WAVE_BUTTON_WIDTH :: 200.0
WAVE_BUTTON_HEIGHT :: 50.0

SKILLS_BUTTON_WIDTH :: 30.0
SKILLS_BUTTON_HEIGHT :: 10.0
SKILLS_PANEL_WIDTH :: 400.0
SKILLS_PANEL_HEIGHT :: 600.0
SKILL_ENTRY_HEIGHT :: 60.0
SKILL_ENTRY_PADDING :: 10.0

QUEST_BUTTON_WIDTH :: 30.0
QUEST_BUTTON_HEIGHT :: 10.0
QUEST_PANEL_WIDTH :: 800.0
QUEST_PANEL_HEIGHT :: 600.0
QUEST_ENTRY_HEIGHT :: 80.0
QUEST_ENTRY_PADDING :: 10.0

draw_menu :: proc(gs: ^Game_State) {
	play_button := make_centered_button(1, MENU_BUTTON_WIDTH, MENU_BUTTON_HEIGHT, "Play")

    if draw_button(play_button){
        start_new_game(gs)
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

	menu_button := make_centered_button(
		-(PAUSE_MENU_SPACING),
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
}

draw_shop_menu :: proc(gs: ^Game_State) {
    draw_rect_aabb(v2{-2000, -2000}, v2{4000, 4000}, col = v4{0.0, 0.0, 0.0, 0.5})

    panel_width := 512.0
    panel_height := 256.0
    panel_x := -panel_width * 0.5
    panel_y := -panel_height * 0.5

    draw_rect_aabb(
        v2{auto_cast panel_x, auto_cast panel_y},
        v2{auto_cast panel_width, auto_cast panel_height},
        col = v4{0.1, 0.1, 0.1, 0.9},
    )

    player := find_player(gs)
    if player == nil do return

    title_pos := v2{auto_cast panel_x + 150, auto_cast panel_y + auto_cast panel_height - 80}
    draw_text(title_pos, "Shop", scale = 1.2)

    currency_pos := v2{auto_cast panel_x + auto_cast panel_width, auto_cast panel_y + auto_cast panel_height - 80}
    currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
    draw_text(currency_pos, currency_text, scale = 0.7)

    column_count := 2
    items_per_column := (len(Upgrade_Kind) + column_count - 1) / column_count

    content_width := panel_width - 160
    column_width := auto_cast content_width / auto_cast column_count

    button_spacing_y := 20.0

    total_height := f32(items_per_column) * auto_cast button_spacing_y
    start_y := panel_y + panel_height - 150

    for upgrade, i in Upgrade_Kind {
        column := i / items_per_column
        row := i % items_per_column

        base_x := panel_x + 80 + (column_width * auto_cast column)
        x_pos := base_x + (column_width - PAUSE_MENU_BUTTON_WIDTH) * 0.5
        y_pos := start_y - auto_cast row * auto_cast button_spacing_y

        level := get_upgrade_level(player, upgrade)
        cost := calculate_upgrade_cost(level)

        button_text := fmt.tprintf("Cost: %d", cost)
        button_color := v4{0.2, 0.3, 0.8, 1.0}
        if level >= MAX_UPGRADE_LEVEL {
            button_color = v4{0.4, 0.4, 0.4, 1.0}
        } else if gs.currency_points < cost {
            button_color = v4{0.5, 0.2, 0.2, 1.0}
        }

        button := Button{
            bounds = {
                auto_cast x_pos,
                auto_cast y_pos - 10,
                auto_cast x_pos + PAUSE_MENU_BUTTON_WIDTH,
                auto_cast y_pos + PAUSE_MENU_BUTTON_HEIGHT - 10,
            },
            text = button_text,
            text_scale = 0.4,
            color = button_color,
        }

        if level < MAX_UPGRADE_LEVEL {
            if draw_button(button) {
                try_purchase_upgrade(gs, player, upgrade)
            }
        }
    }

    for upgrade, i in Upgrade_Kind {
        column := i / items_per_column
        row := i % items_per_column

        base_x := panel_x + 80 + (column_width * auto_cast column)
        x_pos := base_x + (column_width - PAUSE_MENU_BUTTON_WIDTH) * 0.5
        y_pos := start_y - auto_cast row * auto_cast button_spacing_y

        level := get_upgrade_level(player, upgrade)

        name_pos := v2{auto_cast x_pos, auto_cast y_pos + 45}
        upgrade_text := fmt.tprintf("%v (Level %d)", upgrade, level)
        draw_text(name_pos, upgrade_text, scale = 0.4)

        if level >= MAX_UPGRADE_LEVEL {
            max_pos := v2{auto_cast x_pos + PAUSE_MENU_BUTTON_WIDTH + 10, auto_cast y_pos + 5}
            draw_text(max_pos, "MAX", scale = 0.4, color = v4{1, 0.8, 0, 1})
        }
    }

    back_button := Button{
        bounds = {
            auto_cast panel_x + auto_cast panel_width * 0.5 - PAUSE_MENU_BUTTON_WIDTH * 0.5,
            auto_cast panel_y - 80,
            auto_cast panel_x + auto_cast panel_width * 0.5 + PAUSE_MENU_BUTTON_WIDTH * 0.5,
            auto_cast panel_y - 80 + PAUSE_MENU_BUTTON_HEIGHT,
        },
        text = "Back",
        text_scale = 2.0,
        color = v4{0.2, 0.3, 0.8, 1.0},
    }

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
    button_pos := v2{0, 0}

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
	is_clicked := is_hovered && key_just_pressed(app_state.input_state, .LEFT_MOUSE)

	if is_clicked {
	   play_sound("button_click")
	}

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
	text_scale := f32(0.5),
) -> Button {
	return Button {
		bounds = {
			-width * 0.5 + x_offset,
			y_pos - height * 0.5,
			width * 0.5 + x_offset,
			y_pos + height * 0.5,
		},
		text = text,
		text_scale = text_scale,
		color = color,
	}
}

draw_skills_button :: proc(gs: ^Game_State){
    if gs.state_kind != .PLAYING do return

    player := find_player(gs)
    if player == nil do return

    has_unlocked_skills := false
    for skill in gs.skills {
        if skill.unlocked{
            has_unlocked_skills = true
            break
        }
    }

    if !has_unlocked_skills do return

	button := make_centered_button(
		120,
		SKILLS_BUTTON_WIDTH,
		SKILLS_BUTTON_HEIGHT,
		"Skills",
		x_offset = SKILLS_BUTTON_WIDTH + PAUSE_MENU_SPACING,
		color = v4{0.5, 0.1, 0.8, 1.0},
		text_scale = 0.4
	)

    if draw_button(button){
        gs.state_kind = .SKILLS
    }
}

draw_shop_button :: proc(gs: ^Game_State){
	shop_button := make_centered_button(
		120,
		SKILLS_BUTTON_WIDTH,
		SKILLS_BUTTON_HEIGHT,
		"Shop",
		x_offset = 0,
		color = v4{0.5, 0.1, 0.8, 1.0},
		text_scale = 0.4
	)

	if draw_button(shop_button) {
		gs.state_kind = .SHOP
	}
}

draw_quest_button :: proc(gs: ^Game_State) {
    if gs.state_kind != .PLAYING do return
    player := find_player(gs)
    if player == nil do return

    has_available_quests := false
    for _, quest in gs.quests {
        if quest.state != .Locked {
            has_available_quests = true
            break
        }
    }

    button_color := v4{0.4, 0.4, 0.4, 0.5}
    if has_available_quests {
        button_color = v4{0.5, 0.1, 0.8, 1.0}
    }

    quest_button := make_centered_button(
        120,
        QUEST_BUTTON_WIDTH,
        QUEST_BUTTON_HEIGHT,
        "Quests",
        x_offset = -(QUEST_BUTTON_WIDTH + PAUSE_MENU_SPACING),
        color = button_color,
        text_scale = 0.4
    )

    if draw_button(quest_button) && has_available_quests {
        gs.state_kind = .QUESTS
    }
}

draw_skills_menu :: proc(gs: ^Game_State) {
    panel_pos := v2{0, 0}
    panel_bounds := AABB{
        panel_pos.x - SKILLS_PANEL_WIDTH * 0.5,
        panel_pos.y - SKILLS_PANEL_HEIGHT * 0.5,
        panel_pos.x + SKILLS_PANEL_WIDTH * 0.5,
        panel_pos.y + SKILLS_PANEL_HEIGHT * 0.5,
    }

    draw_rect_aabb(
        v2{panel_bounds.x, panel_bounds.y},
        v2{SKILLS_PANEL_WIDTH, SKILLS_PANEL_HEIGHT},
        col = v4{0.2, 0.2, 0.2, 0.9},
    )

    title_pos := v2{panel_bounds.x + 20, panel_bounds.w + 20}
    draw_text(title_pos, "Skills", scale = 2.5)

    unlocked_skills: [dynamic]Skill
    unlocked_skills.allocator = context.temp_allocator

    for kind in Skill_Kind {
        if gs.skills[kind].unlocked {
            append(&unlocked_skills, gs.skills[kind])
        }
    }

    content_start_y := panel_bounds.w - 100
    visible_height := panel_bounds.w - panel_bounds.y - 120
    total_content_height := f32(len(unlocked_skills)) * (SKILL_ENTRY_HEIGHT + SKILL_ENTRY_PADDING)

    scroll_speed :: 50.0
    if key_down(app_state.input_state, .LEFT_MOUSE) {
        mouse_delta := app_state.input_state.mouse_pos.y - app_state.input_state.prev_mouse_pos.y
        gs.skills_scroll_offset += mouse_delta * scroll_speed * sims_per_second
    }

    max_scroll := max(0, total_content_height - visible_height)
    gs.skills_scroll_offset = clamp(gs.skills_scroll_offset, 0, max_scroll)

    content_top := panel_bounds.w - 100
    content_bottom := panel_bounds.y + 50

    for skill, i in unlocked_skills {
        y_pos := content_start_y - f32(i) * (SKILL_ENTRY_HEIGHT + SKILL_ENTRY_PADDING) + gs.skills_scroll_offset

        if y_pos < content_bottom || y_pos > content_top {
            continue
        }

        entry_bounds := AABB{
            panel_bounds.x + 10,
            y_pos,
            panel_bounds.z - 30,
            y_pos + SKILL_ENTRY_HEIGHT,
        }

        is_active := gs.active_skill != nil && gs.active_skill.? == skill.kind
        bg_color := is_active ? v4{0.4, 0.3, 0.6, 0.8} : v4{0.3, 0.3, 0.3, 0.8}

        draw_rect_aabb(
            v2{entry_bounds.x, entry_bounds.y},
            v2{entry_bounds.z - entry_bounds.x, entry_bounds.w - entry_bounds.y},
            col = bg_color,
        )

        text_pos := v2{entry_bounds.x + 10, entry_bounds.y + 10}
        draw_text(
            text_pos,
            fmt.tprintf("%v (Level %d)", skill.kind, skill.level),
            scale = 1.5,
        )

        progress := get_skill_progress(skill)
        progress_width := (entry_bounds.z - entry_bounds.x - 20) * progress
        progress_bounds := AABB{
            entry_bounds.x + 10,
            entry_bounds.y + SKILL_ENTRY_HEIGHT - 15,
            entry_bounds.x + 10 + progress_width,
            entry_bounds.y + SKILL_ENTRY_HEIGHT - 5,
        }

        draw_rect_aabb(
            v2{entry_bounds.x + 10, entry_bounds.y + SKILL_ENTRY_HEIGHT - 15},
            v2{entry_bounds.z - entry_bounds.x - 20, 10},
            col = v4{0.2, 0.2, 0.2, 1.0},
        )

        draw_rect_aabb(
            v2{progress_bounds.x, progress_bounds.y},
            v2{progress_bounds.z - progress_bounds.x, progress_bounds.w - progress_bounds.y},
            col = v4{0.3, 0.8, 0.3, 1.0},
        )

        mouse_pos := screen_to_world_pos(app_state.input_state.mouse_pos)
        if aabb_contains(entry_bounds, mouse_pos) && key_just_pressed(app_state.input_state, .LEFT_MOUSE) {
            if gs.active_skill != nil && gs.active_skill.? == skill.kind {
                gs.active_skill = nil
            } else {
                gs.active_skill = skill.kind
            }
        }
    }

    if total_content_height > visible_height {
        scrollbar_bounds := AABB{
            panel_bounds.z - 20,
            panel_bounds.y + 100,
            panel_bounds.z - 10,
            panel_bounds.w - 20,
        }

        scroll_height := scrollbar_bounds.w - scrollbar_bounds.y
        thumb_height := (visible_height / total_content_height) * scroll_height
        thumb_pos := scrollbar_bounds.y + (gs.skills_scroll_offset / max_scroll) * (scroll_height - thumb_height)

        draw_rect_aabb(
            v2{scrollbar_bounds.x, scrollbar_bounds.y},
            v2{scrollbar_bounds.z - scrollbar_bounds.x, scrollbar_bounds.w - scrollbar_bounds.y},
            col = v4{0.3, 0.3, 0.3, 0.8},
        )

        draw_rect_aabb(
            v2{scrollbar_bounds.x, thumb_pos},
            v2{scrollbar_bounds.z - scrollbar_bounds.x, thumb_height},
            col = v4{0.5, 0.5, 0.5, 1.0},
        )
    }

    back_button := make_centered_button(
        panel_bounds.y + 25,
        PAUSE_MENU_BUTTON_WIDTH,
        PAUSE_MENU_BUTTON_HEIGHT,
        "Back",
    )

    if draw_button(back_button) {
        gs.state_kind = .PLAYING
    }
}

draw_quest_menu :: proc(gs: ^Game_State) {
    panel_pos := v2{0, 0}
    panel_bounds := AABB{
        panel_pos.x - QUEST_PANEL_WIDTH * 0.5,
        panel_pos.y - QUEST_PANEL_HEIGHT * 0.5,
        panel_pos.x + QUEST_PANEL_WIDTH * 0.5,
        panel_pos.y + QUEST_PANEL_HEIGHT * 0.5,
    }

    draw_rect_aabb(
        v2{panel_bounds.x, panel_bounds.y},
        v2{QUEST_PANEL_WIDTH, QUEST_PANEL_HEIGHT},
        col = v4{0.2, 0.2, 0.2, 0.9},
    )

    title_pos := v2{panel_bounds.x + 20, panel_bounds.w - 50}
    draw_text(title_pos, "Quests", scale = 2.5)

    currency_pos := v2{panel_bounds.z - 250, panel_bounds.w - 50}
    draw_text(currency_pos, fmt.tprintf("Currency: %d", gs.currency_points), scale = 2.0)

    content_start_y := panel_bounds.w - 100
    visible_height := panel_bounds.w - panel_bounds.y - 120

    total_content_height: f32 = 0
    for category in Quest_Category {
        total_content_height += 30.0
        quest_count := 0
        for kind, info in QUEST_INFO {
            if info.category == category {
                quest := gs.quests[kind]
                if quest.state != .Locked {
                    total_content_height += QUEST_ENTRY_HEIGHT + QUEST_ENTRY_PADDING
                    quest_count += 1
                }
            }
        }
        if quest_count > 0 {
            total_content_height += 30.0
        }
    }

    scroll_speed :: 50.0
    if key_down(app_state.input_state, .LEFT_MOUSE) {
        mouse_delta := app_state.input_state.mouse_pos.y - app_state.input_state.prev_mouse_pos.y
        gs.quest_scroll_offset += mouse_delta * scroll_speed * sims_per_second
    }

    max_scroll := max(0, total_content_height - visible_height)
    gs.quest_scroll_offset = clamp(gs.quest_scroll_offset, 0, max_scroll)

    content_top := panel_bounds.w - 100
    content_bottom := panel_bounds.y + 50

    current_y := content_start_y + gs.quest_scroll_offset

    for category in Quest_Category {
        if current_y < content_bottom || current_y > content_top {
            current_y -= 30.0 // Skip category header space
        } else {
            category_pos := v2{panel_bounds.x + 20, current_y}
            draw_text(category_pos, fmt.tprintf("-- %v --", category), scale = 2.0)
            current_y -= 30.0
        }

        category_has_quests := false
        for kind, info in QUEST_INFO {
            if info.category != category do continue

            quest := gs.quests[kind]
            if quest.state == .Locked do continue

            category_has_quests = true

            if current_y - QUEST_ENTRY_HEIGHT < content_bottom || current_y > content_top {
                current_y -= QUEST_ENTRY_HEIGHT + QUEST_ENTRY_PADDING
                continue
            }

            entry_bounds := AABB{
                panel_bounds.x + 10,
                current_y - QUEST_ENTRY_HEIGHT,
                panel_bounds.z - 30,
                current_y,
            }

            bg_color := get_quest_background_color(quest)
            draw_rect_aabb(
                v2{entry_bounds.x, entry_bounds.y},
                v2{entry_bounds.z - entry_bounds.x, entry_bounds.w - entry_bounds.y},
                col = bg_color,
            )

            text_pos := v2{entry_bounds.x + 10, entry_bounds.y + 10}
            text_color := quest.state == .Available ? v4{0.7, 0.7, 0.7, 1.0} : COLOR_WHITE
            draw_text(text_pos, fmt.tprintf("%v", kind), scale = 1.5, color = text_color)

            desc_pos := v2{entry_bounds.x + 10, entry_bounds.y + 35}
            draw_text(desc_pos, info.description, scale = 1.2, color = v4{0.7, 0.7, 0.7, 1.0})

            status_pos := v2{entry_bounds.z - 150, entry_bounds.y + 10}
            if quest.state == .Available {
                draw_text(status_pos, fmt.tprintf("Cost: %d", info.base_cost), scale = 1.2)
            } else if quest.state == .Active {
                draw_text(status_pos, "Active", scale = 1.2, color = v4{0.3, 0.8, 0.3, 1.0})
            }

            mouse_pos := screen_to_world_pos(app_state.input_state.mouse_pos)
            if aabb_contains(entry_bounds, mouse_pos) && key_just_pressed(app_state.input_state, .LEFT_MOUSE) {
                handle_quest_click(gs, kind)
            }

            current_y -= QUEST_ENTRY_HEIGHT + QUEST_ENTRY_PADDING
        }

        if category_has_quests {
            current_y -= 30.0
        }
    }

    if total_content_height > visible_height {
        scrollbar_bounds := AABB{
            panel_bounds.z - 20,
            panel_bounds.y + 100,
            panel_bounds.z - 10,
            panel_bounds.w - 20,
        }

        scroll_height := scrollbar_bounds.w - scrollbar_bounds.y
        thumb_height := (visible_height / total_content_height) * scroll_height
        thumb_pos := scrollbar_bounds.y + (gs.quest_scroll_offset / max_scroll) * (scroll_height - thumb_height)

        draw_rect_aabb(
            v2{scrollbar_bounds.x, scrollbar_bounds.y},
            v2{scrollbar_bounds.z - scrollbar_bounds.x, scrollbar_bounds.w - scrollbar_bounds.y},
            col = v4{0.3, 0.3, 0.3, 0.8},
        )

        draw_rect_aabb(
            v2{scrollbar_bounds.x, thumb_pos},
            v2{scrollbar_bounds.z - scrollbar_bounds.x, thumb_height},
            col = v4{0.5, 0.5, 0.5, 1.0},
        )
    }

    back_button := make_centered_button(
        panel_bounds.y + 25,
        PAUSE_MENU_BUTTON_WIDTH,
        PAUSE_MENU_BUTTON_HEIGHT,
        "Back",
    )

    if draw_button(back_button) {
        gs.state_kind = .PLAYING
    }
}

get_quest_background_color :: proc(quest: Quest) -> Vector4 {
    #partial switch quest.state {
        case .Available:
            return v4{0.3, 0.3, 0.3, 0.8}
        case .Purchased:
            return v4{0.4, 0.4, 0.3, 0.8}
        case .Active:
            return v4{0.4, 0.5, 0.3, 0.8}
        case:
            return v4{0.2, 0.2, 0.2, 0.8}
    }
}

handle_quest_click :: proc(gs: ^Game_State, kind: Quest_Kind) {
    quest := &gs.quests[kind]

    #partial switch quest.state {
        case .Available:
            try_purchase_quest(gs, kind)
        case .Purchased:
            activate_quest(gs, kind)
        case .Active:
            deactivate_quest(gs)
    }
}