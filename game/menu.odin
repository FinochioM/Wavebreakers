package main

import "core:fmt"

MENU_BUTTON_WIDTH :: 40.0
MENU_BUTTON_HEIGHT :: 20.0
PAUSE_MENU_BUTTON_WIDTH :: 50.0
PAUSE_MENU_BUTTON_HEIGHT :: 20.0
PAUSE_MENU_SPACING :: 10.0
WAVE_BUTTON_WIDTH :: 45.0
WAVE_BUTTON_HEIGHT :: 15.0

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
    config := get_ui_config(&gs.ui_hot_reload)

    // Background overlay
    draw_rect_aabb(v2{-2000, -2000}, v2{4000, 4000}, col = v4{0.0, 0.0, 0.0, 0.5})

    // Panel setup
    panel_width := config.shop_panel_width
    panel_height := config.shop_panel_height
    panel_x := -panel_width * 0.5
    panel_y := -panel_height * 0.5

    // Main panel
    draw_rect_aabb(
        v2{auto_cast panel_x, auto_cast panel_y},
        v2{auto_cast panel_width, auto_cast panel_height},
        col = v4{0.1, 0.1, 0.1, 0.9},
    )

    player := find_player(gs)
    if player == nil do return

    // Title and currency
    title_pos := v2{
        auto_cast panel_x + config.shop_title_offset_x,
        auto_cast panel_y + auto_cast panel_height - config.shop_title_offset_y
    }
    draw_text(title_pos, "Shop", scale = f64(config.shop_text_scale_title))

    currency_pos := v2{
        auto_cast panel_x + auto_cast panel_width - config.shop_currency_text_offset_x,
        auto_cast panel_y + auto_cast panel_height - config.shop_currency_text_offset_y
    }
    currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
    draw_text(currency_pos, currency_text, scale = f64(config.shop_currency_text_scale))

    // Column layout
    column_count := 2
    items_per_column := (len(Upgrade_Kind) + column_count - 1) / column_count
    content_width := panel_width - config.shop_content_padding
    column_width := auto_cast content_width / auto_cast column_count
    button_spacing_y := config.shop_button_spacing_y
    total_height := f32(items_per_column) * auto_cast button_spacing_y
    start_y := panel_y + panel_height - config.shop_row_start_offset

    // Draw upgrade buttons
    for upgrade, i in Upgrade_Kind {
        column := i / items_per_column
        row := i % items_per_column

        base_x := panel_x + config.shop_column_start_offset + (column_width * auto_cast column)
        x_pos := base_x + (column_width - config.shop_button_width) * 0.5
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
                auto_cast y_pos - config.shop_button_vertical_padding,
                auto_cast x_pos + config.shop_button_width,
                auto_cast y_pos + config.shop_button_height - config.shop_button_vertical_padding,
            },
            text = button_text,
            text_scale = config.shop_text_scale_button,
            color = button_color,
        }

        if level < MAX_UPGRADE_LEVEL {
            if draw_button(button) {
                try_purchase_upgrade(gs, player, upgrade)
            }
        }

        // Upgrade text
        name_pos := v2{
            auto_cast x_pos,
            auto_cast y_pos + config.shop_upgrade_text_offset_y
        }
        upgrade_text := fmt.tprintf("%v (Level %d)", upgrade, level)
        draw_text(name_pos, upgrade_text, scale = f64(config.shop_text_scale_upgrade))

        if level >= MAX_UPGRADE_LEVEL {
            max_pos := v2{
                auto_cast x_pos + config.shop_button_width + config.shop_max_text_offset_x,
                auto_cast y_pos + config.shop_max_text_offset_y
            }
            draw_text(max_pos, "MAX", scale = f64(config.shop_text_scale_upgrade), color = v4{1, 0.8, 0, 1})
        }
    }

    // Back button
    back_button := Button{
        bounds = {
            auto_cast panel_x + auto_cast panel_width * 0.5 - config.shop_back_button_width * 0.5,
            auto_cast panel_y - config.shop_back_button_offset_y,
            auto_cast panel_x + auto_cast panel_width * 0.5 + config.shop_back_button_width * 0.5,
            auto_cast panel_y - config.shop_back_button_offset_y + config.shop_back_button_height,
        },
        text = "Back",
        text_scale = config.shop_back_button_text_scale,
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
                text_scale = 0.4,
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
                text_scale = 0.4,
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
    config := get_ui_config(&gs.ui_hot_reload)

    panel_pos := v2{0, 0}
    panel_bounds := AABB{
        panel_pos.x - config.skills_panel_width * 0.5,
        panel_pos.y - config.skills_panel_height * 0.5,
        panel_pos.x + config.skills_panel_width * 0.5,
        panel_pos.y + config.skills_panel_height * 0.5,
    }

    draw_rect_aabb(
        v2{panel_bounds.x, panel_bounds.y},
        v2{config.skills_panel_width, config.skills_panel_height},
        col = v4{0.2, 0.2, 0.2, 0.9},
    )

    title_pos := v2{
        panel_bounds.x + config.skills_title_offset_x,
        panel_bounds.w - config.skills_title_offset_y
    }
    draw_text(title_pos, "Skills", scale = f64(config.skills_title_text_scale))

    unlocked_skills: [dynamic]Skill
    unlocked_skills.allocator = context.temp_allocator

    for kind in Skill_Kind {
        if gs.skills[kind].unlocked {
            append(&unlocked_skills, gs.skills[kind])
        }
    }

    content_start_y := panel_bounds.w - config.skills_content_top_offset
    visible_height := panel_bounds.w - panel_bounds.y - config.skills_content_top_offset - config.skills_content_bottom_offset
    total_content_height := f32(len(unlocked_skills)) * (config.skills_entry_height + config.skills_entry_spacing)

    if key_down(app_state.input_state, .LEFT_MOUSE) {
        mouse_delta := app_state.input_state.mouse_pos.y - app_state.input_state.prev_mouse_pos.y
        gs.skills_scroll_offset += mouse_delta * config.skills_scroll_speed * sims_per_second
    }

    max_scroll := max(0, total_content_height - visible_height)
    gs.skills_scroll_offset = clamp(gs.skills_scroll_offset, 0, max_scroll)

    content_top := panel_bounds.w - config.skills_content_top_offset
    content_bottom := panel_bounds.y + config.skills_content_bottom_offset

    for skill, i in unlocked_skills {
        y_pos := content_start_y - f32(i) * (config.skills_entry_height + config.skills_entry_spacing) + gs.skills_scroll_offset

        if y_pos < content_bottom || y_pos > content_top {
            continue
        }

        entry_bounds := AABB{
            panel_bounds.x + config.skills_entry_padding_x,
            y_pos,
            panel_bounds.z - config.skills_entry_padding_x - config.skills_scrollbar_width,
            y_pos + config.skills_entry_height,
        }

        is_active := gs.active_skill != nil && gs.active_skill.? == skill.kind
        bg_color := is_active ? v4{0.4, 0.3, 0.6, 0.8} : v4{0.3, 0.3, 0.3, 0.8}

        draw_rect_aabb(
            v2{entry_bounds.x, entry_bounds.y},
            v2{entry_bounds.z - entry_bounds.x, entry_bounds.w - entry_bounds.y},
            col = bg_color,
        )

        text_pos := v2{
            entry_bounds.x + config.skills_entry_text_offset_x,
            entry_bounds.y + config.skills_entry_text_offset_y
        }
        draw_text(
            text_pos,
            fmt.tprintf("%v (Level %d)", skill.kind, skill.level),
            scale = f64(config.skills_entry_text_scale),
        )

        progress := get_skill_progress(skill)
        progress_width := (entry_bounds.z - entry_bounds.x - config.skills_progress_bar_padding_x * 2) * progress
        progress_bounds := AABB{
            entry_bounds.x + config.skills_progress_bar_padding_x,
            entry_bounds.y + config.skills_entry_height - config.skills_progress_bar_offset_bottom,
            entry_bounds.x + config.skills_progress_bar_padding_x + progress_width,
            entry_bounds.y + config.skills_entry_height - config.skills_progress_bar_offset_bottom + config.skills_progress_bar_height,
        }

        draw_rect_aabb(
            v2{entry_bounds.x + config.skills_progress_bar_padding_x, entry_bounds.y + config.skills_entry_height - config.skills_progress_bar_offset_bottom},
            v2{entry_bounds.z - entry_bounds.x - config.skills_progress_bar_padding_x * 2, config.skills_progress_bar_height},
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
            panel_bounds.z - config.skills_scrollbar_width - config.skills_scrollbar_offset_right,
            panel_bounds.y + config.skills_scrollbar_padding_y,
            panel_bounds.z - config.skills_scrollbar_offset_right,
            panel_bounds.w - config.skills_scrollbar_padding_y,
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
        config.pause_menu_button_width,
        config.pause_menu_button_height,
        "Back",
    )

    if draw_button(back_button) {
        gs.state_kind = .PLAYING
    }
}

draw_quest_menu :: proc(gs: ^Game_State) {
    config := get_ui_config(&gs.ui_hot_reload)

    panel_pos := v2{0, 0}
    panel_bounds := AABB{
        panel_pos.x - config.quest_panel_width * 0.5,
        panel_pos.y - config.quest_panel_height * 0.5,
        panel_pos.x + config.quest_panel_width * 0.5,
        panel_pos.y + config.quest_panel_height * 0.5,
    }

    draw_rect_aabb(
        v2{panel_bounds.x, panel_bounds.y},
        v2{config.quest_panel_width, config.quest_panel_height},
        col = v4{0.2, 0.2, 0.2, 0.9},
    )

    // Title and currency
    title_pos := v2{panel_bounds.x + config.quest_title_offset_x, panel_bounds.w - config.quest_title_offset_y}
    draw_text(title_pos, "Quests", scale = f64(config.quest_title_scale))

    currency_pos := v2{panel_bounds.z - config.quest_currency_offset_x, panel_bounds.w - config.quest_currency_offset_y}
    draw_text(currency_pos, fmt.tprintf("Currency: %d", gs.currency_points), scale = f64(config.quest_currency_scale))

    // Content area setup
    content_start_y := panel_bounds.w - config.quest_content_top_offset
    visible_height := panel_bounds.w - panel_bounds.y - config.quest_content_top_offset - config.quest_content_bottom_offset

    total_content_height: f32 = 0
    for category in Quest_Category {
        total_content_height += config.quest_category_spacing
        quest_count := 0
        for kind, info in QUEST_INFO {
            if info.category == category {
                quest := gs.quests[kind]
                if quest.state != .Locked {
                    total_content_height += config.quest_entry_height + config.quest_entry_padding
                    quest_count += 1
                }
            }
        }
        if quest_count > 0 {
            total_content_height += config.quest_category_bottom_spacing
        }
    }

    if key_down(app_state.input_state, .LEFT_MOUSE) {
        mouse_delta := app_state.input_state.mouse_pos.y - app_state.input_state.prev_mouse_pos.y
        gs.quest_scroll_offset += mouse_delta * config.quest_scroll_speed * sims_per_second
    }

    max_scroll := max(0, total_content_height - visible_height)
    gs.quest_scroll_offset = clamp(gs.quest_scroll_offset, 0, max_scroll)

    content_top := panel_bounds.w - config.quest_content_top_offset
    content_bottom := panel_bounds.y + config.quest_content_bottom_offset

    current_y := content_start_y + gs.quest_scroll_offset

    // Draw categories and quests
    for category in Quest_Category {
        if current_y < content_bottom || current_y > content_top {
            current_y -= config.quest_category_spacing
        } else {
            category_pos := v2{panel_bounds.x + config.quest_category_text_offset_x, current_y}
            draw_text(category_pos, fmt.tprintf("-- %v --", category), scale = f64(config.quest_category_text_scale))
            current_y -= config.quest_category_spacing
        }

        category_has_quests := false
        for kind, info in QUEST_INFO {
            if info.category != category do continue

            quest := gs.quests[kind]
            if quest.state == .Locked do continue

            category_has_quests = true

            if current_y - config.quest_entry_height < content_bottom || current_y > content_top {
                current_y -= config.quest_entry_height + config.quest_entry_padding
                continue
            }

            entry_bounds := AABB{
                panel_bounds.x + config.quest_entry_side_padding,
                current_y - config.quest_entry_height,
                panel_bounds.z - config.quest_entry_side_padding - config.quest_scrollbar_width,
                current_y,
            }

            bg_color := get_quest_background_color(quest)
            draw_rect_aabb(
                v2{entry_bounds.x, entry_bounds.y},
                v2{entry_bounds.z - entry_bounds.x, entry_bounds.w - entry_bounds.y},
                col = bg_color,
            )

            // Quest title
            text_pos := v2{
                entry_bounds.x + config.quest_entry_title_offset_x,
                entry_bounds.y + config.quest_entry_title_offset_y
            }
            text_color := quest.state == .Available ? v4{0.7, 0.7, 0.7, 1.0} : COLOR_WHITE
            draw_text(
                text_pos,
                fmt.tprintf("%v", kind),
                scale = f64(config.quest_entry_title_scale),
                color = text_color
            )

            // Quest description
            desc_pos := v2{
                entry_bounds.x + config.quest_entry_desc_offset_x,
                entry_bounds.y + config.quest_entry_desc_offset_y
            }
            draw_text(
                desc_pos,
                info.description,
                scale = f64(config.quest_entry_desc_scale),
                color = v4{0.7, 0.7, 0.7, 1.0}
            )

            // Quest status
            status_pos := v2{
                entry_bounds.z - config.quest_entry_status_offset_x,
                entry_bounds.y + config.quest_entry_status_offset_y
            }
            if quest.state == .Available {
                draw_text(
                    status_pos,
                    fmt.tprintf("Cost: %d", info.base_cost),
                    scale = f64(config.quest_entry_status_scale)
                )
            } else if quest.state == .Active {
                draw_text(
                    status_pos,
                    "Active",
                    scale = f64(config.quest_entry_status_scale),
                    color = v4{0.3, 0.8, 0.3, 1.0}
                )
            }

            mouse_pos := screen_to_world_pos(app_state.input_state.mouse_pos)
            if aabb_contains(entry_bounds, mouse_pos) && key_just_pressed(app_state.input_state, .LEFT_MOUSE) {
                handle_quest_click(gs, kind)
            }

            current_y -= config.quest_entry_height + config.quest_entry_padding
        }

        if category_has_quests {
            current_y -= config.quest_category_bottom_spacing
        }
    }

    // Scrollbar
    if total_content_height > visible_height {
        scrollbar_bounds := AABB{
            panel_bounds.z - config.quest_scrollbar_width - config.quest_scrollbar_offset_right,
            panel_bounds.y + config.quest_scrollbar_padding_y,
            panel_bounds.z - config.quest_scrollbar_offset_right,
            panel_bounds.w - config.quest_scrollbar_padding_y,
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
        config.pause_menu_button_width,
        config.pause_menu_button_height,
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