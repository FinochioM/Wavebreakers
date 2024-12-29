package main

import "core:fmt"
import sapp "../sokol/app"
import "core:strings"

MENU_BUTTON_WIDTH :: 100.0
MENU_BUTTON_HEIGHT :: 50.0
PAUSE_MENU_BUTTON_WIDTH :: 150.0
PAUSE_MENU_BUTTON_HEIGHT :: 30.0
PAUSE_MENU_SPACING :: 10.0
WAVE_BUTTON_WIDTH :: 120.0
WAVE_BUTTON_HEIGHT :: 30.0

SKILLS_BUTTON_WIDTH :: 60.0
SKILLS_BUTTON_HEIGHT :: 20.0
SKILLS_PANEL_WIDTH :: 400.0
SKILLS_PANEL_HEIGHT :: 600.0
SKILL_ENTRY_HEIGHT :: 60.0
SKILL_ENTRY_PADDING :: 10.0

QUEST_BUTTON_WIDTH :: 60.0
QUEST_BUTTON_HEIGHT :: 20.0
QUEST_PANEL_WIDTH :: 800.0
QUEST_PANEL_HEIGHT :: 600.0
QUEST_ENTRY_HEIGHT :: 80.0
QUEST_ENTRY_PADDING :: 10.0

SETTINGS_BUTTON_WIDTH :: 60.0
SETTINGS_BUTTON_HEIGHT :: 20.0
SETTINGS_PANEL_WIDTH :: 200.0
SETTINGS_PANEL_HEIGHT :: 150.0

init_main_menu :: proc(state: ^UI_State) {
    config := get_ui_config(&state.hot_config)
    screen := UI_Screen{
        elements = make([dynamic]^UI_Element),
        config = config,
    }

    background := create_ui_element(
        "main_menu_bg",
        .Panel,
        UI_Layout{
            size = {f32(window_w), f32(window_h)},
            position = {0, 0},         // Center position
            anchor = {0.5, 0.5},       // Anchor at center
            pivot = {0.5, 0.5},        // Pivot at center
        },
        UI_Style{
            background_color = {0.1, 0.1, 0.1, 1},
        },
    )

    content := create_ui_element(
        "content",
        .Panel,
        UI_Layout{
            size = {600, 400},         // Fixed content size
            position = {0, 0},         // Center in background
            anchor = {0.5, 0.5},       // Center anchor
            pivot = {0.5, 0.5},        // Center pivot
        },
        UI_Style{
            background_color = {0, 0, 0, 0},
        },
    )
    add_child(background, content)

    text_content := "Wavebreakers"
    text_dims := get_text_dimensions(text_content, 2.0)
    title := create_ui_element(
        "main_menu_title",
        .Text,
        UI_Layout{
            size = text_dims,
            position = {0, 100},       // Y position relative to content
            anchor = {0.5, 0.5},       // Center in parent
            pivot = {0.5, 0.5},        // Center pivot
        },
        UI_Style{
            text_color = {1, 1, 1, 1},
            text_scale = 2.0,
        },
    )
    title.text = text_content
    add_child(content, title)

    play_button := create_ui_element(
        "play_button",
        .Button,
        UI_Layout{
            size = {100, 20},
            position = {0, 0},         // Center of content
            anchor = {0.5, 0.5},       // Center in parent
            pivot = {0.5, 0.5},        // Center pivot
        },
        UI_Style{
            background_color = {0.2, 0.4, 0.8, 1},
            text_color = {1, 1, 1, 1},
            text_scale = 0.8,
        },
    )
    play_button.text = "Play"
    play_button.on_click = proc(element: ^UI_Element) {
        if app_state.game.state_kind == .MENU {
            start_new_game(&app_state.game)
            app_state.game.state_kind = .PLAYING
        }
    }
    add_child(content, play_button)

    settings_button := create_ui_element(
        "settings_button",
        .Button,
        UI_Layout{
            size = {100, 20},
            position = {0, -50},      // Below play button
            anchor = {0.5, 0.5},       // Center in parent
            pivot = {0.5, 0.5},        // Center pivot
        },
        UI_Style{
            background_color = {0.2, 0.4, 0.8, 1},
            text_color = {1, 1, 1, 1},
            text_scale = 0.8,
        },
    )
    settings_button.text = "Settings"
    settings_button.on_click = proc(element: ^UI_Element) {
        if app_state.game.state_kind == .MENU {
            app_state.game.state_kind = .SETTINGS
        }
    }
    add_child(content, settings_button)

    append(&screen.elements, background)
    state.screens["main_menu"] = screen
    state.active_screen = "main_menu"
}

init_settings_screen :: proc(state: ^UI_State) {
    config := get_ui_config(&state.hot_config)
    screen := UI_Screen{
        elements = make([dynamic]^UI_Element),
        config = config,
    }

    background := create_ui_element(
        "settings_bg_overlay",
        .Panel,
        UI_Layout{
            size = {f32(window_w), f32(window_h)},
            position = {-game_res_w, -game_res_h},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0, 0, 0, 0.5},
        },
    )

    title := create_ui_element(
        "settings_title",
        .Text,
        UI_Layout{
            size = {80, 20},
            position = {500, 50},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            text_color = {1, 1, 1, 1},
            text_scale = 0.6,
        },
    )
    title.text = "Settings"

    tutorial_button := create_ui_element(
        "tutorial_toggle",
        .Button,
        UI_Layout{
            position = {0, 350},
            size = {120, 30},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0.2, 0.4, 0.8, 1},
            text_color = {1, 1, 1, 1},
            text_scale = 0.4,
        },
    )
    tutorial_button.text = "Tutorial: ON"
    tutorial_button.on_click = proc(element: ^UI_Element) {
        app_state.game.settings.tutorial_enabled = !app_state.game.settings.tutorial_enabled
        app_state.game.tutorial.enabled = app_state.game.settings.tutorial_enabled
        if app_state.game.settings.tutorial_enabled {
            element.text = "Tutorial ON"
        }else{
            element.text = "Tutorial OFF"
        }
    }

    back_button := create_ui_element(
        "settings_back",
        .Button,
        UI_Layout{
            size = {80, 30},
            position = {0, 550},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0.2, 0.4, 0.8, 1},
            text_color = {1, 1, 1, 1},
            text_scale = 0.4,
        },
    )
    back_button.text = "Back"
    back_button.on_click = proc(element: ^UI_Element) {
        app_state.game.state_kind = .MENU
    }

    add_child(background, title)
    add_child(background, tutorial_button)
    add_child(background, back_button)
    append(&screen.elements, background)

    state.screens["settings"] = screen
}

init_pause_menu :: proc(state: ^UI_State) {
    config := get_ui_config(&state.hot_config)
    screen := UI_Screen{
        elements = make([dynamic]^UI_Element),
        config = config,
    }

    background := create_ui_element(
        "pause_bg_overlay",
        .Panel,
        UI_Layout{
            size = {f32(window_w), f32(window_h)},
            position = {-game_res_w, -game_res_h},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0, 0, 0, 1.0},
        },
    )

    resume_button := create_ui_element(
        "resume",
        .Button,
        UI_Layout{
            position = {0, 350},
            size = {120, 30},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0.2, 0.4, 0.8, 1},
            text_color = {1, 1, 1, 1},
            text_scale = 0.4,
        },
    )
    resume_button.text = "Resume"
    resume_button.on_click = proc(element: ^UI_Element) {
        app_state.game.state_kind = .PLAYING
    }

    main_menu_button := create_ui_element(
        "main_menu",
        .Button,
        UI_Layout{
            position = {0, 450},
            size = {120, 30},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0.2, 0.4, 0.8, 1},
            text_color = {1, 1, 1, 1},
            text_scale = 0.4,
        },
    )
    main_menu_button.text = "Main Menu"
    main_menu_button.on_click = proc(element: ^UI_Element) {
        app_state.game.state_kind = .MENU
    }

    add_child(background, resume_button)
    add_child(background, main_menu_button)
    append(&screen.elements, background)

    state.screens["pause"] = screen
}

get_upgrade_enum_from_string :: proc(id: string) -> Upgrade_Kind {
    if !strings.has_prefix(id, "upgrade_") {
        return .attack_speed
    }

    kind_str := strings.trim_prefix(id, "upgrade_")
    switch kind_str {
        case "attack_speed": return .attack_speed
        case "accuracy": return .accuracy
        case "damage": return .damage
        case "armor": return .armor
        case "life_steal": return .life_steal
        case "exp_gain": return .exp_gain
        case "crit_chance": return .crit_chance
        case "crit_damage": return .crit_damage
        case "multishot": return .multishot
        case "health_regen": return .health_regen
        case "dodge_chance": return .dodge_chance
        case "fov_range": return .fov_range
    }
    return .attack_speed
}

create_shop_menu :: proc() -> UI_Screen {
    screen := UI_Screen{
        elements = make([dynamic]^UI_Element),
    }

    // Main container
    background := create_ui_element(
        "shop_bg",
        .Panel,
        UI_Layout{
            size = {f32(window_w), f32(window_h)},
            position = {0, 0},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0.2, 0.2, 0.2, 0.9},
        },
    )

    // Content area (centers everything and provides padding)
    content := create_ui_element(
        "content",
        .Panel,
        UI_Layout{
            size = {1000, 600},  // Fixed content size
            position = {0, 0},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0, 0, 0, 0},  // Transparent
            padding = {20, 20},
        },
    )
    add_child(background, content)

    // Title
    title := create_ui_element(
        "title",
        .Text,
        UI_Layout{
            size = {200, 50},
            position = {0, 250},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            text_color = {1, 1, 1, 1},
            text_scale = 1.2,
        },
    )
    title.text = "Shop"
    add_child(content, title)

    // Currency
    currency := create_ui_element(
        "currency",
        .Text,
        UI_Layout{
            size = {200, 30},
            position = {450, 250},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            text_color = {1, 1, 1, 1},
            text_scale = 0.7,
        },
    )
    currency.text = fmt.tprintf("Currency: %d", app_state.game.currency_points)
    add_child(content, currency)

    // Grid layout
    column_count := 2
    items_per_column := (len(Upgrade_Kind) + column_count - 1) / column_count
    cell_width := 400
    cell_height := 100
    start_x := -200
    start_y := 150

    for upgrade, i in Upgrade_Kind {
        column := i / items_per_column
        row := i % items_per_column

        x_pos := start_x + column * cell_width
        y_pos := start_y - row * cell_height

        // Upgrade group
        group := create_ui_element(
            fmt.tprintf("group_%v", upgrade),
            .Panel,
            UI_Layout{
                size = {350, 80},
                position = {f32(x_pos), f32(y_pos)},
                anchor = {0.5, 0.5},
                pivot = {0.5, 0.5},
            },
            UI_Style{
                background_color = {0.3, 0.3, 0.3, 0.5},
                padding = {10, 10},
            },
        )

        // Add group elements...
        // (Rest of your group element creation code remains the same)

        add_child(content, group)
    }

    // Back button
    back_button := create_ui_element(
        "back",
        .Button,
        UI_Layout{
            size = {120, 40},
            position = {0, -250},
            anchor = {0.5, 0.5},
            pivot = {0.5, 0.5},
        },
        UI_Style{
            background_color = {0.2, 0.3, 0.8, 1.0},
            text_color = {1, 1, 1, 1},
            text_scale = 0.5,
        },
    )
    back_button.text = "Back"
    back_button.on_click = proc(element: ^UI_Element) {
        app_state.game.state_kind = .PLAYING
    }
    add_child(content, back_button)

    append(&screen.elements, background)
    return screen
}

init_shop_menu :: proc(gs: ^Game_State) {
    screen := create_shop_menu()
    defer cleanup_screen(&screen)

    ui_state.screens["shop"] = screen
    ui_state.active_screen = "shop"
    draw_ui(&ui_state)
}

cleanup_screen :: proc(screen: ^UI_Screen) {
    for element in screen.elements {
        cleanup_element(element)
    }
    delete(screen.elements)
}

draw_game_over_screen :: proc(gs: ^Game_State){
	draw_rect_aabb(v2{-2000, -2000}, v2{4000, 4000}, col = v4{0.0, 0.0, 0.0, 0.7})

	title_pos := v2{-200, 100}
	draw_text(title_pos, "Game Over!", scale = 3.0)

	wave_text_pos := v2{-150, 0}
	wave_text := fmt.tprintf("Waves Completed %d", gs.wave_number - 1)
	draw_text(wave_text_pos, wave_text, scale = 2.0)

	menu_button := make_centered_screen_button(
	   -100,
	   MENU_BUTTON_WIDTH,
	   MENU_BUTTON_HEIGHT,
	   "Main Menu",
	)

	if draw_screen_button(menu_button){
	   gs.state_kind = .MENU
	}
}

draw_wave_button :: proc(gs: ^Game_State){
    button_pos := v2{0, 0}

    #partial switch gs.wave_status {
        case .WAITING:
            button := make_centered_screen_button(
                500,
                WAVE_BUTTON_WIDTH,
                WAVE_BUTTON_HEIGHT,
                fmt.tprintf("Start Wave %d", gs.wave_number),
                v4{0.2, 0.6, 0.2, 1.0},
                0,
                0.4,
            )
            if draw_screen_button(button) {
                gs.wave_status = .IN_PROGRESS
            }
        case .COMPLETED:
            button := make_centered_screen_button(
                500,
                WAVE_BUTTON_WIDTH,
                WAVE_BUTTON_HEIGHT,
                fmt.tprintf("Start Wave %d", gs.wave_number + 1),
                v4{0.2, 0.6, 0.2, 1.0},
                0,
                0.4,
            )

            if draw_screen_button(button){
                init_wave(gs, gs.wave_number + 1)
                gs.wave_status = .IN_PROGRESS
            }
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

	button := make_centered_screen_button(
		20,
		SKILLS_BUTTON_WIDTH,
		SKILLS_BUTTON_HEIGHT,
		"Skills",
		x_offset = (SKILLS_BUTTON_WIDTH + PAUSE_MENU_SPACING),
		color = v4{0.5, 0.1, 0.8, 1.0},
		text_scale = 0.4
	)

    if draw_screen_button(button){
        gs.state_kind = .SKILLS
    }
}

draw_shop_button :: proc(gs: ^Game_State){
	shop_button := make_centered_screen_button(
		20,
		SKILLS_BUTTON_WIDTH,
		SKILLS_BUTTON_HEIGHT,
		"Shop",
		x_offset = 0,
		color = v4{0.5, 0.1, 0.8, 1.0},
		text_scale = 0.4
	)

	if draw_screen_button(shop_button) {
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

    quest_button := make_centered_screen_button(
        20,
        QUEST_BUTTON_WIDTH,
        QUEST_BUTTON_HEIGHT,
        "Quests",
        x_offset = -(QUEST_BUTTON_WIDTH + PAUSE_MENU_SPACING),
        color = button_color,
        text_scale = 0.4
    )

    if draw_screen_button(quest_button) && has_available_quests {
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

        screen_bounds := world_to_screen_bounds(entry_bounds)
        mouse_pos := window_to_screen(app_state.input_state.mouse_pos)
        if aabb_contains(screen_bounds, mouse_pos) && key_just_pressed(app_state.input_state, .LEFT_MOUSE) {
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

        scroll_percentage := 1.0 - (gs.skills_scroll_offset / max_scroll)
        thumb_pos := scrollbar_bounds.y + scroll_percentage * (scroll_height - thumb_height)

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

    back_button := make_centered_screen_button(
        config.skills_back_button_y,
        config.pause_menu_button_width,
        config.pause_menu_button_height,
        "Back",
        x_offset = config.skills_back_button_x,
    )

    if draw_screen_button(back_button) {
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

    title_pos := v2{panel_bounds.x + config.quest_title_offset_x, panel_bounds.w - config.quest_title_offset_y}
    draw_text(title_pos, "Quests", scale = f64(config.quest_title_scale))

    currency_pos := v2{panel_bounds.z - config.quest_currency_offset_x, panel_bounds.w - config.quest_currency_offset_y}
    draw_text(currency_pos, fmt.tprintf("Currency: %d", gs.currency_points), scale = f64(config.quest_currency_scale))

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

            screen_bounds := world_to_screen_bounds(entry_bounds)
            mouse_pos := window_to_screen(app_state.input_state.mouse_pos)
            if aabb_contains(screen_bounds, mouse_pos) && key_just_pressed(app_state.input_state, .LEFT_MOUSE) {
                handle_quest_click(gs, kind)
            }

            current_y -= config.quest_entry_height + config.quest_entry_padding
        }

        if category_has_quests {
            current_y -= config.quest_category_bottom_spacing
        }
    }

    if total_content_height > visible_height {
        scrollbar_bounds := AABB{
            panel_bounds.z - config.quest_scrollbar_width - config.quest_scrollbar_offset_right,
            panel_bounds.y + config.quest_scrollbar_padding_y,
            panel_bounds.z - config.quest_scrollbar_offset_right,
            panel_bounds.w - config.quest_scrollbar_padding_y,
        }

        scroll_height := scrollbar_bounds.w - scrollbar_bounds.y
        thumb_height := (visible_height / total_content_height) * scroll_height

        scroll_percentage := 1.0 - (gs.quest_scroll_offset / max_scroll)
        thumb_pos := scrollbar_bounds.y + scroll_percentage * (scroll_height - thumb_height)

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

    back_button := make_centered_screen_button(
        config.skills_back_button_y,
        config.pause_menu_button_width,
        config.pause_menu_button_height,
        "Back",
        x_offset = config.skills_back_button_x,
    )

    if draw_screen_button(back_button) {
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

get_window_scale :: proc() -> Vector2{
    return Vector2{
        f32(sapp.width()) / f32(window_w),
        f32(sapp.height()) / f32(window_h),
    }
}

window_to_screen :: proc(window_pos: Vector2) -> Vector2{
    scale := get_window_scale()
    return Vector2{
        window_pos.x / scale.x,
        window_pos.y / scale.y,
    }
}

screen_to_ndc :: proc(screen_pos: Vector2) -> Vector2{
    return Vector2{
        (2.0 * screen_pos.x / f32(window_w)) - 1.0,
        -((2.0 * screen_pos.y / f32(window_h)) -1.0),
    }
}

make_screen_button :: proc(
    screen_x: f32,
    screen_y: f32,
    width: f32,
    height: f32,
    text: string,
    color := v4{0.2, 0.3, 0.8, 1.0},
    text_scale := f32(0.5),
) -> Screen_Button {
    screen_bounds := AABB{
        screen_x,
        screen_y,
        screen_x + width,
        screen_y + height,
    }

    bl := screen_to_ndc(Vector2{screen_bounds.x, screen_bounds.y + height})
    tr := screen_to_ndc(Vector2{screen_bounds.z, screen_bounds.y})

    world_bounds := AABB{
        bl.x * game_res_w * 0.5,
        bl.y * game_res_h * 0.5,
        tr.x * game_res_w * 0.5,
        tr.y * game_res_h * 0.5,
    }

    return Screen_Button{
        screen_bounds = screen_bounds,
        world_bounds = world_bounds,
        text = text,
        text_scale = text_scale,
        color = color,
    }
}

draw_screen_button :: proc(button: Screen_Button) -> bool {
    mouse_pos := window_to_screen(app_state.input_state.mouse_pos)
    is_hovered := aabb_contains(button.screen_bounds, mouse_pos)
    is_clicked := is_hovered && key_just_pressed(app_state.input_state, .LEFT_MOUSE)

    if is_clicked {
        play_sound("button_click")
    }

    color := button.color
    if is_hovered {
        color.xyz *= 1.2
    }

    draw_rect_aabb(
        v2{button.world_bounds.x, button.world_bounds.y},
        v2{button.world_bounds.z - button.world_bounds.x, button.world_bounds.w - button.world_bounds.y},
        col = color,
    )

    text_width := f32(len(button.text)) * 8 * button.text_scale
    text_height := 16 * button.text_scale

    text_pos := v2{
        button.world_bounds.x + (button.world_bounds.z - button.world_bounds.x - text_width) * 0.5,
        button.world_bounds.y + (button.world_bounds.w - button.world_bounds.y - text_height) * 0.5,
    }

    draw_text(text_pos, button.text, scale = auto_cast button.text_scale)

    return is_clicked
}

make_centered_screen_button :: proc(
    y_pos: f32,
    width: f32,
    height: f32,
    text: string,
    color := v4{0.2, 0.3, 0.8, 1.0},
    x_offset := f32(0),
    text_scale := f32(0.5),
) -> Screen_Button {
    screen_x := (f32(window_w) - width) * 0.5 + x_offset
    return make_screen_button(
        screen_x,
        y_pos - height * 0.5,
        width,
        height,
        text,
        color,
        text_scale,
    )
}

world_to_screen_bounds :: proc(world_bounds: AABB) -> AABB {
    ndc_x := world_bounds.x / (game_res_w * 0.5)
    ndc_y := world_bounds.y / (game_res_h * 0.5)
    ndc_z := world_bounds.z / (game_res_w * 0.5)
    ndc_w := world_bounds.w / (game_res_h * 0.5)

    return AABB{
        (ndc_x + 1.0) * f32(window_w) * 0.5,
        (-ndc_w + 1.0) * f32(window_h) * 0.5,
        (ndc_z + 1.0) * f32(window_w) * 0.5,
        (-ndc_y + 1.0) * f32(window_h) * 0.5,
    }
}