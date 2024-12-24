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

window_w: i32 =  1280
window_h: i32 =  720

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

// #volatile with the map image dimensions
WORLD_W :: 128
WORLD_H :: 80

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
	png_data, succ := os.read_entire_file("./res/map.png")

	width, height, channels: i32
	img_data: [^]byte = stbi.load_from_memory(
		raw_data(png_data),
		auto_cast len(png_data),
		&width,
		&height,
		&channels,
		4,
	)

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
	visible_margin := 2
	min_x := max(0, 0)
	max_x := min(WORLD_W, WORLD_W)
	min_y := max(0, 0)
	max_y := min(WORLD_H, WORLD_H)

	for x := min_x; x < max_x; x += 1 {
		for y := min_y; y < max_y; y += 1 {
			tile_pos := array_tile_pos_to_world_tile(x, y)
			tile_pos_world := tile_pos_to_world_pos(tile_pos)
			tile := gs.tiles[x + y * WORLD_W]

            if tile.color.w > 0{
                draw_rect_aabb(
                    tile_pos_world,
                    v2{TILE_LENGTH, TILE_LENGTH},
                    col = tile.color,
                )
            }
		}
	}
}

first_time_init_game_state :: proc(gs: ^Game_State) {
	gs.state_kind = .MENU
    gs.wave_status = .WAITING

	gs.floating_texts = make([dynamic] Floating_Text)
    gs.floating_texts.allocator = context.allocator


    gs.wave_config = init_wave_config()
	load_map_into_tiles(gs.tiles[:])

	init_game_systems(gs)
}

init_game_systems :: proc(gs: ^Game_State){
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

    idle_frames: []Image_Id = {.player_idle1, .player_idle2, .player_idle3, .player_idle4, .player_idle5, .player_idle6, .player_idle7, .player_idle8, .player_idle8,.player_idle9,.player_idle10,.player_idle11,.player_idle12,.player_idle13,.player_idle14,.player_idle15,.player_idle16,.player_idle17,.player_idle18,.player_idle19}
    idle_anim := create_animation(idle_frames, 0.1, true, "idle")

    shoot_frames: []Image_Id = {.player_attack1, .player_attack2, .player_attack3, .player_attack4, .player_attack5, .player_attack6}
	shoot_anim := create_animation(shoot_frames, 0.1, false, "attack")

	add_animation(&e.animations, shoot_anim)
	add_animation(&e.animations, idle_anim)
	play_animation_by_name(&e.animations, "idle")

    if app_state.game.active_quest != nil && app_state.game.active_quest.? == .Risk_Reward {
        current_health := e.health
        current_damage := e.damage
        e.health = current_health / 2 // half of the current health of the player
        e.max_health = e.max_health / 2 // half of the starting max health
        e.damage = current_damage * 2
    }else{
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

    enemy_move_frames: []Image_Id = {.enemy1_10_1,.enemy1_10_2,.enemy1_10_3,.enemy1_10_4,.enemy1_10_5,.enemy1_10_6,.enemy1_10_7,.enemy1_10_8}
    enemy_move_anim := create_animation(enemy_move_frames, 0.1, true, "enemy_move")
	add_animation(&e.animations, enemy_move_anim)
	play_animation_by_name(&e.animations, "enemy_move")

	base_health := 15
	base_damage := 5
	base_speed := 100.0

	config := app_state.game.wave_config
	wave_num := f32(app_state.game.wave_number)

	health_mult := 1.0 + (config.health_scale * wave_num)
	damage_mult := 1.0 + (config.damage_scale * wave_num)
	speed_mult := 1.0 + (config.speed_scale * wave_num)

	if is_boss_wave {
	   health_mult *= BOSS_STATS_MULTIPLIER
	   damage_mult *= BOSS_STATS_MULTIPLIER
	   speed_mult *= 0.5

	   if is_first_boss {
	       e.enemy_type = 10
	       e.value = 50
	   }
	}else{
	   e.enemy_type = 1
	   e.value = 1
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
    spawn_floating_text(gs, player.pos, exp_text, v4{0.3, 0.8, 0.3,1.0})

	player.experience += final_exp
	exp_needed := calculate_exp_for_level(player.level)

	for player.experience >= exp_needed {
		player.experience -= exp_needed
		player.level += 1
		exp_needed = calculate_exp_for_level(player.level)
		check_quest_unlocks(gs,player)
	}
}

add_currency_points :: proc(gs: ^Game_State, points: int) {
	multiplier := 1.0

    if gs.active_quest != nil{
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

		if key_just_pressed(app_state.input_state, .L){
            player := find_player(gs)
            if player != nil {
                for i in 0..<5 {
                    player.level += 1
                }
                check_quest_unlocks(gs, player)

                spawn_floating_text(
                    gs,
                    player.pos,
                    "DEBUG: Added 5 levels!",
                    v4{1, 1, 0, 1},
                )
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
	    for i < len(gs.floating_texts){
	       text := &gs.floating_texts[i]
	       text.lifetime -= f32(delta_t)
	       text.pos += text.velocity * f32(delta_t) * 100.0

	       if text.lifetime <= 0{
	           delete(text.text)
	           ordered_remove(&gs.floating_texts, i)
	       }else{
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
                    if en.upgrade_levels.health_regen > 0{
                        heal_player(&en, 1)

                        base_regen_time := 10.0
                        level_reduction := f32(en.upgrade_levels.health_regen) * HEALTH_REGEN_PER_LEVEL
                        actual_regen_time := math.max(f32(base_regen_time) - level_reduction, 1.0)

                        en.health_regen_timer = actual_regen_time
                    }else{
                        en.health_regen_timer = 10.0
                    }
				}

				en.attack_timer -= f32(delta_t)

				targets := find_enemies_in_range(gs, en.pos, FOV_RANGE)

				if en.attack_timer <= 0 && len(targets) > 0 {
					closest_enemy := targets[0].entity
					projectile := entity_create(gs)
					if projectile != nil {
						setup_projectile(gs, projectile, en.pos, closest_enemy.pos)
						play_sound("shoot")
                        play_animation_by_name(&en.animations, "attack")
					}
					en.attack_timer = 1.0 / en.attack_speed
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

	    for &en in gs.entities{
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

	map_width := f32(WORLD_W * TILE_LENGTH) // 2048
	map_height := f32(WORLD_H * TILE_LENGTH) // 1280

	scale_x := window_w / i32(map_width)
	scale_y := window_h / i32(map_height)
	scale := min(scale_x, scale_y)

	draw_frame.projection = matrix_ortho3d_f32(
		-map_width * 0.5, // left
		map_width * 0.5, // right
		-map_height * 0.5, // bottom
		map_height * 0.5, // top
		-1,
		1,
	)

	// :camera
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
				level_text := fmt.tprintf("Current Level: %d - (%d/%d)", en.level, current_exp,  exp_needed)
				draw_text(ui_base_pos, level_text, scale = 2.0)

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -50}, currency_text, scale = 2.0)

				health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
				draw_text(ui_base_pos + v2{0, -100}, health_text, scale = 2.0)

				enemies_remaining_text := fmt.tprintf("Enemies: %d/%d", gs.active_enemies, gs.enemies_to_spawn)
                draw_text(ui_base_pos + v2{0, -150}, enemies_remaining_text, scale = 2.0)
				break
			}
		}

        draw_wave_button(gs)
        draw_skills_button(gs)
        draw_shop_button(gs)
        draw_quest_button(gs)

	    for text in gs.floating_texts{
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
				} else if en.kind == .player_projectile{
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
				level_text := fmt.tprintf("Current Level: %d - (%d/%d)", en.level, current_exp,  exp_needed)
				draw_text(ui_base_pos, level_text, scale = 2.0)

                currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
                draw_text(ui_base_pos + v2{0, -50}, currency_text, scale = 2.0)

                health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
                draw_text(ui_base_pos + v2{0, -100}, health_text, scale = 2.0)

                enemies_remaining_text := fmt.tprintf("Enemies: %d/%d", gs.active_enemies, gs.enemies_to_spawn)
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
				level_text := fmt.tprintf("Current Level: %d - (%d/%d)", en.level, current_exp,  exp_needed)
				draw_text(ui_base_pos, level_text, scale = 2.0)

                currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
                draw_text(ui_base_pos + v2{0, -50}, currency_text, scale = 2.0)

                health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
                draw_text(ui_base_pos + v2{0, -100}, health_text, scale = 2.0)

                enemies_remaining_text := fmt.tprintf("Enemies: %d/%d", gs.active_enemies, gs.enemies_to_spawn)
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
	img := Image_Id.enemy1_10_1

	if en.enemy_type == 10{
	   img = .boss10
	}

	xform := Matrix4(1)

	if en.enemy_type == 10{
	   xform *= xform_scale(v2{5,5})
	}else{
	   xform *= xform_scale(v2{4, 4})
	}

	draw_current_animation(&en.animations, en.pos, pivot = .bottom_center, xform = xform)
}

draw_player_projectile_at_pos :: proc(en: Entity, pos: Vector2){
    img := Image_Id.player_projectile

    angle := math.atan2(en.direction.y, en.direction.x)
    final_angle := math.to_degrees(angle)

    xform := Matrix4(1)
    xform *= xform_rotate(final_angle)
    xform *= xform_scale(v2{4,4})

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

init_skills :: proc(gs: ^Game_State){
    for kind in Skill_Kind{
        gs.skills[kind] = Skill{
            kind = kind,
            level = 1,
            experience = 0,
            unlocked = false,
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
                    spawn_floating_text(gs, player.pos, fmt.tprintf("%v skill unlocked!", kind), v4{0, 1, 0, 1})
                }
            case .attack_speed:
                if player.upgrade_levels.attack_speed >= MAX_UPGRADE_LEVEL {
                    gs.skills[kind].unlocked = true
                    spawn_floating_text(gs, player.pos, fmt.tprintf("%v skill unlocked!", kind), v4{0, 1, 0, 1})
                }
            case .armor:
                if player.upgrade_levels.armor >= MAX_UPGRADE_LEVEL {
                    gs.skills[kind].unlocked = true
                    spawn_floating_text(gs, player.pos, fmt.tprintf("%v skill unlocked!", kind), v4{0, 1, 0, 1})
                }
            case .life_steal:
                if player.upgrade_levels.life_steal >= MAX_UPGRADE_LEVEL {
                    gs.skills[kind].unlocked = true
                    spawn_floating_text(gs, player.pos, fmt.tprintf("%v skill unlocked!", kind), v4{0, 1, 0, 1})
                }
            case .crit_damage:
                if player.upgrade_levels.crit_damage >= MAX_UPGRADE_LEVEL {
                    gs.skills[kind].unlocked = true
                    spawn_floating_text(gs, player.pos, fmt.tprintf("%v skill unlocked!", kind), v4{0, 1, 0, 1})
                }
            case .health_regen:
                if player.upgrade_levels.health_regen >= MAX_UPGRADE_LEVEL {
                    gs.skills[kind].unlocked = true
                    spawn_floating_text(gs, player.pos, fmt.tprintf("%v skill unlocked!", kind), v4{0, 1, 0, 1})
                }
        }
    }
}

calculate_skill_experience_requirement :: proc(level: int) -> int{
    return int(f32(SKILL_BASE_EXPERIENCE) * math.pow(SKILL_EXPERIENCE_SCALE, f32(level - 1)))
}

add_skill_experience :: proc(gs: ^Game_State, exp_amount: int){
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
            v4{1,1,0,1},
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
        // No direct modification needed - life steal is applied in combat
    case .crit_damage:
        // No direct modification needed - crit damage is calculated in combat
    case .health_regen:
        // No direct modification needed - health regen is calculated in update
    }
}

get_skill_progress :: proc(skill: Skill) -> f32{
    if skill.experience == 0 do return 0

    exp_needed := calculate_skill_experience_requirement(skill.level)
    return f32(skill.experience) / f32(exp_needed)
}

//
// : Quest

QUEST_INFO := map[Quest_Kind]Quest_Info{
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

init_quests :: proc(gs: ^Game_State){
    gs.quests = make(map[Quest_Kind]Quest)

    for kind, info in QUEST_INFO{
        gs.quests[kind] = Quest{
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

try_purchase_quest :: proc(gs: ^Game_State, kind: Quest_Kind) -> bool{
    quest := &gs.quests[kind]
    info := QUEST_INFO[kind]

    if quest.state != .Available do return false
    if gs.currency_points < info.base_cost do return false

    gs.currency_points -= info.base_cost
    quest.state = .Purchased

    spawn_floating_text(gs, player_pos(gs),
        fmt.tprintf("Quest Purchased: %v!", kind),
        v4{0.8, 0.3, 0.8, 1.0})

    return true
}

check_quest_unlocks :: proc(gs: ^Game_State, player: ^Entity) {
    if player == nil do return

    for kind, info in QUEST_INFO {
        quest := &gs.quests[kind]
        if quest.state == .Locked && player.level >= info.unlock_level {
            quest.state = .Available
            spawn_floating_text(gs, player.pos,
                fmt.tprintf("New Quest Available: %v!", kind),
                v4{0.3, 0.8, 0.3, 1.0})
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

    if kind == .Elemental_Rotation{
        player := find_player(gs)
        if player != nil{
            player.current_element = .Fire
            spawn_floating_text(
                gs,
                player.pos,
                "Elemental Rotation Active: Starting With Fire!",
                v4{1, 0.5, 0, 1}
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
            // Will need special handling in setup_projectile
            quest.effects.damage_mult = 0.8  // Lower damage since we'll fire more projectiles
        case .Critical_Cascade:
            quest.effects.attack_speed_mult = 1.2
            quest.effects.damage_mult = 1.2
        case .Priority_Target:
            // Will need special handling in when_projectile_hits_enemy
            quest.effects.damage_mult = 1.4
        case .Sniper_Protocol:
            // Will need special handling in when_projectile_hits_enemy
            quest.effects.damage_mult = 1.5
            quest.effects.attack_speed_mult = 0.8
        case .Crowd_Suppression:
            // Will need special handling in when_projectile_hits_enemy
            quest.effects.damage_mult = 1.0  // Base damage, will increase with enemy count
        case .Elemental_Rotation:
            // Will need special handling in setup_projectile
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
        damage_mult = 1.0,
        attack_speed_mult = 1.0,
        currency_mult = 1.0,
        health_mult = 1.0,
        experience_mult = 1.0,
    }
}

player_pos :: proc(gs: ^Game_State) -> Vector2 {
    player := find_player(gs)
    return player != nil ? player.pos : Vector2{}
}

//
// :animations
create_animation :: proc(frames: []Image_Id, frame_duration: f32, loops: bool, name: string) -> Animation {
    fmt.println("Creating animation:", name)

    // Create a persistent copy of the frames
    frames_copy := make([]Image_Id, len(frames), context.allocator)
    copy(frames_copy[:], frames)

    fmt.println("Copied frames:")
    for frame, i in frames_copy {
        fmt.println("Frame", i, ":", frame)
    }

    return Animation{
        frames = frames_copy,
        current_frame = 0,
        frame_duration = frame_duration,
        frame_timer = 0,
        state = .Stopped,
        loops = loops,
        name = name,
    }
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

draw_animated_sprite :: proc(pos: Vector2, anim: ^Animation, pivot := Pivot.bottom_left, xform := Matrix4(1)){
    if anim == nil do return
    current_frame := get_current_frame(anim)
    draw_sprite(pos, current_frame, pivot, xform)
}

play_animation :: proc(anim: ^Animation){
    if anim == nil do return
    anim.state = .Playing
}

pause_animation :: proc(anim: ^Animation){
    if anim == nil do return
    anim.state = .Paused
}

stop_animation :: proc(anim: ^Animation) {
    if anim == nil do return
    anim.state = .Stopped
    anim.current_frame = 0
    anim.frame_timer = 0
}

reset_animation :: proc(anim: ^Animation){
    if anim == nil do return
    anim.current_frame = 0
    anim.frame_timer = 0
}

create_animation_collection :: proc() -> Animation_Collection {
    return Animation_Collection{
        animations = make(map[string]Animation),
        current_animation = "",
    }
}

add_animation :: proc(collection: ^Animation_Collection, animation: Animation){
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
            if animation_finished && collection.current_animation == "attack"{
                play_animation_by_name(collection, "idle")
            }
            //update_animation(anim, delta_t)
        }
    }
}

draw_current_animation :: proc(collection: ^Animation_Collection, pos: Vector2, pivot := Pivot.bottom_left, xform := Matrix4(1)) {
    if collection == nil || collection.current_animation == "" do return
    if anim, ok := &collection.animations[collection.current_animation]; ok {
        draw_animated_sprite(pos, anim, pivot, xform)
    }
}

load_animation_frames :: proc(directory: string, prefix: string) -> ([]Image_Id, bool) {
    frames: [dynamic]Image_Id
    frames.allocator = context.temp_allocator

    // Convert string to cstring for the API
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
            case "player_attack1": frame_id = .player_attack1
            case "player_attack2": frame_id = .player_attack2
            case "player_attack3": frame_id = .player_attack3
            case "player_attack4": frame_id = .player_attack4
            case "player_attack5": frame_id = .player_attack5
            case "player_attack6": frame_id = .player_attack6
            case: continue
        }

        append(&frames, frame_id)
    }

    if len(frames) == 0 {
        log_error("No frames found for animation:", prefix)
        return nil, false
    }

    return frames[:], true
}