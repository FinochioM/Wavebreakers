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
import "core:encoding/json"
import "core:time"

import sapp "../sokol/app"
import sg "../sokol/gfx"
import sglue "../sokol/glue"
import slog "../sokol/log"

import stbi "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"
import stbtt "vendor:stb/truetype"

window_w :: 1280
window_h :: 720

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

first_time_init_game_state :: proc(gs: ^Game_State) {
	gs.state_kind = .MENU
    gs.wave_status = .WAITING

	gs.floating_texts = make([dynamic] Floating_Text)
    gs.floating_texts.allocator = context.allocator


    gs.wave_config = init_wave_config()

    gs.ui_hot_reload = init_ui_hot_reload()

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
FOV_RANGE_BONUS_PER_LEVEL :: 2.0
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

	e.pos = v2{-200, -115}
	e.animations = create_animation_collection()

    idle_frames: []Image_Id = {.player_idle1, .player_idle2, .player_idle3, .player_idle4, .player_idle5, .player_idle6, .player_idle7, .player_idle8}
    idle_anim := create_animation(idle_frames, 0.1, true, "idle")

    shoot_frames: []Image_Id = {.player_attack1, .player_attack2, .player_attack3, .player_attack4, .player_attack5, .player_attack6, .player_attack7, .player_attack8}
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
    }else{
	   e.health = 100
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
    wave_num := app_state.game.wave_number

    e.animations = create_animation_collection()

    if is_boss_wave {
        if wave_num == 10 {
            e.enemy_type = 10
            e.value = 50
            boss10_move_frames: []Image_Id = {
                .boss10_run_1, .boss10_run_2, .boss10_run_3, .boss10_run_4,
                .boss10_run_5, .boss10_run_6, .boss10_run_7, .boss10_run_8,
            }
            boss10_move_anim := create_animation(boss10_move_frames, 0.1, true, "boss10_move")

            boss10_attack_frames: []Image_Id = {
                .boss10_attack_1, .boss10_attack_2, .boss10_attack_3, .boss10_attack_4,
                .boss10_attack_5, .boss10_attack_6, .boss10_attack_7, .boss10_attack_8,
            }
            boss10_attack_anim := create_animation(boss10_attack_frames, 0.1, false, "boss10_attack1")

            boss10_attack2_frames: []Image_Id = {
                .boss10_attack2_1, .boss10_attack2_2, .boss10_attack2_3, .boss10_attack2_4,
                .boss10_attack2_5, .boss10_attack2_6, .boss10_attack2_7, .boss10_attack2_8,
            }
            boss10_attack2_anim := create_animation(boss10_attack2_frames, 0.1, false, "boss10_attack2")

            add_animation(&e.animations, boss10_move_anim)
            add_animation(&e.animations, boss10_attack_anim)
            add_animation(&e.animations, boss10_attack2_anim)
        }else if wave_num == 20 {
            e.enemy_type = 20
            e.value = 100
            draw_sprite(pos, .boss20, pivot = .bottom_center)
        }
    }else{
        if wave_num <= 10{
            e.enemy_type = 1
            enemy_move_frames: []Image_Id = {
                .enemy1_10_1_move,.enemy1_10_2_move,.enemy1_10_3_move,.enemy1_10_4_move,
                .enemy1_10_5_move,.enemy1_10_6_move,.enemy1_10_7_move,.enemy1_10_8_move
            }
            enemy_move_anim := create_animation(enemy_move_frames, 0.1, true, "enemy1_10_move")

            enemy_attack_frames: []Image_Id = {
                .enemy1_10_1_attack,.enemy1_10_2_attack,.enemy1_10_3_attack,.enemy1_10_4_attack,
                .enemy1_10_5_attack,.enemy1_10_6_attack,.enemy1_10_7_attack,.enemy1_10_8_attack
            }
            enemy_attack_anim := create_animation(enemy_attack_frames, 0.1, false, "enemy1_10_attack")

            enemy_hit_frames: []Image_Id = {
                .enemy1_10_hit1, .enemy1_10_hit2, .enemy1_10_hit3, .enemy1_10_hit4,
            }
            enemy_hit_anim := create_animation(enemy_hit_frames, 0.1, false, "enemy1_10_hit")

        	add_animation(&e.animations, enemy_move_anim)
        	add_animation(&e.animations, enemy_attack_anim)
        	add_animation(&e.animations, enemy_hit_anim)
        }else if wave_num <= 20{
            e.enemy_type = 2
            enemy2_move_frames: []Image_Id = {
                .enemy11_19_1_move, .enemy11_19_2_move, .enemy11_19_3_move, .enemy11_19_4_move,
                .enemy11_19_5_move, .enemy11_19_6_move, .enemy11_19_7_move, .enemy11_19_8_move,
            }
            enemy2_move_anim := create_animation(enemy2_move_frames, 0.14, true, "enemy11_19_move")

            add_animation(&e.animations, enemy2_move_anim)
        }

        e.value = e.enemy_type * 2
    }

    base_health := 15 + (e.enemy_type - 1) * 10
    base_damage := 5 + (e.enemy_type - 1) * 3
    base_speed := 25.0 - f32(e.enemy_type - 1) * 10.0

    config := app_state.game.wave_config
    wave_num_32 := f32(app_state.game.wave_number)

    health_mult := 1.0 + (config.health_scale * wave_num_32)
    damage_mult := 1.0 + (config.damage_scale * wave_num_32)
    speed_mult := 1.0 + (config.speed_scale * wave_num_32)

    if is_boss_wave {
        health_mult *= BOSS_STATS_MULTIPLIER
        damage_mult *= BOSS_STATS_MULTIPLIER
        speed_mult *= 0.8
    }

    e.pos = pos
    e.prev_pos = pos
    e.health = int(f32(base_health) * health_mult * difficulty)
    e.max_health = e.health
    e.attack_timer = 0.0
    e.damage = int(f32(base_damage) * damage_mult * difficulty)
    e.state = .moving
    e.speed = abs(f32(base_speed)) * speed_mult
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

FOV_RANGE :: 200.0 // Range in which the player can detect enemies

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
    gs.currency_points = 0
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

calculate_collision :: proc() {
    // CALCULATE DIMENSIONS DINAMICALLY WITH SWITCH
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
                    play_animation_by_name(&en.animations, "attack")

                    if anim, ok := &en.animations.animations["attack"]; ok{
                        adjust_animation_to_speed(anim, en.attack_speed)
                    }

    				if should_spawn_projectile(&en) && len(targets) > 0{
    					closest_enemy := targets[0].entity
        				projectile := entity_create(gs)
        				if projectile != nil {
        					setup_projectile(gs, projectile, en.pos, closest_enemy.pos)
        					play_sound("projectile")
        				}
        				en.attack_timer = 1.0 / en.attack_speed
				    }
				}

			}
			if en.kind == .enemy {
				process_enemy_behaviour(&en, gs, f32(delta_t))
			    if en.hit_state.is_hit {
                    en.hit_state.hit_timer -= f32(delta_t)
                    if en.hit_state.hit_timer <= 0 {
                        en.hit_state.is_hit = false
                        en.hit_state.hit_timer = 0
                        en.hit_state.color_override = v4{1,1,1,0}
                    }
                }
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
						collision_radius := target.enemy_type == 10 ? 100.0 : 25.0 // TODO TODO TODO
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

game_res_w :: 512
game_res_h :: 256

render_gameplay :: proc(gs: ^Game_State, input_state: Input_State) {
	using linalg
	player: Entity

    draw_frame.projection = matrix_ortho3d_f32(window_w * -0.5,
        window_w * 0.5, window_h * -0.5, window_h * 0.5, -1, 1)

    draw_frame.camera_xform = Matrix4(1)
    draw_frame.camera_xform *= xform_scale(f32(window_h) / f32(game_res_h))

	alpha := f32(accumulator) / f32(sims_per_second)



	#partial switch gs.state_kind {
	case .MENU:
       // draw_rect_aabb(v2{ game_res_w * -0.5, game_res_h * -0.5}, v2{game_res_w, game_res_h}, img_id=.background_map)
		draw_menu(gs)
	case .PLAYING:
        draw_rect_aabb(v2{ game_res_w * -0.5, game_res_h * -0.5}, v2{game_res_w, game_res_h}, img_id=.background_map1)
		for en in gs.entities {
			if en.kind == .player {
				player = en
				break
			}
		}

		for &en in gs.entities {
			#partial switch en.kind {
			case .player:
				draw_player(&en)
			case .enemy, .player_projectile:
				render_pos := linalg.lerp(en.prev_pos, en.pos, alpha)
				hit_color_override := gs.hit_color_override

				if en.kind == .enemy {
					draw_enemy_at_pos(&en, render_pos)
				} else if en.kind == .player_projectile {
					draw_player_projectile_at_pos(en, render_pos)
				}
			}
		}

		for &en in gs.entities {
			if en.kind == .player {
				ui_base_pos := v2{-220, 120}

                exp_needed := calculate_exp_for_level(en.level)
                current_exp := en.experience
				level_text := fmt.tprintf("Current Level: %d - (%d/%d)", en.level, current_exp,  exp_needed)
				draw_text(ui_base_pos, level_text, scale = 0.4)

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -10}, currency_text, scale = 0.4)

				health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
				draw_text(ui_base_pos + v2{0, -20}, health_text, scale = 0.4)

				enemies_remaining_text := fmt.tprintf("Enemies: %d/%d", gs.active_enemies, gs.enemies_to_spawn)
                draw_text(ui_base_pos + v2{0, -30}, enemies_remaining_text, scale = 0.4)
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
	       draw_text(text.pos, text.text, scale = 0.4, color = color)
	    }
        draw_rect_aabb(v2{ game_res_w * -0.5, game_res_h * -0.5}, v2{game_res_w, game_res_h}, img_id=.background_map0)
	case .PAUSED:
        draw_rect_aabb(v2{ game_res_w * -0.5, game_res_h * -0.5}, v2{game_res_w, game_res_h}, img_id=.background_map1)

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
        draw_rect_aabb(v2{ game_res_w * -0.5, game_res_h * -0.5}, v2{game_res_w, game_res_h}, img_id=.background_map1)
        for en in gs.entities {
            if en.kind == .player {
                player = en
                break
            }
        }

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
				ui_base_pos := v2{-220, 120}

                exp_needed := calculate_exp_for_level(en.level)
                current_exp := en.experience
				level_text := fmt.tprintf("Current Level: %d - (%d/%d)", en.level, current_exp,  exp_needed)
				draw_text(ui_base_pos, level_text, scale = 0.4)

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -10}, currency_text, scale = 0.4)

				health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
				draw_text(ui_base_pos + v2{0, -20}, health_text, scale = 0.4)

				enemies_remaining_text := fmt.tprintf("Enemies: %d/%d", gs.active_enemies, gs.enemies_to_spawn)
                draw_text(ui_base_pos + v2{0, -30}, enemies_remaining_text, scale = 0.4)
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
        draw_rect_aabb(v2{ game_res_w * -0.5, game_res_h * -0.5}, v2{game_res_w, game_res_h}, img_id=.background_map0)
    case .SKILLS:
        draw_rect_aabb(v2{ game_res_w * -0.5, game_res_h * -0.5}, v2{game_res_w, game_res_h}, img_id=.background_map1)
        for en in gs.entities {
            if en.kind == .player {
                player = en
                break
            }
        }

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
				ui_base_pos := v2{-220, 120}

                exp_needed := calculate_exp_for_level(en.level)
                current_exp := en.experience
				level_text := fmt.tprintf("Current Level: %d - (%d/%d)", en.level, current_exp,  exp_needed)
				draw_text(ui_base_pos, level_text, scale = 0.4)

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -10}, currency_text, scale = 0.4)

				health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
				draw_text(ui_base_pos + v2{0, -20}, health_text, scale = 0.4)

				enemies_remaining_text := fmt.tprintf("Enemies: %d/%d", gs.active_enemies, gs.enemies_to_spawn)
                draw_text(ui_base_pos + v2{0, -30}, enemies_remaining_text, scale = 0.4)
				break
            }
        }

        for text in gs.floating_texts {
            text_alpha := text.lifetime / text.max_lifetime
            color := text.color
            color.w = text_alpha
            draw_text(text.pos, text.text, scale = 0.4, color = color)
        }

        draw_skills_menu(gs)
        draw_rect_aabb(v2{ game_res_w * -0.5, game_res_h * -0.5}, v2{game_res_w, game_res_h}, img_id=.background_map0)
	}
}

draw_player :: proc(en: ^Entity) {
    xform := Matrix4(1)
    xform *= xform_scale(v2{0.62, 0.62})

    draw_current_animation(&en.animations, en.pos, pivot = .bottom_center, xform = xform)
}

draw_enemy_at_pos :: proc(en: ^Entity, pos: Vector2) {
	xform := Matrix4(1)

	if en.enemy_type == 10 || en.enemy_type == 20{
	   xform *= xform_scale(v2{1,1})
	}else{
	   xform *= xform_scale(v2{0.7, 0.7})
	}

	draw_current_animation(&en.animations, en.pos, pivot = .bottom_center, xform = xform, color_override = en.hit_state.color_override)
}

should_spawn_projectile :: proc(en: ^Entity) -> bool {
    if en.animations.current_animation != "attack" do return false

    if anim, ok := en.animations.animations["attack"]; ok {
        return anim.current_frame == 7
    }
    return false
}

draw_player_projectile_at_pos :: proc(en: Entity, pos: Vector2){
    img := Image_Id.player_projectile

    angle := math.atan2(en.direction.y, en.direction.x)
    final_angle := math.to_degrees(angle)

    xform := Matrix4(1)
    xform *= xform_rotate(final_angle)
    xform *= xform_scale(v2{0.62,0.62})

    draw_sprite(pos, img, pivot = .bottom_center, xform = xform)
}

screen_to_world_pos :: proc(screen_pos: Vector2) -> Vector2 {
    map_width := 512.0
    map_height := 256.0

    scale_x := f32(window_w) / auto_cast map_width
    scale_y := f32(window_h) / auto_cast map_height
    scale := min(scale_x, scale_y)

    viewport_width := auto_cast map_width * auto_cast scale
    viewport_height := auto_cast map_height * auto_cast scale
    offset_x := (f32(window_w) - auto_cast viewport_width) * 0.5
    offset_y := (f32(window_h) - auto_cast viewport_height) * 0.5

    adjusted_x := (screen_pos.x - offset_x) / scale
    adjusted_y := (screen_pos.y - offset_y) / scale

    world_x := adjusted_x - auto_cast map_width * 0.5
    world_y := auto_cast map_height * 0.5 - auto_cast adjusted_y

    return Vector2{world_x, auto_cast world_y}
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
    frames_copy := make([]Image_Id, len(frames), context.allocator)
    copy(frames_copy[:], frames)

    return Animation{
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

adjust_animation_to_speed :: proc(anim:  ^Animation, speed_multiplier: f32) {
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

draw_animated_sprite :: proc(pos: Vector2, anim: ^Animation, pivot := Pivot.bottom_left, xform := Matrix4(1), color_override := v4{0,0,0,0}){
    if anim == nil do return
    current_frame := get_current_frame(anim)
    draw_sprite(pos, current_frame, pivot, xform, color_override)
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

reset_and_play_animation :: proc(collection: ^Animation_Collection, name: string, speed: f32 = 1.0){
    if collection == nil do return

    if anim, ok := &collection.animations[name]; ok{
        anim.current_frame = 0
        anim.frame_timer = 0
        anim.state = .Playing
        anim.loops = false
        adjust_animation_to_speed(anim, speed)

        collection.current_animation = name
    }
}

update_current_animation :: proc(collection: ^Animation_Collection, delta_t: f32) {
    if collection.current_animation != "" {
        if anim, ok := &collection.animations[collection.current_animation]; ok {
            animation_finished := update_animation(anim, delta_t)
            if animation_finished && collection.current_animation == "attack"{
                play_animation_by_name(collection, "idle")
            }
        }
    }
}

draw_current_animation :: proc(collection: ^Animation_Collection, pos: Vector2, pivot := Pivot.bottom_left, xform := Matrix4(1), color_override := v4{0,0,0,0}) {
    if collection == nil || collection.current_animation == "" {
        fmt.println("Warning: Empty animation collection or no current animation")
        return
    }
    if anim, ok := &collection.animations[collection.current_animation]; ok {
        draw_animated_sprite(pos, anim, pivot, xform, color_override)
    }else {
        fmt.println("Warning: Animation not found in collection:", collection.current_animation)
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

init_ui_hot_reload :: proc() -> UI_Hot_Reload {
    hr := UI_Hot_Reload{
        config_path = "A:/Desarrollos/1WeekGame/game/config/ui_config.json",
        config = UI_Config{
            // General menu
            menu_button_width = 40.0,
            menu_button_height = 20.0,
            pause_menu_button_width = 50.0,
            pause_menu_button_height = 20.0,
            pause_menu_spacing = 10.0,

            // Wave button
            wave_button_width = 45.0,
            wave_button_height = 15.0,

            // Shop menu
            shop_panel_width = 512.0,
            shop_panel_height = 256.0,
            shop_title_offset_x = 150.0,
            shop_title_offset_y = 80.0,
            shop_content_padding = 160.0,
            shop_button_spacing_y = 20.0,
            shop_row_start_offset = 150.0,
            shop_column_start_offset = 80.0,
            shop_text_scale_title = 1.2,
            shop_text_scale_currency = 0.7,
            shop_text_scale_button = 0.4,
            shop_text_scale_upgrade = 0.4,
            shop_button_width = 50.0,
            shop_button_height = 20.0,
            shop_button_vertical_padding = 10.0,
            shop_upgrade_text_offset_y = 45.0,
            shop_max_text_offset_x = 10.0,
            shop_max_text_offset_y = 5.0,
            shop_back_button_offset_y = 80.0,
            shop_back_button_width = 0.0,
            shop_back_button_height = 0.0,
            shop_back_button_text_scale = 0.0,
            shop_currency_text_offset_x = 0.0,
            shop_currency_text_offset_y = 0.0,
            shop_currency_text_scale = 0.0,
            skills_back_button_y = 0.0,
            skills_back_button_x = 0.0,

            // Skills menu
            skills_panel_width = 0.0,
            skills_panel_height = 0.0,
            skills_title_offset_x = 0.0,
            skills_title_offset_y = 0.0,
            skills_title_text_scale = 0.0,
            skills_entry_padding_x = 0.0,
            skills_entry_height = 0.0,
            skills_entry_spacing = 0.0,
            skills_entry_text_offset_x = 0.0,
            skills_entry_text_offset_y = 0.0,
            skills_entry_text_scale = 0.0,
            skills_progress_bar_height = 0.0,
            skills_progress_bar_offset_bottom = 0.0,
            skills_progress_bar_padding_x = 0.0,
            skills_scrollbar_width = 0.0,
            skills_scrollbar_offset_right = 0.0,
            skills_scrollbar_padding_y = 0.0,
            skills_content_top_offset = 0.0,
            skills_content_bottom_offset = 0.0,
            skills_scroll_speed = 0.0,

            quest_button_width = 30.0,
            quest_button_height = 10.0,
            quest_panel_width = 800.0,
            quest_panel_height = 600.0,
            quest_entry_height = 80.0,
            quest_entry_padding = 10.0,
        },
    }

    if !os.exists(hr.config_path) {
        save_ui_config(&hr)
    }

    load_ui_config(&hr)
    return hr
}

save_ui_config :: proc(hr: ^UI_Hot_Reload) {
    data, err := json.marshal(hr.config)
    if err != nil {
        fmt.println("Error marshaling config:", err)
        return
    }

    os.write_entire_file(hr.config_path, data)
}


load_ui_config :: proc(hr: ^UI_Hot_Reload) {
    data, ok := os.read_entire_file(hr.config_path)
    if !ok {
        fmt.println("Could not read config file")
        return
    }

    err := json.unmarshal(data, &hr.config)
    if err != nil {
        fmt.println("Error unmarshaling config:", err)
        return
    }

    if file_info, err := os.stat(hr.config_path); err == 0 {
        hr.last_modified_time = file_info.modification_time
    }
}

check_and_reload :: proc(hr: ^UI_Hot_Reload) {
    if file_info, err := os.stat(hr.config_path); err == 0 {
        if time.duration_seconds(time.diff(hr.last_modified_time, file_info.modification_time)) > 0 {
            load_ui_config(hr)
            fmt.println("Reloaded UI configuration")
        }
    }
}

get_ui_config :: proc(hr: ^UI_Hot_Reload) -> UI_Config {
    return hr.config
}
