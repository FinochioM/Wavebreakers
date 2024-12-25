package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:strings"
import t "core:time"

import sapp "../sokol/app"
import sg "../sokol/gfx"
import sglue "../sokol/glue"
import slog "../sokol/log"

import stbi "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"
import stbtt "vendor:stb/truetype"

import fcore "fmod/core"
import fstudio "fmod/studio"
import fsbank "fmod/fsbank"

window_w: i32 = 1280
window_h: i32 = 720

last_time: t.Time
accumulator: f64
sims_per_second :: 1.0 / 30.0

last_sim_time: f64 = 0.0

main :: proc() {
	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			cleanup_cb = cleanup,
			event_cb = event,
			width = window_w,
			height = window_h,
			window_title = "WaveBreakers",
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}

init :: proc "c" () {
	initialize()
}

frame :: proc "c" () {
	frame_init()
}

cleanup :: proc "c" () {
	context = runtime.default_context()
	sg.shutdown()
}


//
// :GAME

// :tile

WORLD_W :: 512
WORLD_H :: 256

Tile_Pos :: [2]int

get_tile :: proc(gs: Game_State, tile_pos: Tile_Pos) -> Tile {
	local := world_tile_to_array_tile_pos(tile_pos)

	if local.x < 0 || local.x >= WORLD_W || local.y < 0 || local.y >= WORLD_H {
		return Tile{}
	}

	return gs.tiles[local.x + local.y * WORLD_W]
}
get_tile_pointer :: proc(gs: ^Game_State, tile_pos: Tile_Pos) -> ^Tile {
	local := world_tile_to_array_tile_pos(tile_pos)
	return &gs.tiles[local.x + local.y * WORLD_W]
}

get_tiles_in_box_radius :: proc(world_pos: Vector2, box_radius: Vector2i) -> []Tile_Pos {

	tiles: [dynamic]Tile_Pos
	tiles.allocator = context.temp_allocator

	tile_pos := world_pos_to_tile_pos(world_pos)

	for x := tile_pos.x - box_radius.x; x < tile_pos.x + box_radius.x; x += 1 {
		for y := tile_pos.y - box_radius.y; y < tile_pos.y + box_radius.y; y += 1 {
			append(&tiles, (Tile_Pos){x, y})
		}
	}

	return tiles[:]
}

// :tile load
load_map_into_tiles :: proc(tiles: []Tile) {
	stbi.set_flip_vertically_on_load(1)
	png_data, succ := os.read_entire_file("./res/map.png")
	if !succ {
		fmt.println("Failed to load map image")
		return
	}

	width, height, channels: i32
	img_data: [^]byte = stbi.load_from_memory(
		raw_data(png_data),
		auto_cast len(png_data),
		&width,
		&height,
		&channels,
		4,
	)

	if img_data == nil {
		fmt.println("Failed to decode map image")
		return
	}

	for x in 0 ..< WORLD_W {
		for y in 0 ..< WORLD_H {
			index := (x + y * WORLD_W) * 4
			pixel: []u8 = img_data[index:index + 4]

			t := &tiles[x + y * WORLD_W]
			t.color = {
				f32(pixel[0]) / 255.0,
				f32(pixel[1]) / 255.0,
				f32(pixel[2]) / 255.0,
				f32(pixel[3]) / 255.0,
			}
		}
	}

	stbi.image_free(img_data)
}

world_tile_to_array_tile_pos :: proc(world_tile: Tile_Pos) -> Vector2i {
	x_index := world_tile.x + int(math.floor(f32(WORLD_W * 0.5)))
	y_index := world_tile.y + int(math.floor(f32(WORLD_H * 0.5)))
	return {x_index, y_index}
}

array_tile_pos_to_world_tile :: proc(x: int, y: int) -> Tile_Pos {
	x_index := x - int(math.floor(f32(WORLD_W * 0.5)))
	y_index := y - int(math.floor(f32(WORLD_H * 0.5)))
	return (Tile_Pos){x_index, y_index}
}

TILE_LENGTH :: 16

tile_pos_to_world_pos :: proc(tile_pos: Tile_Pos) -> Vector2 {
	return (Vector2){auto_cast tile_pos.x * TILE_LENGTH, auto_cast tile_pos.y * TILE_LENGTH}
}

world_pos_to_tile_pos :: proc(world_pos: Vector2) -> Tile_Pos {
	return (Tile_Pos) {
		auto_cast math.floor(world_pos.x / TILE_LENGTH),
		auto_cast math.floor(world_pos.y / TILE_LENGTH),
	}
}

// :tile
draw_tiles :: proc(gs: ^Game_State, player: Entity) {
	map_width := WORLD_W * TILE_LENGTH
	map_height := WORLD_H * TILE_LENGTH

	start_x := -map_width / 2
	start_y := -map_height / 2

	for x := 0; x < WORLD_W; x += 1 {
		for y := 0; y < WORLD_H; y += 1 {
			tile := gs.tiles[x + y * WORLD_W]
			pos := v2{auto_cast (start_x + x * TILE_LENGTH), auto_cast (start_y + y * TILE_LENGTH)}

			if pos.x >= -4096 && pos.x <= 4096 && pos.y >= -2048 && pos.y <= 2048 {
				if tile.color.w > 0 {
					draw_rect_aabb(pos, v2{TILE_LENGTH, TILE_LENGTH}, col = tile.color)
				}
			}
		}
	}
}

first_time_init_game_state :: proc(gs: ^Game_State) {
	gs.state_kind = .MENU
	gs.wave_status = .WAITING

	gs.floating_texts = make([dynamic]Floating_Text)
	gs.floating_texts.allocator = context.allocator


	gs.wave_config = init_wave_config()
	load_map_into_tiles(gs.tiles[:])

	init_game_systems(gs)
}

init_game_systems :: proc(gs: ^Game_State) {
	init_skills(gs)
	init_quests(gs)
}

//
// :ENTITY

EXPERIENCE_PER_LEVEL :: 100 // Might add something here to not have a fixed amount.
EXPERIENCE_PER_ENEMY :: 3
POINTS_PER_ENEMY :: 1

Entity_Handle :: u64

Upgrade_Kind :: enum {
	attack_speed,
	accuracy,
	damage,
	armor,
	life_steal,
	exp_gain,
	crit_chance,
	crit_damage,
	multishot,
	health_regen,
	dodge_chance,
	fov_range,
}

UPGRADE_BASE_COST :: 5
UPGRADE_COST_INCREMENT :: 3
MAX_UPGRADE_LEVEL :: 10

ATTACK_SPEED_BONUS_PER_LEVEL :: 0.1
ACCURACY_BONUS_PER_LEVEL :: 0.1
DAMAGE_BONUS_PER_LEVEL :: 0.15
ARMOR_BONUS_PER_LEVEL :: 0.1
LIFE_STEAL_PER_LEVEL :: 0.075
EXP_GAIN_BONUS_PER_LEVEL :: 0.1
CRIT_CHANCE_PER_LEVEL :: 0.05
CRIT_DAMAGE_PER_LEVEL :: 0.1
MULTISHOT_CHANCE_PER_LEVEL :: 0.075
DODGE_CHANCE_PER_LEVEL :: 0.03
FOV_RANGE_BONUS_PER_LEVEL :: 50.0
HEALTH_REGEN_PER_LEVEL :: 0.9

FIRST_BOSS_WAVE :: 10
BOSS_STATS_MULTIPLIER :: 5.0

handle_to_entity :: proc(gs: ^Game_State, handle: Entity_Handle) -> ^Entity {
	for &en in gs.entities {
		if (.allocated in en.flags) && en.id == handle {
			return &en
		}
	}
	log_error("entity no longer valid")
	return nil
}

entity_to_handle :: proc(gs: Game_State, entity: Entity) -> Entity_Handle {
	return entity.id
}

entity_create :: proc(gs: ^Game_State) -> ^Entity {
	spare_en: ^Entity
	for &en in gs.entities {
		if !(.allocated in en.flags) {
			spare_en = &en
			break
		}
	}

	if spare_en == nil {
		log_error("ran out of entities, increase size")
		return nil
	} else {
		spare_en.flags = {.allocated}
		gs.latest_entity_handle += 1
		spare_en.id = gs.latest_entity_handle
		return spare_en
	}
}

entity_destroy :: proc(gs: ^Game_State, entity: ^Entity) {
	if entity == nil do return
	entity.flags = {}
	mem.set(entity, 0, size_of(Entity))
}

setup_player :: proc(e: ^Entity) {
	e.kind = .player
	e.flags |= {.allocated}

	e.pos = v2{-900, -550}
	e.animations = create_animation_collection()

	idle_frames: []Image_Id = {
		.player_idle1,
		.player_idle2,
		.player_idle3,
		.player_idle4,
		.player_idle5,
		.player_idle6,
		.player_idle7,
		.player_idle8,
	}
	idle_anim := create_animation(idle_frames, 0.1, true, "idle")

	shoot_frames: []Image_Id = {
		.player_attack1,
		.player_attack2,
		.player_attack3,
		.player_attack4,
		.player_attack5,
		.player_attack6,
		.player_attack7,
		.player_attack8,
	}
	shoot_anim := create_animation(shoot_frames, 0.1, false, "attack")

	add_animation(&e.animations, shoot_anim)
	add_animation(&e.animations, idle_anim)
	play_animation_by_name(&e.animations, "idle")

	if app_state.game.active_quest != nil && app_state.game.active_quest.? == .Risk_Reward {
		current_health := e.health
		current_damage := e.damage
		e.health = current_health / 2
		e.max_health = e.max_health / 2
		e.damage = current_damage * 2
	} else {
		e.health = 50
		e.max_health = 100
		e.damage = 10
	}
	e.attack_speed = 1.0
	e.attack_timer = 0.0
	e.upgrade_levels = {}
	e.health_regen_timer = 0
	e.current_fov_range = FOV_RANGE
}

setup_enemy :: proc(e: ^Entity, pos: Vector2, difficulty: f32) {
	e.kind = .enemy
	e.flags |= {.allocated}

	is_boss_wave := app_state.game.wave_number % 10 == 0
	is_first_boss := app_state.game.wave_number == FIRST_BOSS_WAVE
	wave_num := app_state.game.wave_number

	e.animations = create_animation_collection()

	if is_boss_wave {
		switch wave_num {
		case 10:
			e.enemy_type = 10
			e.value = 50
			draw_sprite(pos, .boss10, pivot = .bottom_center)
		case 20:
			e.enemy_type = 20
			e.value = 100
			draw_sprite(pos, .boss20, pivot = .bottom_center)
		}
	} else {
		if wave_num <= 10 {
			e.enemy_type = 1
			enemy_move_frames: []Image_Id = {
				.enemy1_10_1_move,
				.enemy1_10_2_move,
				.enemy1_10_3_move,
				.enemy1_10_4_move,
				.enemy1_10_5_move,
				.enemy1_10_6_move,
				.enemy1_10_7_move,
				.enemy1_10_8_move,
			}
			enemy_move_anim := create_animation(enemy_move_frames, 0.1, true, "enemy1_10_move")
			enemy_attack_frames: []Image_Id = {
				.enemy1_10_1_attack,
				.enemy1_10_2_attack,
				.enemy1_10_3_attack,
				.enemy1_10_4_attack,
				.enemy1_10_5_attack,
				.enemy1_10_6_attack,
				.enemy1_10_7_attack,
				.enemy1_10_8_attack,
			}
			enemy_attack_anim := create_animation(
				enemy_attack_frames,
				0.1,
				true,
				"enemy1_10_attack",
			)

			add_animation(&e.animations, enemy_move_anim)
			add_animation(&e.animations, enemy_attack_anim)
		} else if wave_num <= 20 {
			e.enemy_type = 2
			enemy2_move_frames: []Image_Id = {
				.enemy11_19_1_move,
				.enemy11_19_2_move,
				.enemy11_19_3_move,
				.enemy11_19_4_move,
				.enemy11_19_5_move,
				.enemy11_19_6_move,
				.enemy11_19_7_move,
				.enemy11_19_8_move,
			}
			enemy2_move_anim := create_animation(enemy2_move_frames, 0.1, true, "enemy11_19_move")

			add_animation(&e.animations, enemy2_move_anim)
		}

		e.value = e.enemy_type * 2
	}

	play_animation_by_name(&e.animations, wave_num <= 10 ? "enemy1_10_move" : "enemy11_19_move")

	base_health := 15 + (e.enemy_type - 1) * 10
	base_damage := 5 + (e.enemy_type - 1) * 3
	base_speed := 100.0 - f32(e.enemy_type - 1) * 10.0

	config := app_state.game.wave_config
	wave_num_32 := f32(app_state.game.wave_number)

	health_mult := 1.0 + (config.health_scale * wave_num_32)
	damage_mult := 1.0 + (config.damage_scale * wave_num_32)
	speed_mult := 1.0 + (config.speed_scale * wave_num_32)

	if is_boss_wave {
		health_mult *= BOSS_STATS_MULTIPLIER
		damage_mult *= BOSS_STATS_MULTIPLIER
		speed_mult *= 0.5
	}

	e.pos = pos
	e.prev_pos = pos
	e.health = int(f32(base_health) * health_mult * difficulty)
	e.max_health = e.health
	e.attack_timer = 0.0
	e.damage = int(f32(base_damage) * damage_mult * difficulty)
	e.state = .moving
	e.speed = f32(base_speed) * speed_mult
}

calculate_exp_for_level :: proc(level: int) -> int {
	return int(EXPERIENCE_PER_LEVEL * math.pow(1.2, f32(level - 1)))
}

add_experience :: proc(gs: ^Game_State, player: ^Entity, exp_amount: int) {
	multiplier := 1.0

	if gs.active_quest != nil {
		quest := &gs.quests[gs.active_quest.?]
		multiplier = f64(quest.effects.experience_mult)
	}

	final_exp := int(f32(exp_amount) * f32(multiplier))
	fmt.println(final_exp)
	exp_text := fmt.tprintf("+%d exp", final_exp)
	spawn_floating_text(gs, player.pos, exp_text, v4{0.3, 0.8, 0.3, 1.0})

	player.experience += final_exp
	exp_needed := calculate_exp_for_level(player.level)

	for player.experience >= exp_needed {
		player.experience -= exp_needed
		player.level += 1
		exp_needed = calculate_exp_for_level(player.level)
		check_quest_unlocks(gs, player)
	}
}

add_currency_points :: proc(gs: ^Game_State, points: int) {
	multiplier := 1.0

	if gs.active_quest != nil {
		quest := &gs.quests[gs.active_quest.?]
		multiplier = f64(quest.effects.currency_mult)
	}

	gs.currency_points += int(f32(points) * f32(multiplier))
}

//
// THE GAMEPLAY LINE
//

//
// :sim

FOV_RANGE :: 1200.0 // Range in which the player can detect enemies

start_new_game :: proc(gs: ^Game_State) {
	for &en in gs.entities {
		if .allocated in en.flags {
			entity_destroy(gs, &en)
		}
	}

	for text in &gs.floating_texts {
		delete(text.text)
	}
	clear(&gs.floating_texts)

	gs.wave_number = 0
	gs.enemies_to_spawn = 0
	gs.currency_points = 10000
	gs.player_level = 0
	gs.player_experience = 0

	init_game_systems(gs)

	e := entity_create(gs)
	if e != nil {
		setup_player(e)
	}
}

handle_input :: proc(gs: ^Game_State) {
	mouse_pos := screen_to_world_pos(app_state.input_state.mouse_pos)

	#partial switch gs.state_kind {
	case .MENU:
	// Does nothing now.
	case .PLAYING:
		if key_just_pressed(app_state.input_state, .ESCAPE) {
			gs.state_kind = .PAUSED
		}

		if key_just_pressed(app_state.input_state, .L) {
			player := find_player(gs)
			if player != nil {
				for i in 0 ..< 5 {
					player.level += 1
				}
				check_quest_unlocks(gs, player)

				spawn_floating_text(gs, player.pos, "DEBUG: Added 5 levels!", v4{1, 1, 0, 1})
			}
		}
	case .PAUSED:
		if key_just_pressed(app_state.input_state, .ESCAPE) {
			gs.state_kind = .PLAYING
		}

		resume_button := AABB {
			-PAUSE_MENU_BUTTON_WIDTH * 0.5,
			PAUSE_MENU_SPACING,
			PAUSE_MENU_BUTTON_WIDTH * 0.5,
			PAUSE_MENU_BUTTON_HEIGHT + PAUSE_MENU_SPACING,
		}

		menu_button := AABB {
			-PAUSE_MENU_BUTTON_WIDTH * 0.5,
			-PAUSE_MENU_BUTTON_HEIGHT - PAUSE_MENU_SPACING,
			PAUSE_MENU_BUTTON_WIDTH * 0.5,
			-PAUSE_MENU_SPACING,
		}

		if key_just_pressed(app_state.input_state, .LEFT_MOUSE) {
			if aabb_contains(resume_button, mouse_pos) {
				gs.state_kind = .PLAYING
			} else if aabb_contains(menu_button, mouse_pos) {
				gs.state_kind = .MENU
			}
		}
	}
}

update_gameplay :: proc(gs: ^Game_State, delta_t: f64) {
	defer gs.tick_index += 1

	#partial switch gs.state_kind {
	case .PLAYING, .SKILLS, .QUESTS:
		update_quest_progress(gs)
		i := 0
		for i < len(gs.floating_texts) {
			text := &gs.floating_texts[i]
			text.lifetime -= f32(delta_t)
			text.pos += text.velocity * f32(delta_t) * 100.0

			if text.lifetime <= 0 {
				delete(text.text)
				ordered_remove(&gs.floating_texts, i)
			} else {
				i += 1
			}
		}

		for &en in gs.entities {
			en.frame = {}
		}

		for &en in gs.entities {
			if en.kind == .player {
				if en.health <= 0 {
					gs.state_kind = .GAME_OVER
				}

				check_skill_unlock(gs, &en)

				en.health_regen_timer -= f32(delta_t)
				if en.health_regen_timer <= 0 {
					if en.upgrade_levels.health_regen > 0 {
						heal_player(&en, 1)

						base_regen_time := 10.0
						level_reduction :=
							f32(en.upgrade_levels.health_regen) * HEALTH_REGEN_PER_LEVEL
						actual_regen_time := math.max(f32(base_regen_time) - level_reduction, 1.0)

						en.health_regen_timer = actual_regen_time
					} else {
						en.health_regen_timer = 10.0
					}
				}

				en.attack_timer -= f32(delta_t)

				targets := find_enemies_in_range(gs, en.pos, FOV_RANGE)

				if en.attack_timer <= 0 && len(targets) > 0 {
					play_animation_by_name(&en.animations, "attack")

					if anim, ok := &en.animations.animations["attack"]; ok {
						adjust_animation_to_speed(anim, en.attack_speed)
					}

					if should_spawn_projectile(&en) && len(targets) > 0 {
						closest_enemy := targets[0].entity
						projectile := entity_create(gs)
						if projectile != nil {
							setup_projectile(gs, projectile, en.pos, closest_enemy.pos)
							play_sound("shoot")
						}
						en.attack_timer = 1.0 / en.attack_speed
					}
				}

			}
			if en.kind == .enemy {
				process_enemy_behaviour(&en, gs, f32(delta_t))
			}
			if en.kind == .player_projectile {
				SUB_STEPS :: 4
				dt := f32(delta_t) / f32(SUB_STEPS)

				en.prev_pos = en.pos

				for step in 0 ..< SUB_STEPS {
					if !(.allocated in en.flags) do break

					en.direction.y -= PROJECTILE_GRAVITY * dt

					movement := v2{en.direction.x * dt, en.direction.y * dt}
					new_pos := en.pos + movement

					for &target in gs.entities {
						if target.kind != .enemy do continue
						if !(.allocated in target.flags) do continue

						dist := linalg.length(target.pos - en.pos)
						collision_radius := target.enemy_type == 10 ? 200.0 : 100
						if auto_cast dist <= collision_radius {
							when_projectile_hits_enemy(gs, &en, &target)
							entity_destroy(gs, &en)
							break
						}
					}

					if .allocated in en.flags {
						en.pos = new_pos

						if linalg.length(en.pos) > 2000 || en.pos.y < -1000 {
							entity_destroy(gs, &en)
						}
					}
				}
			}
		}

		if gs.wave_number == 0 {
			init_wave(gs, 1)
		}

		process_wave(gs, delta_t)

		for &en in gs.entities {
			if .allocated in en.flags {
				update_current_animation(&en.animations, f32(delta_t))
			}
		}
	}
}

//
// :render

render_gameplay :: proc(gs: ^Game_State, input_state: Input_State) {
	using linalg
	player: Entity

	map_width := f32(WORLD_W * TILE_LENGTH)
	map_height := f32(WORLD_H * TILE_LENGTH)

	draw_frame.projection = matrix_ortho3d_f32(
		-map_width * 0.5,
		map_width * 0.5,
		-map_height * 0.5,
		map_height * 0.5,
		-1,
		1,
	)

	draw_frame.camera_xform = Matrix4(1)

	alpha := f32(accumulator) / f32(sims_per_second)

	#partial switch gs.state_kind {
	case .MENU:
		draw_menu(gs)
	case .PLAYING:
		for en in gs.entities {
			if en.kind == .player {
				player = en
				break
			}
		}

		draw_tiles(gs, player)

		for &en in gs.entities {
			#partial switch en.kind {
			case .player:
				draw_player(&en)
			case .enemy, .player_projectile:
				render_pos := linalg.lerp(en.prev_pos, en.pos, alpha)

				if en.kind == .enemy {
					draw_enemy_at_pos(&en, render_pos)
				} else if en.kind == .player_projectile {
					draw_player_projectile_at_pos(en, render_pos)
				}
			}
		}

		for &en in gs.entities {
			if en.kind == .player {
				ui_base_pos := v2{-1000, 600}

				exp_needed := calculate_exp_for_level(en.level)
				current_exp := en.experience
				level_text := fmt.tprintf(
					"Current Level: %d - (%d/%d)",
					en.level,
					current_exp,
					exp_needed,
				)
				draw_text(ui_base_pos, level_text, scale = 2.0)

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -50}, currency_text, scale = 2.0)

				health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
				draw_text(ui_base_pos + v2{0, -100}, health_text, scale = 2.0)

				enemies_remaining_text := fmt.tprintf(
					"Enemies: %d/%d",
					gs.active_enemies,
					gs.enemies_to_spawn,
				)
				draw_text(ui_base_pos + v2{0, -150}, enemies_remaining_text, scale = 2.0)
				break
			}
		}

		draw_wave_button(gs)
		draw_skills_button(gs)
		draw_shop_button(gs)
		draw_quest_button(gs)

		for text in gs.floating_texts {
			text_alpha := text.lifetime / text.max_lifetime
			color := text.color
			color.w = text_alpha
			draw_text(text.pos, text.text, scale = 1.5, color = color)
		}
	case .PAUSED:
		draw_tiles(gs, player)
		for &en in gs.entities {
			#partial switch en.kind {
			case .player:
				draw_player(&en)
			case .enemy, .player_projectile:
				render_pos := linalg.lerp(en.prev_pos, en.pos, alpha)

				if en.kind == .enemy {
					draw_enemy_at_pos(&en, render_pos)
				} else if en.kind == .player_projectile {
					draw_player_projectile_at_pos(en, render_pos)
				}
			}
		}

		draw_pause_menu(gs)
	case .SHOP:
		draw_shop_menu(gs)
	case .GAME_OVER:
		draw_game_over_screen(gs)
	case .QUESTS:
		for en in gs.entities {
			if en.kind == .player {
				player = en
				break
			}
		}

		draw_tiles(gs, player)

		for &en in gs.entities {
			#partial switch en.kind {
			case .player:
				draw_player(&en)
			case .enemy, .player_projectile:
				render_pos := linalg.lerp(en.prev_pos, en.pos, alpha)
				if en.kind == .enemy {
					draw_enemy_at_pos(&en, render_pos)
				} else if en.kind == .player_projectile {
					draw_player_projectile_at_pos(en, render_pos)
				}
			}
		}

		for &en in gs.entities {
			if en.kind == .player {
				ui_base_pos := v2{-1000, 600}

				exp_needed := calculate_exp_for_level(en.level)
				current_exp := en.experience
				level_text := fmt.tprintf(
					"Current Level: %d - (%d/%d)",
					en.level,
					current_exp,
					exp_needed,
				)
				draw_text(ui_base_pos, level_text, scale = 2.0)

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -50}, currency_text, scale = 2.0)

				health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
				draw_text(ui_base_pos + v2{0, -100}, health_text, scale = 2.0)

				enemies_remaining_text := fmt.tprintf(
					"Enemies: %d/%d",
					gs.active_enemies,
					gs.enemies_to_spawn,
				)
				draw_text(ui_base_pos + v2{0, -150}, enemies_remaining_text, scale = 2.0)
				break
			}
		}

		draw_skills_button(gs)
		draw_quest_button(gs)

		for text in gs.floating_texts {
			text_alpha := text.lifetime / text.max_lifetime
			color := text.color
			color.w = text_alpha
			draw_text(text.pos, text.text, scale = 1.5, color = color)
		}

		draw_quest_menu(gs)
	case .SKILLS:
		for en in gs.entities {
			if en.kind == .player {
				player = en
				break
			}
		}

		draw_tiles(gs, player)

		for &en in gs.entities {
			#partial switch en.kind {
			case .player:
				draw_player(&en)
			case .enemy, .player_projectile:
				render_pos := linalg.lerp(en.prev_pos, en.pos, alpha)

				if en.kind == .enemy {
					draw_enemy_at_pos(&en, render_pos)
				} else if en.kind == .player_projectile {
					draw_player_projectile_at_pos(en, render_pos)
				}
			}
		}

		for &en in gs.entities {
			if en.kind == .player {
				ui_base_pos := v2{-1000, 600}

				exp_needed := calculate_exp_for_level(en.level)
				current_exp := en.experience
				level_text := fmt.tprintf(
					"Current Level: %d - (%d/%d)",
					en.level,
					current_exp,
					exp_needed,
				)
				draw_text(ui_base_pos, level_text, scale = 2.0)

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -50}, currency_text, scale = 2.0)

				health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
				draw_text(ui_base_pos + v2{0, -100}, health_text, scale = 2.0)

				enemies_remaining_text := fmt.tprintf(
					"Enemies: %d/%d",
					gs.active_enemies,
					gs.enemies_to_spawn,
				)
				draw_text(ui_base_pos + v2{0, -150}, enemies_remaining_text, scale = 2.0)

				stats_pos := v2{600, 600}
				draw_debug_stats(&en, stats_pos)
				break
			}
		}

		for text in gs.floating_texts {
			text_alpha := text.lifetime / text.max_lifetime
			color := text.color
			color.w = text_alpha
			draw_text(text.pos, text.text, scale = 1.5, color = color)
		}

		draw_skills_menu(gs)
	}
}

draw_player :: proc(en: ^Entity) {
	xform := Matrix4(1)
	xform *= xform_scale(v2{3, 3})

	draw_current_animation(&en.animations, en.pos, pivot = .bottom_center, xform = xform)
}

draw_enemy_at_pos :: proc(en: ^Entity, pos: Vector2) {
	img := Image_Id.enemy1_10_1_move

	if en.enemy_type == 10 {
		img = .boss10
	} else if en.enemy_type == 20 {
		img = .boss20
	}

	xform := Matrix4(1)

	if en.enemy_type == 10 {
		xform *= xform_scale(v2{5, 5})
	} else {
		xform *= xform_scale(v2{4, 4})
	}

	draw_current_animation(&en.animations, en.pos, pivot = .bottom_center, xform = xform)
}

should_spawn_projectile :: proc(en: ^Entity) -> bool {
	if en.animations.current_animation != "attack" do return false

	if anim, ok := en.animations.animations["attack"]; ok {
		return anim.current_frame == 7
	}
	return false
}

draw_player_projectile_at_pos :: proc(en: Entity, pos: Vector2) {
	img := Image_Id.player_projectile

	angle := math.atan2(en.direction.y, en.direction.x)
	final_angle := math.to_degrees(angle)

	xform := Matrix4(1)
	xform *= xform_rotate(final_angle)
	xform *= xform_scale(v2{3, 3})

	draw_sprite(pos, img, pivot = .bottom_center, xform = xform)
}

screen_to_world_pos :: proc(screen_pos: Vector2) -> Vector2 {
	map_width := f32(WORLD_W * TILE_LENGTH)
	map_height := f32(WORLD_H * TILE_LENGTH)

	scale_x := f32(window_w) / map_width
	scale_y := f32(window_h) / map_height
	scale := min(scale_x, scale_y)

	viewport_width := map_width * scale
	viewport_height := map_height * scale
	offset_x := (f32(window_w) - viewport_width) * 0.5
	offset_y := (f32(window_h) - viewport_height) * 0.5

	adjusted_x := (screen_pos.x - offset_x) / scale
	adjusted_y := (screen_pos.y - offset_y) / scale

	world_x := adjusted_x - map_width * 0.5
	world_y := map_height * 0.5 - adjusted_y

	return Vector2{world_x, world_y}
}

//
// :COLLISION STUFF
//

AABB :: Vector4
get_aabb_from_entity :: proc(en: Entity) -> AABB {

	#partial switch en.kind {
	case .player:
		{
			return aabb_make(v2{16, 32}, .bottom_center)
		}
	}

	return {}
}

aabb_collide_aabb :: proc(a: AABB, b: AABB) -> (bool, Vector2) {
	dx := (a.z + a.x) / 2 - (b.z + b.x) / 2
	dy := (a.w + a.y) / 2 - (b.w + b.y) / 2

	overlap_x := (a.z - a.x) / 2 + (b.z - b.x) / 2 - abs(dx)
	overlap_y := (a.w - a.y) / 2 + (b.w - b.y) / 2 - abs(dy)

	if overlap_x <= 0 || overlap_y <= 0 {
		return false, Vector2{}
	}

	penetration := Vector2{}
	if overlap_x < overlap_y {
		penetration.x = overlap_x if dx > 0 else -overlap_x
	} else {
		penetration.y = overlap_y if dy > 0 else -overlap_y
	}

	return true, penetration
}

aabb_get_center :: proc(a: Vector4) -> Vector2 {
	min := a.xy
	max := a.zw
	return {min.x + 0.5 * (max.x - min.x), min.y + 0.5 * (max.y - min.y)}
}

aabb_make_with_pos :: proc(pos: Vector2, size: Vector2, pivot: Pivot) -> Vector4 {
	aabb := (Vector4){0, 0, size.x, size.y}
	aabb = aabb_shift(aabb, pos - scale_from_pivot(pivot) * size)
	return aabb
}
aabb_make_with_size :: proc(size: Vector2, pivot: Pivot) -> Vector4 {
	return aabb_make({}, size, pivot)
}

aabb_make :: proc {
	aabb_make_with_pos,
	aabb_make_with_size,
}

aabb_shift :: proc(aabb: Vector4, amount: Vector2) -> Vector4 {
	return {aabb.x + amount.x, aabb.y + amount.y, aabb.z + amount.x, aabb.w + amount.y}
}

aabb_contains :: proc(aabb: Vector4, p: Vector2) -> bool {
	return (p.x >= aabb.x) && (p.x <= aabb.z) && (p.y >= aabb.y) && (p.y <= aabb.w)
}


animate_to_target_f32 :: proc(
	value: ^f32,
	target: f32,
	delta_t: f32,
	rate: f32 = 15.0,
	good_enough: f32 = 0.001,
) -> bool {
	value^ += (target - value^) * (1.0 - math.pow_f32(2.0, -rate * delta_t))
	if almost_equals(value^, target, good_enough) {
		value^ = target
		return true // reached
	}
	return false
}

animate_to_target_v2 :: proc(value: ^Vector2, target: Vector2, delta_t: f32, rate: f32 = 15.0) {
	value.x += (target.x - value.x) * (1.0 - math.pow_f32(2.0, -rate * delta_t))
	value.y += (target.y - value.y) * (1.0 - math.pow_f32(2.0, -rate * delta_t))
}

almost_equals :: proc(a: f32, b: f32, epsilon: f32 = 0.001) -> bool {
	return abs(a - b) <= epsilon
}
//
// :upgrades

find_player :: proc(gs: ^Game_State) -> ^Entity {
	for &en in gs.entities {
		if en.kind == .player {
			return &en
		}
	}

	return nil
}

get_upgrade_level :: proc(player: ^Entity, upgrade: Upgrade_Kind) -> int {
	switch upgrade {
	case .attack_speed:
		return player.upgrade_levels.attack_speed
	case .accuracy:
		return player.upgrade_levels.accuracy
	case .damage:
		return player.upgrade_levels.damage
	case .armor:
		return player.upgrade_levels.armor
	case .life_steal:
		return player.upgrade_levels.life_steal
	case .exp_gain:
		return player.upgrade_levels.exp_gain
	case .crit_chance:
		return player.upgrade_levels.crit_chance
	case .crit_damage:
		return player.upgrade_levels.crit_damage
	case .multishot:
		return player.upgrade_levels.multishot
	case .health_regen:
		return player.upgrade_levels.health_regen
	case .dodge_chance:
		return player.upgrade_levels.dodge_chance
	case .fov_range:
		return player.upgrade_levels.fov_range
	}
	return 0
}

calculate_upgrade_cost :: proc(current_level: int) -> int {
	return UPGRADE_BASE_COST + (current_level * UPGRADE_COST_INCREMENT)
}

try_purchase_upgrade :: proc(gs: ^Game_State, player: ^Entity, upgrade: Upgrade_Kind) {
	level := get_upgrade_level(player, upgrade)
	if level >= MAX_UPGRADE_LEVEL do return

	cost := calculate_upgrade_cost(level)
	if gs.currency_points < cost do return

	gs.currency_points -= cost

	switch upgrade {
	case .attack_speed:
		player.upgrade_levels.attack_speed += 1
		player.attack_speed =
			1.0 + (f32(player.upgrade_levels.attack_speed) * ATTACK_SPEED_BONUS_PER_LEVEL)
	case .accuracy:
		player.upgrade_levels.accuracy += 1
	case .damage:
		player.upgrade_levels.damage += 1
		player.damage =
			10 +
			int(f32(player.damage) * DAMAGE_BONUS_PER_LEVEL * f32(player.upgrade_levels.damage))
	case .armor:
		player.upgrade_levels.armor += 1
		old_max_health := player.max_health
		player.max_health =
			100 + int(f32(100) * ARMOR_BONUS_PER_LEVEL * f32(player.upgrade_levels.armor))
		health_percentage := f32(player.health) / f32(old_max_health)
		player.health = int(f32(player.max_health) * health_percentage)
	case .life_steal:
		player.upgrade_levels.life_steal += 1
	case .exp_gain:
		player.upgrade_levels.exp_gain += 1
	case .crit_chance:
		player.upgrade_levels.crit_chance += 1
	case .crit_damage:
		player.upgrade_levels.crit_damage += 1
	case .multishot:
		player.upgrade_levels.multishot += 1
	case .health_regen:
		player.upgrade_levels.health_regen += 1
	case .dodge_chance:
		player.upgrade_levels.dodge_chance += 1
	case .fov_range:
		player.upgrade_levels.fov_range += 1
		player.current_fov_range =
			FOV_RANGE + (f32(player.upgrade_levels.fov_range) * FOV_RANGE_BONUS_PER_LEVEL)
	}
}

//
// : skills
SKILL_BASE_EXPERIENCE :: 100
SKILL_EXPERIENCE_SCALE :: 1.5
SKILL_BONUS_PER_LEVEL :: 0.05

init_skills :: proc(gs: ^Game_State) {
	for kind in Skill_Kind {
		gs.skills[kind] = Skill {
			kind       = kind,
			level      = 1,
			experience = 0,
			unlocked   = false,
		}
	}

	gs.active_skill = nil
}

check_skill_unlock :: proc(gs: ^Game_State, player: ^Entity) {
	if player == nil do return

	for kind in Skill_Kind {
		if gs.skills[kind].unlocked do continue

		#partial switch kind {
		case .damage:
			if player.upgrade_levels.damage >= MAX_UPGRADE_LEVEL {
				gs.skills[kind].unlocked = true
				spawn_floating_text(
					gs,
					player.pos,
					fmt.tprintf("%v skill unlocked!", kind),
					v4{0, 1, 0, 1},
				)
			}
		case .attack_speed:
			if player.upgrade_levels.attack_speed >= MAX_UPGRADE_LEVEL {
				gs.skills[kind].unlocked = true
				spawn_floating_text(
					gs,
					player.pos,
					fmt.tprintf("%v skill unlocked!", kind),
					v4{0, 1, 0, 1},
				)
			}
		case .armor:
			if player.upgrade_levels.armor >= MAX_UPGRADE_LEVEL {
				gs.skills[kind].unlocked = true
				spawn_floating_text(
					gs,
					player.pos,
					fmt.tprintf("%v skill unlocked!", kind),
					v4{0, 1, 0, 1},
				)
			}
		case .life_steal:
			if player.upgrade_levels.life_steal >= MAX_UPGRADE_LEVEL {
				gs.skills[kind].unlocked = true
				spawn_floating_text(
					gs,
					player.pos,
					fmt.tprintf("%v skill unlocked!", kind),
					v4{0, 1, 0, 1},
				)
			}
		case .crit_damage:
			if player.upgrade_levels.crit_damage >= MAX_UPGRADE_LEVEL {
				gs.skills[kind].unlocked = true
				spawn_floating_text(
					gs,
					player.pos,
					fmt.tprintf("%v skill unlocked!", kind),
					v4{0, 1, 0, 1},
				)
			}
		case .health_regen:
			if player.upgrade_levels.health_regen >= MAX_UPGRADE_LEVEL {
				gs.skills[kind].unlocked = true
				spawn_floating_text(
					gs,
					player.pos,
					fmt.tprintf("%v skill unlocked!", kind),
					v4{0, 1, 0, 1},
				)
			}
		}
	}
}

calculate_skill_experience_requirement :: proc(level: int) -> int {
	return int(f32(SKILL_BASE_EXPERIENCE) * math.pow(SKILL_EXPERIENCE_SCALE, f32(level - 1)))
}

add_skill_experience :: proc(gs: ^Game_State, exp_amount: int) {
	if gs.active_skill == nil do return

	skill := &gs.skills[gs.active_skill.?]
	skill.experience += exp_amount
	exp_needed := calculate_skill_experience_requirement(skill.level)

	for skill.experience >= exp_needed {
		skill.experience -= exp_needed
		skill.level += 1
		exp_needed = calculate_skill_experience_requirement(skill.level)

		apply_skill_bonus(gs, gs.active_skill.?)
		spawn_floating_text(
			gs,
			find_player(gs).pos,
			fmt.tprintf("%v skill level up! (%d)", skill.kind, skill.level),
			v4{1, 1, 0, 1},
		)
	}
}

apply_skill_bonus :: proc(gs: ^Game_State, kind: Skill_Kind) {
	player := find_player(gs)
	if player == nil do return

	skill := &gs.skills[kind]
	bonus := f32(skill.level) * SKILL_BONUS_PER_LEVEL

	#partial switch kind {
	case .damage:
		player.damage = int(f32(player.damage) * (1 + bonus))
	case .attack_speed:
		player.attack_speed *= (1 + bonus)
	case .armor:
		player.max_health = int(f32(player.max_health) * (1 + bonus))
		player.health = player.max_health
	case .life_steal:
	//life steal is applied in combat
	case .crit_damage:
	//crit damage is calculated in combat
	case .health_regen:
	// health regen is calculated in update
	}
}

get_skill_progress :: proc(skill: Skill) -> f32 {
	if skill.experience == 0 do return 0

	exp_needed := calculate_skill_experience_requirement(skill.level)
	return f32(skill.experience) / f32(exp_needed)
}

//
// : Quest

QUEST_INFO := map[Quest_Kind]Quest_Info {
	.Time_Dilation = {
		category = .Combat_Flow,
		unlock_level = 5,
		base_cost = 1000,
		description = "Successful hits create a local time slow effect around hit enemies",
	},
	.Chain_Reaction = {
		category = .Combat_Flow,
		unlock_level = 10,
		base_cost = 2000,
		description = "Enemies have a chance to explode on death",
	},
	.Energy_Field = {
		category = .Combat_Flow,
		unlock_level = 15,
		base_cost = 3000,
		description = "Build up charge with each hit, release automatically as an AOE pulse when full",
	},
	.Projectile_Master = {
		category = .Combat_Flow,
		unlock_level = 20,
		base_cost = 4000,
		description = "Every Nth shot splits into multiple projectiles",
	},
	.Critical_Cascade = {
		category = .Combat_Flow,
		unlock_level = 25,
		base_cost = 5000,
		description = "Critical hits have a chance to instantly reload and fire another shot",
	},
	.Gold_Fever = {
		category = .Resource_Management,
		unlock_level = 7,
		base_cost = 1500,
		description = "Enemies drop more currency but take less damage",
	},
	.Experience_Flow = {
		category = .Resource_Management,
		unlock_level = 12,
		base_cost = 2500,
		description = "Higher XP gain but reduced attack speed",
	},
	.Blood_Ritual = {
		category = .Resource_Management,
		unlock_level = 17,
		base_cost = 3500,
		description = "Much higher damage but costs health to shoot",
	},
	.Fortune_Seeker = {
		category = .Resource_Management,
		unlock_level = 22,
		base_cost = 4500,
		description = "Enemies have a chance to drop double rewards but have more health",
	},
	.Risk_Reward = {
		category = .Resource_Management,
		unlock_level = 27,
		base_cost = 5500,
		description = "Lower health pool but significantly increased damage",
	},
	.Priority_Target = {
		category = .Strategic,
		unlock_level = 9,
		base_cost = 1800,
		description = "Bonus damage to the closest enemy",
	},
	.Sniper_Protocol = {
		category = .Strategic,
		unlock_level = 14,
		base_cost = 2800,
		description = "Increased damage to distant enemies but reduced close-range damage",
	},
	.Crowd_Suppression = {
		category = .Strategic,
		unlock_level = 19,
		base_cost = 3800,
		description = "Damage increases based on number of enemies on screen",
	},
	.Elemental_Rotation = {
		category = .Strategic,
		unlock_level = 24,
		base_cost = 4800,
		description = "Shots cycle between different effects (freeze, burn, shock)",
	},
	.Defensive_Matrix = {
		category = .Strategic,
		unlock_level = 29,
		base_cost = 5800,
		description = "Create a damage-absorbing shield that converts damage to attack speed",
	},
}

init_quests :: proc(gs: ^Game_State) {
	gs.quests = make(map[Quest_Kind]Quest)

	for kind, info in QUEST_INFO {
		gs.quests[kind] = Quest {
			kind = kind,
			state = .Locked,
			progress = 0,
			max_progress = 100,
			effects = {
				damage_mult = 1.0,
				attack_speed_mult = 1.0,
				currency_mult = 1.0,
				health_mult = 1.0,
				experience_mult = 1.0,
			},
		}
	}
}

try_purchase_quest :: proc(gs: ^Game_State, kind: Quest_Kind) -> bool {
	quest := &gs.quests[kind]
	info := QUEST_INFO[kind]

	if quest.state != .Available do return false
	if gs.currency_points < info.base_cost do return false

	gs.currency_points -= info.base_cost
	quest.state = .Purchased

	spawn_floating_text(
		gs,
		player_pos(gs),
		fmt.tprintf("Quest Purchased: %v!", kind),
		v4{0.8, 0.3, 0.8, 1.0},
	)

	return true
}

check_quest_unlocks :: proc(gs: ^Game_State, player: ^Entity) {
	if player == nil do return

	for kind, info in QUEST_INFO {
		quest := &gs.quests[kind]
		if quest.state == .Locked && player.level >= info.unlock_level {
			quest.state = .Available
			spawn_floating_text(
				gs,
				player.pos,
				fmt.tprintf("New Quest Available: %v!", kind),
				v4{0.3, 0.8, 0.3, 1.0},
			)
		}
	}
}

activate_quest :: proc(gs: ^Game_State, kind: Quest_Kind) -> bool {
	if gs.active_quest != nil {
		current_quest := &gs.quests[gs.active_quest.?]
		current_quest.state = .Purchased
		remove_quest_effects(gs, current_quest)
	}

	quest := &gs.quests[kind]
	if quest.state != .Purchased do return false

	quest.state = .Active
	gs.active_quest = kind

	if kind == .Elemental_Rotation {
		player := find_player(gs)
		if player != nil {
			player.current_element = .Fire
			spawn_floating_text(
				gs,
				player.pos,
				"Elemental Rotation Active: Starting With Fire!",
				v4{1, 0.5, 0, 1},
			)
		}
	}

	apply_quest_effects(gs, quest)
	return true
}

deactivate_quest :: proc(gs: ^Game_State) {
	if gs.active_quest == nil do return

	quest := &gs.quests[gs.active_quest.?]
	quest.state = .Purchased
	remove_quest_effects(gs, quest)
	gs.active_quest = nil
}

apply_quest_effects :: proc(gs: ^Game_State, quest: ^Quest) {
	player := find_player(gs)
	if player == nil do return

	#partial switch quest.kind {
	case .Gold_Fever:
		quest.effects.currency_mult = 2.0
		quest.effects.damage_mult = 0.7
	case .Experience_Flow:
		quest.effects.experience_mult = 2.0
		quest.effects.attack_speed_mult = 0.7
	case .Blood_Ritual:
		quest.effects.damage_mult = 2.0
		quest.effects.health_mult = 0.7
	case .Risk_Reward:
		quest.effects.damage_mult = 2.0
		quest.effects.health_mult = 0.5
	case .Time_Dilation:
		quest.effects.attack_speed_mult = 0.8
		quest.effects.damage_mult = 1.1
	case .Chain_Reaction:
		// Chain reaction is handled in when_enemy_dies
		quest.effects.damage_mult = 1.2
	case .Energy_Field:
		// Energy field will be handled in when_projectile_hits_enemy
		quest.effects.damage_mult = 1.3
	case .Projectile_Master:
		quest.effects.damage_mult = 0.8 // Lower damage since we'll fire more projectiles
	case .Critical_Cascade:
		quest.effects.attack_speed_mult = 1.2
		quest.effects.damage_mult = 1.2
	case .Priority_Target:
		quest.effects.damage_mult = 1.4
	case .Sniper_Protocol:
		quest.effects.damage_mult = 1.5
		quest.effects.attack_speed_mult = 0.8
	case .Crowd_Suppression:
		quest.effects.damage_mult = 1.0 // Base damage, will increase with enemy count
	case .Elemental_Rotation:
		quest.effects.damage_mult = 1.3
	case .Defensive_Matrix:
		quest.effects.health_mult = 1.5
		quest.effects.attack_speed_mult = 1.2
	case .Fortune_Seeker:
		quest.effects.currency_mult = 1.5
		quest.effects.experience_mult = 1.5
		quest.effects.damage_mult = 0.8
	}

	player.damage = int(f32(player.damage) * quest.effects.damage_mult)
	player.attack_speed *= quest.effects.attack_speed_mult
	player.max_health = int(f32(player.max_health) * quest.effects.health_mult)
	player.health = min(player.health, player.max_health)
}

remove_quest_effects :: proc(gs: ^Game_State, quest: ^Quest) {
	player := find_player(gs)
	if player == nil do return

	player.damage = int(f32(player.damage) / quest.effects.damage_mult)
	player.attack_speed /= quest.effects.attack_speed_mult
	player.max_health = int(f32(player.max_health) / quest.effects.health_mult)
	player.health = min(player.health, player.max_health)

	quest.effects = {
		damage_mult       = 1.0,
		attack_speed_mult = 1.0,
		currency_mult     = 1.0,
		health_mult       = 1.0,
		experience_mult   = 1.0,
	}
}

player_pos :: proc(gs: ^Game_State) -> Vector2 {
	player := find_player(gs)
	return player != nil ? player.pos : Vector2{}
}

//
// :animations
create_animation :: proc(
	frames: []Image_Id,
	frame_duration: f32,
	loops: bool,
	name: string,
) -> Animation {
	frames_copy := make([]Image_Id, len(frames), context.allocator)
	copy(frames_copy[:], frames)

	return Animation {
		frames = frames_copy,
		current_frame = 0,
		frame_duration = frame_duration,
		base_duration = frame_duration,
		frame_timer = 0,
		state = .Stopped,
		loops = loops,
		name = name,
	}
}

adjust_animation_to_speed :: proc(anim: ^Animation, speed_multiplier: f32) {
	if anim == nil do return

	anim.frame_duration = anim.base_duration / speed_multiplier
}

update_animation :: proc(anim: ^Animation, delta_t: f32) -> bool {
	if anim == nil {
		return false
	}

	if anim.state != .Playing {
		return false
	}

	anim.frame_timer += delta_t
	if anim.frame_timer >= anim.frame_duration {
		anim.frame_timer -= anim.frame_duration
		anim.current_frame += 1

		if anim.current_frame >= len(anim.frames) {
			if anim.loops {
				anim.current_frame = 0
			} else {
				anim.current_frame = len(anim.frames) - 1
				anim.state = .Stopped
				return true
			}
		}
	}

	return false
}

get_current_frame :: proc(anim: ^Animation) -> Image_Id {
	if anim == nil {
		return .nil
	}

	if len(anim.frames) == 0 {
		return .nil
	}

	if anim.current_frame < 0 || anim.current_frame >= len(anim.frames) {
		return .nil
	}

	frame := anim.frames[anim.current_frame]
	return frame
}

draw_animated_sprite :: proc(
	pos: Vector2,
	anim: ^Animation,
	pivot := Pivot.bottom_left,
	xform := Matrix4(1),
) {
	if anim == nil do return
	current_frame := get_current_frame(anim)
	draw_sprite(pos, current_frame, pivot, xform)
}

play_animation :: proc(anim: ^Animation) {
	if anim == nil do return
	anim.state = .Playing
}

pause_animation :: proc(anim: ^Animation) {
	if anim == nil do return
	anim.state = .Paused
}

stop_animation :: proc(anim: ^Animation) {
	if anim == nil do return
	anim.state = .Stopped
	anim.current_frame = 0
	anim.frame_timer = 0
}

reset_animation :: proc(anim: ^Animation) {
	if anim == nil do return
	anim.current_frame = 0
	anim.frame_timer = 0
}

create_animation_collection :: proc() -> Animation_Collection {
	return Animation_Collection{animations = make(map[string]Animation), current_animation = ""}
}

add_animation :: proc(collection: ^Animation_Collection, animation: Animation) {
	collection.animations[animation.name] = animation
}

play_animation_by_name :: proc(collection: ^Animation_Collection, name: string) {
	if collection == nil {
		return
	}

	if collection.current_animation == name {
		return
	}

	if collection.current_animation != "" {
		if anim, ok := &collection.animations[collection.current_animation]; ok {
			stop_animation(anim)
		}
	}

	if anim, ok := &collection.animations[name]; ok {
		collection.current_animation = name
		play_animation(anim)
	} else {
		fmt.println("Animation not found:", name)
	}
}

update_current_animation :: proc(collection: ^Animation_Collection, delta_t: f32) {
	if collection.current_animation != "" {
		if anim, ok := &collection.animations[collection.current_animation]; ok {
			animation_finished := update_animation(anim, delta_t)
			if animation_finished && collection.current_animation == "attack" {
				play_animation_by_name(collection, "idle")
			}
		}
	}
}

draw_current_animation :: proc(
	collection: ^Animation_Collection,
	pos: Vector2,
	pivot := Pivot.bottom_left,
	xform := Matrix4(1),
) {
	if collection == nil || collection.current_animation == "" do return
	if anim, ok := &collection.animations[collection.current_animation]; ok {
		draw_animated_sprite(pos, anim, pivot, xform)
	}
}

load_animation_frames :: proc(directory: string, prefix: string) -> ([]Image_Id, bool) {
	frames: [dynamic]Image_Id
	frames.allocator = context.temp_allocator

	dir_handle, err := os.open(directory)
	if err != 0 {
		log_error("Failed to open directory:", directory)
		return nil, false
	}
	defer os.close(dir_handle)

	files, read_err := os.read_dir(dir_handle, 0)
	if read_err != 0 {
		log_error("Failed to read directory:", directory)
		return nil, false
	}

	for file in files {
		if !strings.has_prefix(file.name, prefix) do continue
		if !strings.has_suffix(file.name, ".png") do continue

		frame_name := strings.concatenate({prefix, "_", strings.trim_suffix(file.name, ".png")})

		frame_id: Image_Id
		switch frame_name {
		case "player_attack1":
			frame_id = .player_attack1
		case "player_attack2":
			frame_id = .player_attack2
		case "player_attack3":
			frame_id = .player_attack3
		case "player_attack4":
			frame_id = .player_attack4
		case "player_attack5":
			frame_id = .player_attack5
		case "player_attack6":
			frame_id = .player_attack6
		case:
			continue
		}

		append(&frames, frame_id)
	}

	if len(frames) == 0 {
		log_error("No frames found for animation:", prefix)
		return nil, false
	}

	return frames[:], true
}

DEBUG_FLAGS :: struct {
	mouse_pos:  bool,
	player_fov: bool,
}

DEBUG :: DEBUG_FLAGS {
	mouse_pos  = true,
	player_fov = true,
}

DEFAULT_UV :: v4{0, 0, 1, 1}
Vector2i :: [2]int
Vector2 :: [2]f32
Vector3 :: [3]f32
Vector4 :: [4]f32
v2 :: Vector2
v3 :: Vector3
v4 :: Vector4
Matrix4 :: linalg.Matrix4f32

COLOR_WHITE :: Vector4{1, 1, 1, 1}
COLOR_RED :: Vector4{1, 0, 0, 1}

loggie :: fmt.println
log_error :: fmt.println
log_warning :: fmt.println

init_time: t.Time
seconds_since_init :: proc() -> f64 {
	using t
	if init_time._nsec == 0 {
		log_error("invalid time")
		return 0
	}
	return duration_seconds(since(init_time))
}

xform_translate :: proc(pos: Vector2) -> Matrix4 {
	return linalg.matrix4_translate(v3{pos.x, pos.y, 0})
}
xform_rotate :: proc(angle: f32) -> Matrix4 {
	return linalg.matrix4_rotate(math.to_radians(angle), v3{0, 0, 1})
}
xform_scale :: proc(scale: Vector2) -> Matrix4 {
	return linalg.matrix4_scale(v3{scale.x, scale.y, 1})
}

Pivot :: enum {
	bottom_left,
	bottom_center,
	bottom_right,
	center_left,
	center_center,
	center_right,
	top_left,
	top_center,
	top_right,
}
scale_from_pivot :: proc(pivot: Pivot) -> Vector2 {
	switch pivot {
	case .bottom_left:
		return v2{0.0, 0.0}
	case .bottom_center:
		return v2{0.5, 0.0}
	case .bottom_right:
		return v2{1.0, 0.0}
	case .center_left:
		return v2{0.0, 0.5}
	case .center_center:
		return v2{0.5, 0.5}
	case .center_right:
		return v2{1.0, 0.5}
	case .top_center:
		return v2{0.5, 1.0}
	case .top_left:
		return v2{0.0, 1.0}
	case .top_right:
		return v2{1.0, 1.0}
	}
	return {}
}

sine_breathe :: proc(p: $T) -> T where intrinsics.type_is_float(T) {
	return (math.sin((p - .25) * 2.0 * math.PI) / 2.0) + 0.5
}



Button :: struct {
	bounds:     AABB,
	text:       string,
	text_scale: f32,
	color:      Vector4,
}

Tile :: struct {
    color: Vector4,
}

Wave_Status :: enum{
    WAITING,
    IN_PROGRESS,
    COMPLETED,
}

Floating_Text :: struct {
    pos: Vector2,
    text: string,
    lifetime: f32,
    max_lifetime: f32,
    velocity:  Vector2,
    color: Vector4,
}

Game_State_Kind :: enum {
	MENU,
	PLAYING,
	PAUSED,
	SHOP,
	GAME_OVER,
	SKILLS,
	QUESTS,
}

Game_State :: struct {
	state_kind:           Game_State_Kind,
	tick_index:           u64,
	entities:             [128]Entity,
	latest_entity_handle: Entity_Handle,
	tiles:                [WORLD_W * WORLD_H]Tile,
	player_level:         int,
	player_experience:    int,
	wave_number:          int,
	wave_spawn_timer:     f32,
	wave_spawn_rate:      f32,
	enemies_to_spawn:     int,
	currency_points:      int, // Currency
	floating_texts:       [dynamic]Floating_Text,
	wave_status:          Wave_Status,
	active_enemies:       int,
	wave_config:          Wave_Config,
	current_wave_difficulty: f32,
    skills: [Skill_Kind]Skill,
    active_skill: Maybe(Skill_Kind),
    skills_scroll_offset: f32,
    quests: map[Quest_Kind]Quest,
    active_quest: Maybe(Quest_Kind),
    quest_scroll_offset: f32,
}

Enemy_Target :: struct {
	entity:   ^Entity,
	distance: f32,
}

Enemy_state :: enum {
	idle,
	moving,
	attacking,
}

Entity_Flags :: enum {
	allocated,
	physics,
}

Entity_Kind :: enum {
	nil,
	player,
	enemy,
	player_projectile,
}

Entity :: struct {
	id:                 Entity_Handle,
	kind:               Entity_Kind,
	flags:              bit_set[Entity_Flags],
	pos:                Vector2,
	prev_pos:           Vector2,
	direction:          Vector2,
	health:             int,
	max_health:         int,
	damage:             int,
	attack_speed:       f32,
	attack_timer:       f32,
	speed:              f32,
	value:              int,
	enemy_type:         int,
	state:              Enemy_state,
	target:             ^Entity,
	frame:              struct {},
	level:              int, // Current level
	experience:         int, // Current currency
	upgrade_levels:     struct {
		attack_speed: int,
		accuracy:     int,
		damage:       int,
		armor:        int,
		life_steal:   int,
		exp_gain:     int,
		crit_chance:  int,
		crit_damage:  int,
		multishot:    int,
		health_regen: int,
		dodge_chance: int,
		fov_range:    int,
	},
	health_regen_timer: f32,
	current_fov_range:  f32,
	energy_field_charge: int,
	current_element: Element_Kind,
	chain_reaction_range: f32,
	is_multishot: bool,
	animations: Animation_Collection,
}

Element_Kind :: enum{
    None,
    Fire, // damage over time
    Ice, // slows enemies
    Lightning, // chain damage to nearby enemies
}

Wave_Config :: struct {
    base_enemy_count: int,
    enemy_count_increase: int,
    max_enemy_count: int,
    base_difficulty: f32,
    difficulty_scale_factor: f32,

    health_scale: f32,
    damage_scale: f32,
    speed_scale: f32,
}

Skill_Kind :: enum {
    damage,
    attack_speed,
    armor,
    life_steal,
    crit_damage,
    health_regen,
}

Skill :: struct {
    kind: Skill_Kind,
    level: int,
    experience: int,
    unlocked: bool
}

Quest_Category :: enum {
    Combat_Flow,
    Resource_Management,
    Strategic,
}

Quest_Kind :: enum {
    Time_Dilation,
    Chain_Reaction,
    Energy_Field,
    Projectile_Master,
    Critical_Cascade,

    Gold_Fever,
    Experience_Flow,
    Blood_Ritual,
    Fortune_Seeker,
    Risk_Reward,

    Priority_Target,
    Sniper_Protocol,
    Crowd_Suppression,
    Elemental_Rotation,
    Defensive_Matrix,
}

Quest_State :: enum{
    Locked,
    Available,
    Purchased,
    Active,
}

Quest :: struct {
    kind: Quest_Kind,
    state: Quest_State,
    progress: int,
    max_progress: int,
    effects: struct {
        damage_mult: f32,
        attack_speed_mult: f32,
        currency_mult: f32,
        health_mult: f32,
        experience_mult: f32,
    },
}

Quest_Info :: struct {
    kind: Quest_Kind,
    category: Quest_Category,
    unlock_level: int,
    base_cost: int,
    description: string,
}

Animation_State :: enum {
    Playing,
    Paused,
    Stopped,
}

Animation :: struct {
    frames: []Image_Id,
    current_frame: int,
    frame_duration: f32,
    frame_timer: f32,
    state: Animation_State,
    loops: bool,
    name: string,
    base_duration: f32,
}

Animation_Collection :: struct {
    animations: map[string]Animation,
    current_animation: string,
}

app_state: struct {
	pass_action:   sg.Pass_Action,
	pip:           sg.Pipeline,
	bind:          sg.Bindings,
	input_state:   Input_State,
	game:          Game_State,
	camera_pos:    Vector2,
}

Sound_State :: struct {
	system: ^fstudio.SYSTEM,
	core_system: ^fcore.SYSTEM,
	bank: ^fstudio.BANK,
	strings_bank: ^fstudio.BANK,
	master_ch_group : ^fcore.CHANNELGROUP,
}
sound_st: Sound_State

init_sound :: proc(){
    using fstudio
    using sound_st

	fmod_error_check(System_Create(&system, fcore.VERSION))

	fmod_error_check(System_Initialize(system, 512, INIT_NORMAL, INIT_NORMAL, nil))

	fmod_error_check(System_LoadBankFile(system, "./res_workbench/fmod_wavebreakers/wavebreakers/Build/Desktop/Master.bank", LOAD_BANK_NORMAL, &bank))
	fmod_error_check(System_LoadBankFile(system, "./res_workbench/fmod_wavebreakers/wavebreakers/Build/Desktop/Master.strings.bank", LOAD_BANK_NORMAL, &strings_bank))
}

play_sound :: proc(name: string) {
    using fstudio
    using sound_st

    event_path := fmt.tprintf("event:/%s", name)

    event_desc: ^EVENTDESCRIPTION
    result := System_GetEvent(system, fmt.ctprint(event_path), &event_desc) // Use event_path instead of name

    if result != .OK {
        fmt.println("Failed to get event:", event_path, "Error:", fcore.error_string(result))
        return
    }

    instance: ^EVENTINSTANCE
    fmod_error_check(EventDescription_CreateInstance(event_desc, &instance))
    fmod_error_check(EventInstance_Start(instance))
}

update_sound :: proc() {
    using fstudio
    using sound_st

    fmod_error_check(System_Update(system))
}

fmod_error_check :: proc(result: fcore.RESULT) {
	assert(result == .OK, fcore.error_string(result))
}

draw_sprite :: proc(
	pos: Vector2,
	img_id: Image_Id,
	pivot := Pivot.bottom_left,
	xform := Matrix4(1),
	color_override := v4{0, 0, 0, 0},
	deferred := false,
) {
    if int(img_id) < 0 || int(img_id) >= len(images) {
        fmt.println("Invalid image ID:", img_id, "at position", int(img_id))
        return
    }

	image := images[img_id]
	size := v2{auto_cast image.width, auto_cast image.height}

	xform0 := Matrix4(1)
	xform0 *= xform_translate(pos)
	xform0 *= xform
	xform0 *= xform_translate(size * -scale_from_pivot(pivot))

	draw_rect_xform(
		xform0,
		size,
		img_id = img_id,
		color_override = color_override,
		deferred = deferred,
	)
}

draw_rect_aabb :: proc(
	pos: Vector2,
	size: Vector2,
	col: Vector4 = COLOR_WHITE,
	uv: Vector4 = DEFAULT_UV,
	img_id: Image_Id = .nil,
	color_override := v4{0, 0, 0, 0},
	deferred := false,
) {
	xform := linalg.matrix4_translate(v3{pos.x, pos.y, 0})
	draw_rect_xform(xform, size, col, uv, img_id, color_override, deferred = deferred)
}

draw_rect_xform :: proc(
	xform: Matrix4,
	size: Vector2,
	col: Vector4 = COLOR_WHITE,
	uv: Vector4 = DEFAULT_UV,
	img_id: Image_Id = .nil,
	color_override := v4{0, 0, 0, 0},
	deferred := false,
) {
	draw_rect_projected(
		draw_frame.projection * draw_frame.camera_xform * xform,
		size,
		col,
		uv,
		img_id,
		color_override,
		deferred = deferred,
	)
}

Vertex :: struct {
	pos:            Vector2,
	col:            Vector4,
	uv:             Vector2,
	tex_index:      u8,
	_pad:           [3]u8,
	color_override: Vector4,
}

Quad :: [4]Vertex

MAX_QUADS :: 135000
MAX_VERTS :: MAX_QUADS * 4

Draw_Frame :: struct {
	scuffed_deferred_quads: [MAX_QUADS / 4]Quad,
	quads:                  [MAX_QUADS]Quad,
	projection:             Matrix4,
	camera_xform:           Matrix4,
	using reset:            struct {
		quad_count:                  int,
		sucffed_deferred_quad_count: int,
	},
}
draw_frame: Draw_Frame

// below is the lower level draw rect stuff

draw_rect_projected :: proc(
	world_to_clip: Matrix4,
	size: Vector2,
	col: Vector4 = COLOR_WHITE,
	uv: Vector4 = DEFAULT_UV,
	img_id: Image_Id = .nil,
	color_override := v4{0, 0, 0, 0},
	deferred := false,
) {

	bl := v2{0, 0}
	tl := v2{0, size.y}
	tr := v2{size.x, size.y}
	br := v2{size.x, 0}

	uv0 := uv
	if uv == DEFAULT_UV {
		uv0 = images[img_id].atlas_uvs
	}

	tex_index: u8 = images[img_id].tex_index
	if img_id == .nil {
		tex_index = 255
	}

	draw_quad_projected(
		world_to_clip,
		{bl, tl, tr, br},
		{col, col, col, col},
		{uv0.xy, uv0.xw, uv0.zw, uv0.zy},
		{tex_index, tex_index, tex_index, tex_index},
		{color_override, color_override, color_override, color_override},
		deferred = deferred,
	)

}

draw_quad_projected :: proc(
	world_to_clip: Matrix4,
	positions: [4]Vector2,
	colors: [4]Vector4,
	uvs: [4]Vector2,
	tex_indicies: [4]u8,
	//flags:           [4]Quad_Flags,
	color_overrides: [4]Vector4,
	//hsv:             [4]Vector3
	deferred := false,
) {
	using linalg

	if draw_frame.quad_count >= MAX_QUADS {
		log_error("max quads reached")
		return
	}

	verts := cast(^[4]Vertex)&draw_frame.quads[draw_frame.quad_count]
	if deferred {
		verts =
		cast(^[4]Vertex)&draw_frame.scuffed_deferred_quads[draw_frame.sucffed_deferred_quad_count]
		draw_frame.sucffed_deferred_quad_count += 1
	} else {
		draw_frame.quad_count += 1
	}


	verts[0].pos = (world_to_clip * Vector4{positions[0].x, positions[0].y, 0.0, 1.0}).xy
	verts[1].pos = (world_to_clip * Vector4{positions[1].x, positions[1].y, 0.0, 1.0}).xy
	verts[2].pos = (world_to_clip * Vector4{positions[2].x, positions[2].y, 0.0, 1.0}).xy
	verts[3].pos = (world_to_clip * Vector4{positions[3].x, positions[3].y, 0.0, 1.0}).xy

	verts[0].col = colors[0]
	verts[1].col = colors[1]
	verts[2].col = colors[2]
	verts[3].col = colors[3]

	verts[0].uv = uvs[0]
	verts[1].uv = uvs[1]
	verts[2].uv = uvs[2]
	verts[3].uv = uvs[3]

	verts[0].tex_index = tex_indicies[0]
	verts[1].tex_index = tex_indicies[1]
	verts[2].tex_index = tex_indicies[2]
	verts[3].tex_index = tex_indicies[3]

	verts[0].color_override = color_overrides[0]
	verts[1].color_override = color_overrides[1]
	verts[2].color_override = color_overrides[2]
	verts[3].color_override = color_overrides[3]
}

MENU_BUTTON_WIDTH :: 200.0
MENU_BUTTON_HEIGHT :: 50.0
PAUSE_MENU_BUTTON_WIDTH :: 200.0
PAUSE_MENU_BUTTON_HEIGHT :: 50.0
PAUSE_MENU_SPACING :: 20.0
WAVE_BUTTON_WIDTH :: 200.0
WAVE_BUTTON_HEIGHT :: 50.0

SKILLS_BUTTON_WIDTH :: 150.0
SKILLS_BUTTON_HEIGHT :: 40.0
SKILLS_PANEL_WIDTH :: 400.0
SKILLS_PANEL_HEIGHT :: 600.0
SKILL_ENTRY_HEIGHT :: 60.0
SKILL_ENTRY_PADDING :: 10.0

QUEST_BUTTON_WIDTH :: 150.0
QUEST_BUTTON_HEIGHT :: 40.0
QUEST_PANEL_WIDTH :: 800.0
QUEST_PANEL_HEIGHT :: 600.0
QUEST_ENTRY_HEIGHT :: 80.0
QUEST_ENTRY_PADDING :: 10.0

draw_menu :: proc(gs: ^Game_State) {
	play_button := make_centered_button(100, MENU_BUTTON_WIDTH, MENU_BUTTON_HEIGHT, "Play")

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

    panel_width := 1000.0
    panel_height := 700.0
    panel_x := -panel_width * 0.5
    panel_y := -panel_height * 0.5

    draw_rect_aabb(
        v2{auto_cast panel_x, auto_cast panel_y},
        v2{auto_cast panel_width, auto_cast panel_height},
        col = v4{0.1, 0.1, 0.1, 0.9},
    )

    player := find_player(gs)
    if player == nil do return

    title_pos := v2{auto_cast panel_x + 50, auto_cast panel_y + auto_cast panel_height - 80}
    draw_text(title_pos, "Shop", scale = 3.0)

    currency_pos := v2{auto_cast panel_x + auto_cast panel_width - 300, auto_cast panel_y + auto_cast panel_height - 80}
    currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
    draw_text(currency_pos, currency_text, scale = 2.0)

    column_count := 2
    items_per_column := (len(Upgrade_Kind) + column_count - 1) / column_count

    content_width := panel_width - 160
    column_width := auto_cast content_width / auto_cast column_count

    button_spacing_y := 100.0

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
            text_scale = 2.0,
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
        draw_text(name_pos, upgrade_text, scale = 1.5)

        if level >= MAX_UPGRADE_LEVEL {
            max_pos := v2{auto_cast x_pos + PAUSE_MENU_BUTTON_WIDTH + 10, auto_cast y_pos + 5}
            draw_text(max_pos, "MAX", scale = 1.5, color = v4{1, 0.8, 0, 1})
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
    button_pos := v2{0, -250}

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

draw_skills_button :: proc(gs: ^Game_State){
    button_pos := v2{600, 500}

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
		600,
		SKILLS_BUTTON_WIDTH,
		SKILLS_BUTTON_HEIGHT,
		"Skills",
		x_offset = 	SKILLS_BUTTON_WIDTH + PAUSE_MENU_SPACING,
		color = v4{0.5, 0.1, 0.8, 1.0}
	)

    if draw_button(button){
        gs.state_kind = .SKILLS
    }
}

draw_shop_button :: proc(gs: ^Game_State){
	shop_button := make_centered_button(
		600,
		SKILLS_BUTTON_WIDTH,
		SKILLS_BUTTON_HEIGHT,
		"Shop",
		x_offset = 0,
		color = v4{0.5, 0.1, 0.8, 1.0},
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
        600,
        QUEST_BUTTON_WIDTH,
        QUEST_BUTTON_HEIGHT,
        "Quests",
        x_offset = -(QUEST_BUTTON_WIDTH + PAUSE_MENU_SPACING),
        color = button_color,
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
            current_y -= 30.0
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

Key_Code :: enum {
	// copied from sokol_app
	INVALID       = 0,
	SPACE         = 32,
	APOSTROPHE    = 39,
	COMMA         = 44,
	MINUS         = 45,
	PERIOD        = 46,
	SLASH         = 47,
	_0            = 48,
	_1            = 49,
	_2            = 50,
	_3            = 51,
	_4            = 52,
	_5            = 53,
	_6            = 54,
	_7            = 55,
	_8            = 56,
	_9            = 57,
	SEMICOLON     = 59,
	EQUAL         = 61,
	A             = 65,
	B             = 66,
	C             = 67,
	D             = 68,
	E             = 69,
	F             = 70,
	G             = 71,
	H             = 72,
	I             = 73,
	J             = 74,
	K             = 75,
	L             = 76,
	M             = 77,
	N             = 78,
	O             = 79,
	P             = 80,
	Q             = 81,
	R             = 82,
	S             = 83,
	T             = 84,
	U             = 85,
	V             = 86,
	W             = 87,
	X             = 88,
	Y             = 89,
	Z             = 90,
	LEFT_BRACKET  = 91,
	BACKSLASH     = 92,
	RIGHT_BRACKET = 93,
	GRAVE_ACCENT  = 96,
	WORLD_1       = 161,
	WORLD_2       = 162,
	ESCAPE        = 256,
	ENTER         = 257,
	TAB           = 258,
	BACKSPACE     = 259,
	INSERT        = 260,
	DELETE        = 261,
	RIGHT         = 262,
	LEFT          = 263,
	DOWN          = 264,
	UP            = 265,
	PAGE_UP       = 266,
	PAGE_DOWN     = 267,
	HOME          = 268,
	END           = 269,
	CAPS_LOCK     = 280,
	SCROLL_LOCK   = 281,
	NUM_LOCK      = 282,
	PRINT_SCREEN  = 283,
	PAUSE         = 284,
	F1            = 290,
	F2            = 291,
	F3            = 292,
	F4            = 293,
	F5            = 294,
	F6            = 295,
	F7            = 296,
	F8            = 297,
	F9            = 298,
	F10           = 299,
	F11           = 300,
	F12           = 301,
	F13           = 302,
	F14           = 303,
	F15           = 304,
	F16           = 305,
	F17           = 306,
	F18           = 307,
	F19           = 308,
	F20           = 309,
	F21           = 310,
	F22           = 311,
	F23           = 312,
	F24           = 313,
	F25           = 314,
	KP_0          = 320,
	KP_1          = 321,
	KP_2          = 322,
	KP_3          = 323,
	KP_4          = 324,
	KP_5          = 325,
	KP_6          = 326,
	KP_7          = 327,
	KP_8          = 328,
	KP_9          = 329,
	KP_DECIMAL    = 330,
	KP_DIVIDE     = 331,
	KP_MULTIPLY   = 332,
	KP_SUBTRACT   = 333,
	KP_ADD        = 334,
	KP_ENTER      = 335,
	KP_EQUAL      = 336,
	LEFT_SHIFT    = 340,
	LEFT_CONTROL  = 341,
	LEFT_ALT      = 342,
	LEFT_SUPER    = 343,
	RIGHT_SHIFT   = 344,
	RIGHT_CONTROL = 345,
	RIGHT_ALT     = 346,
	RIGHT_SUPER   = 347,
	MENU          = 348,

	LEFT_MOUSE    = 400,
	RIGHT_MOUSE   = 401,
	MIDDLE_MOUSE  = 402,
}
MAX_KEYCODES :: sapp.MAX_KEYCODES
map_sokol_mouse_button :: proc "c" (sokol_mouse_button: sapp.Mousebutton) -> Key_Code {
	#partial switch sokol_mouse_button {
	case .LEFT:
		return .LEFT_MOUSE
	case .RIGHT:
		return .RIGHT_MOUSE
	case .MIDDLE:
		return .MIDDLE_MOUSE
	}
	return nil
}

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

initialize :: proc "c" () {
    context = runtime.default_context()
    init_time = t.now()

    sg.setup({
        environment = sglue.environment(),
        logger = {func = slog.func},
        d3d11_shader_debugging = ODIN_DEBUG,
    })

    init_images()
    init_fonts()
    init_sound()
    play_sound("beat")

    first_time_init_game_state(&app_state.game)

    rand.reset(auto_cast runtime.read_cycle_counter())

    app_state.bind.vertex_buffers[0] = sg.make_buffer({
        usage = .DYNAMIC,
        size = size_of(Quad) * len(draw_frame.quads)
    })

    index_buffer_count :: MAX_QUADS * 6
    indices := make([]u16, index_buffer_count)
    defer delete(indices)

    i := 0
    for i < index_buffer_count {
        indices[i + 0] = auto_cast ((i / 6) * 4 + 0)
        indices[i + 1] = auto_cast ((i / 6) * 4 + 1)
        indices[i + 2] = auto_cast ((i / 6) * 4 + 2)
        indices[i + 3] = auto_cast ((i / 6) * 4 + 0)
        indices[i + 4] = auto_cast ((i / 6) * 4 + 2)
        indices[i + 5] = auto_cast ((i / 6) * 4 + 3)
        i += 6
    }

    app_state.bind.index_buffer = sg.make_buffer({
        type = .INDEXBUFFER,
        data = {ptr = raw_data(indices), size = size_of(u16) * len(indices)}
    })

    app_state.bind.samplers[SMP_default_sampler] = sg.make_sampler({})

    pipeline_desc: sg.Pipeline_Desc = {
        shader = sg.make_shader(quad_shader_desc(sg.query_backend())),
        index_type = .UINT16,
        layout = {
            attrs = {
                ATTR_quad_position = {format = .FLOAT2},
                ATTR_quad_color0 = {format = .FLOAT4},
                ATTR_quad_uv0 = {format = .FLOAT2},
                ATTR_quad_bytes0 = {format = .UBYTE4N},
                ATTR_quad_color_override0 = {format = .FLOAT4},
            },
        },
        depth = {
            compare = .LESS_EQUAL,
            write_enabled = true,
            pixel_format = .DEPTH_STENCIL,
        },
        cull_mode = .NONE,
        face_winding = .CCW,
    }

    blend: sg.Blend_State = {
        enabled = true,
        src_factor_rgb = .SRC_ALPHA,
        dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        op_rgb = .ADD,
        src_factor_alpha = .ONE,
        dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
        op_alpha = .ADD,
    }
    pipeline_desc.colors[0].blend = blend

    app_state.pip = sg.make_pipeline(pipeline_desc)

    app_state.pass_action = {
        colors = {
            0 = {
                load_action = .CLEAR,
                clear_value = {0, 0, 0, 1},
            },
        },
    }
}

frame_init :: proc "c" () {
	using runtime, linalg
	context = runtime.default_context()

	current_time := t.now()
	frame_time: f64 = t.duration_seconds(t.diff(last_time, current_time))
	last_time = current_time
	frame_time = sapp.frame_duration()

	handle_input(&app_state.game)

	accumulator += frame_time

    for accumulator >= sims_per_second {
        update_gameplay(&app_state.game, sims_per_second)
        last_sim_time = seconds_since_init()
        accumulator -= sims_per_second
    }

	draw_frame.reset = {}
	dt := seconds_since_init() - last_sim_time
	render_gameplay(&app_state.game, app_state.input_state)

	reset_input_state_for_next_frame(&app_state.input_state)

	for i in 0 ..< draw_frame.sucffed_deferred_quad_count {
		draw_frame.quads[draw_frame.quad_count] = draw_frame.scuffed_deferred_quads[i]
		draw_frame.quad_count += 1
	}

	app_state.bind.images[IMG_tex0] = atlas.sg_image
	app_state.bind.images[IMG_tex1] = images[font.img_id].sg_img

	sg.update_buffer(
		app_state.bind.vertex_buffers[0],
		{ptr = &draw_frame.quads[0], size = size_of(Quad) * len(draw_frame.quads)},
	)
	sg.begin_pass({action = app_state.pass_action, swapchain = sglue.swapchain()})
	sg.apply_pipeline(app_state.pip)
	sg.apply_bindings(app_state.bind)
	sg.draw(0, 6 * draw_frame.quad_count, 1)
	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
	update_sound()
}

CHAIN_REACTION_RANGE :: 200.0
CHAIN_REACTION_DAMAGE_MULT :: 0.5

ENERGY_FIELD_MAX_CHARGE :: 100
ENERGY_FIELD_CHARGE_PER_HIT :: 10
ENERGY_FIELD_RANGE :: 300.0
ENERGY_FIELD_DAMAGE_MULT :: 2.0

PROJECTILE_MASTER_SHOT_COUNT :: 3
PROJECTILE_MASTER_ANGLE_SPREAD :: 15.0

CRITICAL_CASCADE_RELOAD_CHANCE :: 0.5

spawn_floating_text :: proc(gs: ^Game_State, pos: Vector2, text: string, color := COLOR_WHITE){
    text_copy := strings.clone(text, context.allocator)
    append(&gs.floating_texts, Floating_Text{
        pos = pos + v2{0, 75},
        text = text_copy,
        lifetime = 1.2,
        max_lifetime = 1.2,
        velocity = v2{0, 5},
        color = color,
    })
}

ENEMY_ATTACK_RANGE :: 100.0
ENEMY_ATTACK_COOLDOWN :: 2.0
process_enemy_behaviour :: proc(en: ^Entity, gs: ^Game_State, delta_t: f32) {
	if gs.active_quest != nil && gs.active_quest.? == .Time_Dilation{
	   en.speed = min(en.speed * (1 + delta_t), 100.0) //slow down and gradually recover the speed
	}

	if en.target == nil {
		for &potential_target in gs.entities {
			if potential_target.kind == .player {
				en.target = &potential_target
				break
			}
		}
	}

	if en.target == nil do return
	direction := en.target.pos - en.pos
	distance := linalg.length(direction)

	#partial switch en.state {
	case .moving:
		if distance <= ENEMY_ATTACK_RANGE {
			en.state = .attacking
		}
	case .attacking:
		if distance > ENEMY_ATTACK_RANGE {
			en.state = .moving
		}
	}

    wave_num := gs.wave_number

	#partial switch en.state {
	case .moving:
		if distance > 2.0 {
			en.prev_pos = en.pos
			direction = linalg.normalize(direction)
			en.pos += direction * en.speed * delta_t
		}
	case .attacking:
	    en.prev_pos = en.pos
        en.speed = 0
		en.attack_timer -= delta_t
		if en.attack_timer <= 0 {
			if en.target != nil {
			    play_animation_by_name(&en.animations, wave_num <= 10 ? "enemy1_10_attack" : "enemy11_19_attack")
				damage := process_enemy_damage(en.target, en.damage)
				en.target.health -= damage

				if en.target.health <= 0{
				    en.target.health = 0
				}

				en.attack_timer = ENEMY_ATTACK_COOLDOWN
			}
		}
	}
}

process_enemy_damage :: proc(player: ^Entity, damage: int) -> int {
	dodge_chance := f32(player.upgrade_levels.dodge_chance) * DODGE_CHANCE_PER_LEVEL
	if rand.float32() < dodge_chance {
		return 0
	}

	return damage
}


find_enemies_in_range :: proc(gs: ^Game_State, source_pos: Vector2, range: f32) -> []Enemy_Target {
	player := find_player(gs)
	actual_range := player != nil ? player.current_fov_range : range

	targets: [dynamic]Enemy_Target
	targets.allocator = context.temp_allocator

	for &en in gs.entities {
		if en.kind != .enemy do continue
		if !(.allocated in en.flags) do continue

		direction := en.pos - source_pos
		distance := linalg.length(direction)

		if distance <= actual_range {
			append(&targets, Enemy_Target{entity = &en, distance = distance})
		}
	}

	if len(targets) > 1 {
		for i := 0; i < len(targets) - 1; i += 1 {
			for j := 0; j < len(targets) - i - 1; j += 1 {
				if targets[j].distance > targets[j + 1].distance {
					targets[j], targets[j + 1] = targets[j + 1], targets[j]
				}
			}
		}
	}

	return targets[:]
}

PROJECTILE_SPEED :: 600.0
PROJECTILE_SIZE :: v2{32, 32}
PROJECTILE_GRAVITY :: 980.0
PROJECTILE_INITIAL_Y_VELOCITY :: 400.0

calculate_enemy_velocity :: proc(enemy: ^Entity) -> Vector2 {
	if enemy.state != .moving do return Vector2{}

	direction := linalg.normalize(enemy.target.pos - enemy.pos)
	return direction * enemy.speed
}

calculate_intercept_point :: proc(
	shooter_pos: Vector2,
	target: ^Entity,
) -> (
	hit_pos: Vector2,
	flight_time: f32,
) {
	target_velocity := calculate_enemy_velocity(target)
	to_target := target.pos - shooter_pos

	effective_speed := f32(600.0)

	a := linalg.length2(target_velocity) - effective_speed * effective_speed
	b := 2 * linalg.dot(to_target, target_velocity)
	c := linalg.length2(to_target)

	discriminant := b * b - 4 * a * c

	if discriminant < 0 {
		return target.pos, linalg.length(to_target)
	}

	t1 := (-b - math.sqrt(discriminant)) / (2 * a)
	t2 := (-b + math.sqrt(discriminant)) / (2 * a)
	time := min(t1, t2) if t1 > 0 else t2

	if time < 0 {
		return target.pos, linalg.length(to_target)
	}

	predicted_pos := target.pos + target_velocity * time
	return predicted_pos, time
}

setup_projectile :: proc(gs: ^Game_State, e: ^Entity, pos: Vector2, target_pos: Vector2, is_multishot := false) {
	e.kind = .player_projectile
	e.flags |= {.allocated}
    e.is_multishot = is_multishot

	player_height := 32.0 * 5.0
	spawn_position := pos + v2{0, auto_cast player_height * 0.5}
	e.pos = spawn_position
	e.prev_pos = spawn_position

	player := find_player(gs)

    if player != nil && !is_multishot {
        multishot_level := player.upgrade_levels.multishot
        multishot_chance := f32(multishot_level) * MULTISHOT_CHANCE_PER_LEVEL

        for i := 0; i < 2; i += 1 {
            if rand.float32() < multishot_chance {
                extra_projectile := entity_create(&app_state.game)
                if extra_projectile != nil {
                    angle_offset := rand.float32_range(-0.2, 0.2)
                    modified_target := target_pos + Vector2{math.cos(angle_offset), math.sin(angle_offset)} * 50
                    setup_projectile(gs, extra_projectile, pos, modified_target, true)
                    extra_projectile.damage = int(f32(extra_projectile.damage) * 0.5)
                }
            }
        }
    }

    if !is_multishot && gs.active_quest != nil && gs.active_quest.? == .Projectile_Master {
            base_angle := math.atan2(target_pos.y - pos.y, target_pos.x - pos.x)
            shot_distance := linalg.length(target_pos - pos)

            for i in 1..<PROJECTILE_MASTER_SHOT_COUNT {
                extra_projectile := entity_create(gs)
                if extra_projectile != nil {
                    angle_offset := f32(i) * PROJECTILE_MASTER_ANGLE_SPREAD * math.PI / 180.0

                    modified_target := pos + Vector2{
                        math.cos(base_angle + angle_offset),
                        math.sin(base_angle + angle_offset),
                    } * shot_distance

                    setup_projectile(gs, extra_projectile, pos, modified_target, true)

                    extra_projectile = entity_create(gs)
                    if extra_projectile != nil {
                        modified_target = pos + Vector2{
                            math.cos(base_angle - angle_offset),
                            math.sin(base_angle - angle_offset),
                        } * shot_distance
                        setup_projectile(gs, extra_projectile, pos, modified_target, true)
                    }
                }
            }
        }

    accuracy_level := player != nil ? player.upgrade_levels.accuracy : 0

	to_target := target_pos - spawn_position
	distance := linalg.length(to_target)

	base_spread := 0.35
	max_range := FOV_RANGE
	distance_factor := auto_cast distance / auto_cast max_range
	accuracy_reduction := f32(accuracy_level) * ACCURACY_BONUS_PER_LEVEL
	actual_spread := base_spread * auto_cast distance_factor * auto_cast (1.0 - accuracy_reduction)

	angle_offset := rand.float32_range(auto_cast -actual_spread, auto_cast actual_spread)
	cos_theta := math.cos(angle_offset)
	sin_theta := math.sin(angle_offset)

	dx := target_pos.x - spawn_position.x
	dy := target_pos.y - spawn_position.y
	adjusted_x := dx * cos_theta - dy * sin_theta
	adjusted_y := dx * sin_theta + dy * cos_theta
	adjusted_target := spawn_position + Vector2{adjusted_x, adjusted_y}

	flight_time := max(distance / 600.0, 0.5)
	gravity := PROJECTILE_GRAVITY
	dx = linalg.length(adjusted_target - spawn_position)
	dy = adjusted_target.y - spawn_position.y

	vx := dx / flight_time
	vy := (dy + 0.5 * auto_cast gravity * flight_time * flight_time) / flight_time

	direction := linalg.normalize(adjusted_target - spawn_position)
	e.direction = {direction.x * vx, vy}

	if player != nil {
		e.damage = player.damage
	} else {
		e.damage = 10
	}
}

when_enemy_dies :: proc(gs: ^Game_State, enemy: ^Entity) {
    switch enemy.enemy_type {
        case 10:
            spawn_floating_text(
                gs,
                enemy.pos,
                "First Boss Defeated",
                v4{1, 0.5, 0, 1},
            )
            spawn_floating_text(
                gs,
                enemy.pos + v2{0, 50},
                "New Enemy Type Unlocked",
                v4{0,1,0,1},
            )
        case 20:
            spawn_floating_text(
                gs,
                enemy.pos,
                "Second Boss Defeated",
                v4{1, 0.5, 0, 1},
            )
            spawn_floating_text(
                gs,
                enemy.pos + v2{0, 50},
                "New Enemy Type Unlocked",
                v4{0,1,0,1},
            )
    }

    enemies_to_destroy := 0

    if gs.active_quest != nil && gs.active_quest.? == .Chain_Reaction {
        targets := find_enemies_in_range(gs, enemy.pos, CHAIN_REACTION_RANGE)

        if len(targets) > 0 {
            explosion_damage := int(f32(enemy.max_health) * CHAIN_REACTION_DAMAGE_MULT)

            entities_to_destroy: [dynamic]^Entity
            entities_to_destroy.allocator = context.temp_allocator

            for target in targets {
                if target.entity == enemy do continue
                target.entity.health -= explosion_damage

                spawn_floating_text(
                    gs,
                    target.entity.pos,
                    fmt.tprintf("%d", explosion_damage),
                    v4{1, 0.5, 0, 1},
                )

                if target.entity.health <= 0 {
                    append(&entities_to_destroy, target.entity)
                    enemies_to_destroy += 1
                }
            }

            for entity_to_destroy in entities_to_destroy {
                entity_destroy(gs, entity_to_destroy)
            }
        }
    }

    add_currency_points(gs, enemy.value)
    gs.active_enemies -= (1 + enemies_to_destroy)

    actual_active_enemies := 0
    for &en in gs.entities{
        if en.kind == .enemy && .allocated in en.flags{
            actual_active_enemies += 1
        }
    }

    if actual_active_enemies != gs.active_enemies{
        gs.active_enemies = actual_active_enemies
    }

    if gs.active_enemies <= 0 && gs.enemies_to_spawn <= 0 {
        gs.wave_status = .COMPLETED
    }
}

when_projectile_hits_enemy :: proc(gs: ^Game_State, projectile: ^Entity, enemy: ^Entity) {
    player := find_player(gs)
    if player == nil do return

    if gs.active_quest != nil && gs.active_quest.? == .Time_Dilation {
        enemy.speed *= 0.5
    }

    if gs.active_quest != nil && gs.active_quest.? == .Energy_Field {
        player.energy_field_charge += ENERGY_FIELD_CHARGE_PER_HIT

        if player.energy_field_charge >= ENERGY_FIELD_MAX_CHARGE {
            targets := find_enemies_in_range(gs, player.pos, ENERGY_FIELD_RANGE)
            pulse_damage := int(f32(player.damage) * ENERGY_FIELD_DAMAGE_MULT)

            for target in targets {
                target.entity.health -= pulse_damage
                spawn_floating_text(
                    gs,
                    target.entity.pos,
                    fmt.tprintf("%d", pulse_damage),
                    v4{0, 0.7, 1, 1},
                )

                if target.entity.health <= 0 {
                    when_enemy_dies(gs, target.entity)
                    entity_destroy(gs, target.entity)
                }
            }

            player.energy_field_charge = 0
        }
    }

    if gs.active_quest != nil && gs.active_quest.? == .Elemental_Rotation{
        apply_elemental_effects(gs, enemy, projectile.damage)
    }

    total_damage := projectile.damage
    crit_hit := false

    if gs.active_quest != nil && gs.active_quest.? == .Sniper_Protocol {
        distance := linalg.length(enemy.pos - player.pos)
        if distance > FOV_RANGE * 0.6 {
            total_damage = int(f32(total_damage) * 1.5)
            spawn_floating_text(gs, enemy.pos, "Long range bonus!", v4{0.8, 0.8, 0.2, 1})
        } else if distance < FOV_RANGE * 0.3 {
            total_damage = int(f32(total_damage) * 0.7)
            spawn_floating_text(gs, enemy.pos, "Close range penalty!", v4{0.8, 0.2, 0.2, 1})
        }
    }

    if gs.active_quest != nil && gs.active_quest.? == .Priority_Target {
        targets := find_enemies_in_range(gs, player.pos, FOV_RANGE)
        if len(targets) > 0 && targets[0].entity == enemy {
            total_damage = int(f32(total_damage) * 1.5)
            spawn_floating_text(gs, enemy.pos, "Priority target!", v4{1, 0.8, 0, 1})
        }
    }

    if gs.active_quest != nil && gs.active_quest.? == .Crowd_Suppression {
        targets := find_enemies_in_range(gs, player.pos, FOV_RANGE)
        enemy_bonus := len(targets) * 10
        if enemy_bonus > 0 {
            total_damage = int(f32(total_damage) * (1.0 + f32(enemy_bonus)/100.0))
            spawn_floating_text(
                gs,
                enemy.pos,
                fmt.tprintf("Crowd bonus: +%d%%!", enemy_bonus),
                v4{0.8, 0.5, 0.8, 1},
            )
        }
    }

    if gs.active_quest != nil && gs.active_quest.? == .Blood_Ritual {
        health_cost := 5
        if player.health > health_cost {
            player.health -= health_cost
            total_damage *= 2
            spawn_floating_text(
                gs,
                player.pos,
                fmt.tprintf("-%d HP", health_cost),
                v4{0.8, 0, 0, 1},
            )
        }
    }

    crit_chance := f32(player.upgrade_levels.crit_chance) * CRIT_CHANCE_PER_LEVEL
    if rand.float32() < crit_chance {
        crit_hit = true
        crit_multiplier := 1.5 + (f32(player.upgrade_levels.crit_damage) * CRIT_DAMAGE_PER_LEVEL)
        total_damage = int(f32(total_damage) * crit_multiplier)
    }

    life_steal_chance := f32(player.upgrade_levels.life_steal) * LIFE_STEAL_PER_LEVEL

    if rand.float32() < life_steal_chance && player.health < player.max_health {
        heal_amount := int(f32(total_damage) * 0.075)
        if projectile.is_multishot {
            heal_amount = int(f32(heal_amount) * 0.5)
        }

        heal_amount = max(1, heal_amount)
        heal_player(player, heal_amount)
    }

    enemy.health -= total_damage

    if crit_hit && gs.active_quest != nil && gs.active_quest.? == .Critical_Cascade {
        if rand.float32() < CRITICAL_CASCADE_RELOAD_CHANCE {
            player.attack_timer = 0
            spawn_floating_text(
                gs,
                player.pos,
                "Cascade Reload!",
                v4{1, 1, 0, 1},
            )
        }
    }

    text_color := crit_hit ? v4{1, 0, 0, 1} : COLOR_WHITE
    spawn_floating_text(gs, enemy.pos, fmt.tprintf("%d", total_damage), text_color)

    if enemy.health <= 0 {
        if gs.active_quest != nil && gs.active_quest.? == .Fortune_Seeker {
            if rand.float32() < 0.35 {
                spawn_floating_text(gs, enemy.pos, "Double rewards!", v4{1, 0.8, 0, 1})
                add_currency_points(gs, POINTS_PER_ENEMY)
                exp_multiplier := 1.0 + (f32(player.upgrade_levels.exp_gain) * EXP_GAIN_BONUS_PER_LEVEL)
                exp_amount := int(f32(EXPERIENCE_PER_ENEMY) * exp_multiplier)
                add_experience(gs, player, exp_amount)
            }
        }

        exp_multiplier := 1.0 + (f32(player.upgrade_levels.exp_gain) * EXP_GAIN_BONUS_PER_LEVEL)
        exp_amount := int(f32(EXPERIENCE_PER_ENEMY) * exp_multiplier)
        add_experience(gs, player, exp_amount)

        if gs.active_skill != nil{
            add_skill_experience(gs, EXPERIENCE_PER_ENEMY)
        }

        when_enemy_dies(gs, enemy)
        entity_destroy(gs, enemy)
    }
}

heal_player :: proc(player: ^Entity, amount: int) {
	player.health = min(player.health + amount, player.max_health)
}

//
// :waves
SPAWN_MARGIN :: 100
WAVE_SPAWN_RATE :: 2.0

init_wave_config :: proc() -> Wave_Config{
    return Wave_Config{
        base_enemy_count = 5,
        enemy_count_increase = 3,
        max_enemy_count = 30,
        base_difficulty = 1.0,
        difficulty_scale_factor = 0.25,

        health_scale = 0.08,
        damage_scale = 0.06,
        speed_scale = 0.02,
    }
}

init_wave :: proc(gs: ^Game_State, wave_number: int) {
    gs.wave_number = wave_number
    gs.wave_spawn_timer = WAVE_SPAWN_RATE
    gs.wave_spawn_rate = WAVE_SPAWN_RATE

    gs.enemies_to_spawn = calculate_wave_enemies(wave_number, gs.wave_config)
    gs.current_wave_difficulty = calculate_wave_difficulty(wave_number, gs.wave_config)

	gs.active_enemies = 0
	gs.wave_status = .WAITING
}

calculate_wave_enemies :: proc(wave_number: int, config: Wave_Config) -> int {
    if wave_number % 10 == 0{
        return 1
    }
    enemy_count := config.base_enemy_count + (wave_number - 1) * config.enemy_count_increase
    return min(enemy_count, config.max_enemy_count)
}

calculate_wave_difficulty :: proc(wave_number: int, config: Wave_Config) -> f32{
    difficulty_mult := 1.0 + math.log_f32(f32(wave_number), math.E) * config.difficulty_scale_factor
    return config.base_difficulty * difficulty_mult
}

process_wave :: proc(gs: ^Game_State, delta_t: f64) {
    if gs.wave_status != .IN_PROGRESS do return

    actual_active_enemies := 0
    for &en in gs.entities {
        if en.kind == .enemy && .allocated in en.flags {
            actual_active_enemies += 1
        }
    }

    if actual_active_enemies != gs.active_enemies {
        gs.active_enemies = actual_active_enemies
    }

    if gs.enemies_to_spawn <= 0 && gs.active_enemies <= 0 {
        gs.wave_status = .COMPLETED
        return
    }

    is_boss_wave := gs.wave_number % 10 == 0

    gs.wave_spawn_timer -= f32(delta_t)
    if gs.wave_spawn_timer <= 0 && gs.enemies_to_spawn > 0 {
        enemy := entity_create(gs)
        if enemy != nil {
            map_width := f32(WORLD_W * TILE_LENGTH)
            screen_half_width := map_width * 0.5
            spawn_position := screen_half_width + SPAWN_MARGIN

            spawn_x := rand.float32_range(
                rand.float32_range(spawn_position, spawn_position + SPAWN_MARGIN * 1.2),
                spawn_position + SPAWN_MARGIN * 1.2,
            )

            setup_enemy(enemy, v2{spawn_x, -550}, gs.current_wave_difficulty)
            gs.active_enemies += 1
        }

        gs.enemies_to_spawn -= 1
        gs.wave_spawn_timer = gs.wave_spawn_rate
    }
}

apply_elemental_effects :: proc(gs: ^Game_State, enemy: ^Entity, damage: int) {
    if gs.active_quest != nil && gs.active_quest.? == .Elemental_Rotation {
        player := find_player(gs)
        if player == nil do return

        #partial switch player.current_element {
            case .Fire:
                spawn_floating_text(
                    gs,
                    enemy.pos,
                    "Burning!",
                    v4{1, 0.5, 0, 1},
                )
                enemy.health -= damage / 4
            case .Ice:
                enemy.speed *= 0.5
                spawn_floating_text(
                    gs,
                    enemy.pos,
                    "Frozen!",
                    v4{0.5, 0.5, 1, 1},
                )
            case .Lightning:
                nearby := find_enemies_in_range(gs, enemy.pos, 150.0)
                if len(nearby) > 1 {
                    chain_target := nearby[1].entity
                    chain_target.health -= damage / 2
                    spawn_floating_text(
                        gs,
                        chain_target.pos,
                        "Chain Lightning",
                        v4{1, 1, 0, 1},
                    )
                }
        }

        player.current_element = Element_Kind((int(player.current_element) + 1) % len(Element_Kind))
        next_element := "Fire"
        if player.current_element == .Ice do next_element = "Ice"
        if player.current_element == .Lightning do next_element = "Lightning"

        spawn_floating_text(
            gs,
            player.pos,
            fmt.tprintf("Next: %s", next_element),
            v4{0.8, 0.8, 0.8, 1.0},
        )
    }
}

update_quest_progress :: proc(gs: ^Game_State) {
    if gs.active_quest == nil do return

    quest := &gs.quests[gs.active_quest.?]
    player := find_player(gs)
    if player == nil do return

    #partial switch quest.kind {
        case .Energy_Field:
            quest.progress = player.energy_field_charge
            quest.max_progress = ENERGY_FIELD_MAX_CHARGE
        // Add other progress tracking as needed
    }
}

//
// :IMAGE STUFF
//
Image_Id :: enum {
	nil,
	player_attack1,
	player_attack2,
	player_attack3,
	player_attack4,
	player_attack5,
	player_attack6,
	player_attack7,
	player_attack8,
	player_idle1,
	player_idle2,
	player_idle3,
	player_idle4,
	player_idle5,
	player_idle6,
	player_idle7,
	player_idle8,
	player_projectile,
	enemy1_10_1_move,
	enemy1_10_2_move,
	enemy1_10_3_move,
	enemy1_10_4_move,
	enemy1_10_5_move,
	enemy1_10_6_move,
	enemy1_10_7_move,
	enemy1_10_8_move,
	enemy1_10_1_attack,
	enemy1_10_2_attack,
	enemy1_10_3_attack,
	enemy1_10_4_attack,
	enemy1_10_5_attack,
	enemy1_10_6_attack,
	enemy1_10_7_attack,
	enemy1_10_8_attack,
	boss10,
	enemy11_19_1_move,
	enemy11_19_2_move,
	enemy11_19_3_move,
	enemy11_19_4_move,
	enemy11_19_5_move,
	enemy11_19_6_move,
	enemy11_19_7_move,
	enemy11_19_8_move,
	boss20,
}

Image :: struct {
	width, height: i32,
	tex_index:     u8,
	sg_img:        sg.Image,
	data:          [^]byte,
	atlas_uvs:     Vector4,
}
images: [512]Image
image_count: int

init_images :: proc() {
	using fmt

	img_dir := "./res/images/"

	highest_id := 0
	for img_name, id in Image_Id {
		if id == 0 {
		continue
	}

		if id > highest_id {
			highest_id = id
		}

		path := tprint(img_dir, img_name, ".png", sep = "")

		png_data, succ := os.read_entire_file(path)
        if !succ {
            continue
        }
		assert(succ)

		stbi.set_flip_vertically_on_load(1)
		width, height, channels: i32
		img_data := stbi.load_from_memory(
			raw_data(png_data),
			auto_cast len(png_data),
			&width,
			&height,
			&channels,
			4,
		)
		assert(img_data != nil, "stbi load failed, invalid image?")

		img: Image
		img.width = width
		img.height = height
		img.data = img_data

		images[id] = img
	}
	image_count = highest_id + 1
	pack_images_into_atlas()
}

Atlas :: struct {
	w, h:     int,
	sg_image: sg.Image,
}
atlas: Atlas

pack_images_into_atlas :: proc() {
    max_width := 0
    max_height := 0
    total_area := 0

    for img, id in images {
        if img.width == 0 do continue
        max_width = max(max_width, int(img.width))
        max_height = max(max_height, int(img.height))
        total_area += int(img.width) * int(img.height)
    }

    min_size := 128
    for min_size * min_size < total_area * 2 {
        min_size *= 2
    }

    atlas.w = min_size
    atlas.h = min_size

    nodes := make([dynamic]stbrp.Node, atlas.w)
    defer delete(nodes)

    cont: stbrp.Context
    stbrp.init_target(&cont, auto_cast atlas.w, auto_cast atlas.h, raw_data(nodes), auto_cast len(nodes))

    rects := make([dynamic]stbrp.Rect)
    defer delete(rects)

    for img, id in images {
        if img.width == 0 do continue
        rect := stbrp.Rect{
            id = auto_cast id,
            w = auto_cast img.width,
            h = auto_cast img.height,
        }
        append(&rects, rect)
    }

    if len(rects) == 0 {
        return
    }

    succ := stbrp.pack_rects(&cont, raw_data(rects), auto_cast len(rects))
    if succ == 0 {
        for rect, i in rects {
            fmt.printf("Rect %d: %dx%d = %d pixels\n",
                rect.id, rect.w, rect.h, rect.w * rect.h)
        }
        assert(false, "failed to pack all the rects, ran out of space?")
    }

    raw_data_size := atlas.w * atlas.h * 4
    atlas_data, err := mem.alloc(raw_data_size)
    if err != nil {
        return
    }
    defer mem.free(atlas_data)

    mem.set(atlas_data, 255, raw_data_size)

    for rect in rects {
        img := &images[rect.id]
        if img == nil || img.data == nil {
            continue
        }

        for row in 0 ..< rect.h {
            src_row := mem.ptr_offset(&img.data[0], row * rect.w * 4)
            dest_row := mem.ptr_offset(
                cast(^u8)atlas_data,
                ((rect.y + row) * auto_cast atlas.w + rect.x) * 4,
            )
            mem.copy(dest_row, src_row, auto_cast rect.w * 4)
        }

        stbi.image_free(img.data)
        img.data = nil

        img.atlas_uvs.x = cast(f32)rect.x / cast(f32)atlas.w
        img.atlas_uvs.y = cast(f32)rect.y / cast(f32)atlas.h
        img.atlas_uvs.z = img.atlas_uvs.x + cast(f32)img.width / cast(f32)atlas.w
        img.atlas_uvs.w = img.atlas_uvs.y + cast(f32)img.height / cast(f32)atlas.h
    }

    stbi.write_png(
        "atlases/atlas.png",
        auto_cast atlas.w,
        auto_cast atlas.h,
        4,
        atlas_data,
        4 * auto_cast atlas.w,
    )

    desc: sg.Image_Desc
    desc.width = auto_cast atlas.w
    desc.height = auto_cast atlas.h
    desc.pixel_format = .RGBA8
    desc.data.subimage[0][0] = {
        ptr = atlas_data,
        size = auto_cast raw_data_size,
    }

    atlas.sg_image = sg.make_image(desc)
    if atlas.sg_image.id == sg.INVALID_ID {
        log_error("failed to make image")
    }
}

//
// :FONT
//
draw_text :: proc(pos: Vector2, text: string, scale := 1.0, color := COLOR_WHITE) {
	using stbtt

	x: f32
	y: f32

	for char in text {
		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(
			&font.char_data[0],
			font_bitmap_w,
			font_bitmap_h,
			cast(i32)char - 32,
			&advance_x,
			&advance_y,
			&q,
			false,
		)

		size := v2{abs(q.x0 - q.x1), abs(q.y0 - q.y1)}

		bottom_left := v2{q.x0, -q.y1}
		top_right := v2{q.x1, -q.y0}
		assert(bottom_left + size == top_right)

		offset_to_render_at := v2{x, y} + bottom_left

		uv := v4{q.s0, q.t1, q.s1, q.t0}

		xform := Matrix4(1)
		xform *= xform_translate(pos)
		xform *= xform_scale(v2{auto_cast scale, auto_cast scale})
		xform *= xform_translate(offset_to_render_at)
		draw_rect_xform(xform, size, col = color, uv = uv, img_id = font.img_id)

		x += advance_x
		y += -advance_y
	}

}

font_bitmap_w :: 256
font_bitmap_h :: 256
char_count :: 96
Font :: struct {
	char_data: [char_count]stbtt.bakedchar,
	img_id:    Image_Id,
}
font: Font

init_fonts :: proc() {
	using stbtt

	bitmap, _ := mem.alloc(font_bitmap_w * font_bitmap_h)
	font_height := 15
	path := "./res/fonts/alagard.ttf"
	ttf_data, err := os.read_entire_file(path)
	assert(ttf_data != nil, "failed to read font")

	ret := BakeFontBitmap(
		raw_data(ttf_data),
		0,
		auto_cast font_height,
		auto_cast bitmap,
		font_bitmap_w,
		font_bitmap_h,
		32,
		char_count,
		&font.char_data[0],
	)
	assert(ret > 0, "not enough space in bitmap")

	stbi.write_png(
		"atlases/font.png",
		auto_cast font_bitmap_w,
		auto_cast font_bitmap_h,
		1,
		bitmap,
		auto_cast font_bitmap_w,
	)

	desc: sg.Image_Desc
	desc.width = auto_cast font_bitmap_w
	desc.height = auto_cast font_bitmap_h
	desc.pixel_format = .R8
	desc.data.subimage[0][0] = {
		ptr  = bitmap,
		size = auto_cast (font_bitmap_w * font_bitmap_h),
	}
	sg_img := sg.make_image(desc)
	if sg_img.id == sg.INVALID_ID {
		log_error("failed to make image")
	}

	id := store_image(font_bitmap_w, font_bitmap_h, 1, sg_img)
	font.img_id = id
}

store_image :: proc(w: int, h: int, tex_index: u8, sg_img: sg.Image) -> Image_Id {

	img: Image
	img.width = auto_cast w
	img.height = auto_cast h
	img.tex_index = tex_index
	img.sg_img = sg_img
	img.atlas_uvs = DEFAULT_UV

	id := image_count
	images[id] = img
	image_count += 1

	return auto_cast id
}

DEBUG_LINE_SPACING :: 30.0

draw_debug_stats :: proc(player: ^Entity, pos: Vector2){
    if player == nil do return

    draw_text(pos, "-- CURRENT STATS --", scale = 2.0)

    current_pos := pos + v2{0, -50}

    draw_text(current_pos, fmt.tprintf("Attack Speed: %.1f (Level %d)",
        player.attack_speed,
        player.upgrade_levels.attack_speed),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING
    draw_text(current_pos, fmt.tprintf("Damage: %d (Level %d)",
        player.damage,
        player.upgrade_levels.damage),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING
    draw_text(current_pos, fmt.tprintf("Crit Chance: %.1f%% (Level %d)",
        f32(player.upgrade_levels.crit_chance) * CRIT_CHANCE_PER_LEVEL * 100,
        player.upgrade_levels.crit_chance),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING
    draw_text(current_pos, fmt.tprintf("Crit Damage: +%.1f%% (Level %d)",
        (1.5 + f32(player.upgrade_levels.crit_damage) * CRIT_DAMAGE_PER_LEVEL - 1.0) * 100,
        player.upgrade_levels.crit_damage),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING
    draw_text(current_pos, fmt.tprintf("Accuracy: %.1f%% (Level %d)",
        (1.0 - (0.35 * (1.0 - f32(player.upgrade_levels.accuracy) * ACCURACY_BONUS_PER_LEVEL))) * 100,
        player.upgrade_levels.accuracy),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING * 2  // Extra space between sections
    draw_text(current_pos, fmt.tprintf("Life Steal: %.1f%% (Level %d)",
        f32(player.upgrade_levels.life_steal) * LIFE_STEAL_PER_LEVEL * 100,
        player.upgrade_levels.life_steal),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING
    draw_text(current_pos, fmt.tprintf("Health Regen: %.1f/s (Level %d)",
        f32(player.upgrade_levels.health_regen) * HEALTH_REGEN_PER_LEVEL,
        player.upgrade_levels.health_regen),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING
    draw_text(current_pos, fmt.tprintf("Dodge Chance: %.1f%% (Level %d)",
        f32(player.upgrade_levels.dodge_chance) * DODGE_CHANCE_PER_LEVEL * 100,
        player.upgrade_levels.dodge_chance),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING
    draw_text(current_pos, fmt.tprintf("FOV Range: %.0f (Level %d)",
        player.current_fov_range,
        player.upgrade_levels.fov_range),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING * 2  // Extra space between sections
    draw_text(current_pos, fmt.tprintf("Exp Gain: +%.1f%% (Level %d)",
        f32(player.upgrade_levels.exp_gain) * EXP_GAIN_BONUS_PER_LEVEL * 100,
        player.upgrade_levels.exp_gain),
        scale = 1.5)

    current_pos.y -= DEBUG_LINE_SPACING
    draw_text(current_pos, fmt.tprintf("Multishot Chance: %.1f%% (Level %d)",
        f32(player.upgrade_levels.multishot) * MULTISHOT_CHANCE_PER_LEVEL * 100,
        player.upgrade_levels.multishot),
        scale = 1.5)
}