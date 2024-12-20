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
	png_data, succ := os.read_entire_file("A:/Desarrollos/1WeekGame/res/map.png")
	assert(succ, "map.png not found")

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

			r := pixel[0]
			g := pixel[1]
			b := pixel[2]
			a := pixel[3]

			t := &tiles[x + y * WORLD_W]

			if r == 65 && g == 128 && b == 62 {
				t.type = 1
			} else if r == 65 && g == 110 && b == 107 {
				t.type = 2
			} else if r == 87 && g == 79 && b == 51 {
				t.type = 3
			} else if r == 110 && g == 100 && b == 65 {
				t.type = 4
			} else if r == 117 && g == 107 && b == 69 {
				t.type = 5
			} else {
				t.type = 0
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

			if tile.type != 0 {
				col := COLOR_WHITE

				switch tile.type {
				case 1:
					col = v4{0.255, 0.502, 0.243, 1.0}
				case 2:
					col = v4{0.255, 0.431, 0.42, 1.0}
				case 3:
					col = v4{0.341, 0.31, 0.2, 1.0}
				case 4:
					col = v4{0.431, 0.392, 0.255, 1.0}
				case 5:
					col = v4{0.459, 0.431, 0.267, 1.0}
				}

				draw_rect_aabb(tile_pos_world, v2{TILE_LENGTH, TILE_LENGTH}, col = col)
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
}

//
// :GAME STATE

add_message :: proc(messages: ^[dynamic]Event, new_message: Event) -> ^Event {

	for msg in messages {
		#partial switch msg.kind {
		case:
			if msg.kind == new_message.kind {
				return nil
			}
		}
	}

	index := append(messages, new_message) - 1
	return &messages[index]
}


//
// :ENTITY

EXPERIENCE_PER_LEVEL :: 100
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
LIFE_STEAL_PER_LEVEL :: 0.05
EXP_GAIN_BONUS_PER_LEVEL :: 0.1
CRIT_CHANCE_PER_LEVEL :: 0.05
CRIT_DAMAGE_PER_LEVEL :: 0.2
MULTISHOT_CHANCE_PER_LEVEL :: 0.1
DODGE_CHANCE_PER_LEVEL :: 0.03
FOV_RANGE_BONUS_PER_LEVEL :: 50.0
HEALTH_REGEN_PER_LEVEL :: 0.9

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

	e.pos = v2{-900, -500}

	e.health = 100
	e.max_health = 100
	e.damage = 10
	e.attack_speed = 1.0
	e.attack_timer = 0.0

	e.upgrade_levels = {}
	e.health_regen_timer = 0
	e.current_fov_range = FOV_RANGE
}

setup_enemy :: proc(e: ^Entity, pos: Vector2, difficulty: f32) {
	e.kind = .enemy
	e.flags |= {.allocated}

	base_health := 15
	base_damage := 5
	base_speed := 100.0

	config := app_state.game.wave_config
	wave_num := f32(app_state.game.wave_number)

	health_mult := 1.0 + (config.health_scale * wave_num)
	damage_mult := 1.0 + (config.damage_scale * wave_num)
	speed_mult := 1.0 + (config.speed_scale * wave_num)

	e.pos = pos
	e.prev_pos = pos
    e.health = int(f32(base_health) * health_mult * difficulty)
	e.max_health = e.health
	e.attack_timer = 0.0
	e.damage = int(f32(base_damage) * damage_mult * difficulty)
	e.state = .moving
	e.speed = f32(base_speed) * speed_mult
	e.value = 10
	e.enemy_type = 1
}

calculate_exp_for_level :: proc(level: int) -> int {
	return EXPERIENCE_PER_LEVEL * level
}

add_experience :: proc(gs: ^Game_State, player: ^Entity, exp_amount: int) {
	player.experience += exp_amount
	exp_needed := calculate_exp_for_level(player.level)

	for player.experience >= exp_needed {
		player.experience -= exp_needed
		player.level += 1
		gs.available_points += 1
		exp_needed = calculate_exp_for_level(player.level)
	}
}

add_currency_points :: proc(gs: ^Game_State, points: int) {
	gs.currency_points += points
}

//
// THE GAMEPLAY LINE
//

//
// :sim

FOV_RANGE :: 1000.0 // Range in which the player can detect enemies

handle_input :: proc(gs: ^Game_State) {
	mouse_pos := screen_to_world_pos(app_state.input_state.mouse_pos)

	#partial switch gs.state_kind {
	case .MENU:
		button_bounds := AABB {
			-MENU_BUTTON_WIDTH * 0.5,
			-MENU_BUTTON_HEIGHT * 0.5,
			MENU_BUTTON_WIDTH * 0.5,
			MENU_BUTTON_HEIGHT * 0.5,
		}

		if aabb_contains(button_bounds, mouse_pos) {
			if key_just_pressed(app_state.input_state, .LEFT_MOUSE) {
				for &en in gs.entities {
					if .allocated in en.flags {
						entity_destroy(gs, &en)
					}
				}

				gs.wave_number = 0
				gs.enemies_to_spawn = 0
				gs.available_points = 0
				gs.currency_points = 0
				gs.player_level = 0
				gs.player_experience = 0

                for text in &gs.floating_texts{
                    delete(text.text)
                }

				clear(&gs.floating_texts)

				e := entity_create(gs)
				if e != nil {
					setup_player(e)
				}

				gs.state_kind = .PLAYING
			}
		}
	case .PLAYING:
		if key_just_pressed(app_state.input_state, .ESCAPE) {
			gs.state_kind = .PAUSED
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

update_gameplay :: proc(gs: ^Game_State, delta_t: f64, messages: []Event) {
	defer gs.tick_index += 1

	#partial switch gs.state_kind {
	case .PLAYING:
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

				if DEBUG.player_fov {
					debug_draw_fov_range(en.pos, FOV_RANGE)
				}

				if en.attack_timer <= 0 && len(targets) > 0 {
					closest_enemy := targets[0].entity
					projectile := entity_create(gs)
					if projectile != nil {
						setup_projectile(projectile, en.pos, closest_enemy.pos)
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
						if dist <= 100.0 {
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
	}
}

//
// :render

render_gameplay :: proc(gs: ^Game_State, input_state: Input_State, messages_out: ^[dynamic]Event) {
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

		for en in gs.entities {
			#partial switch en.kind {
			case .player:
				draw_player(en)
			case .enemy, .player_projectile:
				render_pos := linalg.lerp(en.prev_pos, en.pos, alpha)

				if en.kind == .enemy {
					draw_enemy_at_pos(en, render_pos)
				} else if en.kind == .player_projectile {
					draw_player_projectile_at_pos(en, render_pos)
				}
			}
		}

		for &en in gs.entities {
			if en.kind == .player {
				ui_base_pos := v2{-1000, 600}

				level_text := fmt.tprintf("Current Level: %d", en.level)
				draw_text(ui_base_pos, level_text, scale = 2.0)

				if gs.available_points > 0 {
					points_text := fmt.tprintf("Available Points: %d", gs.available_points)
					draw_text(ui_base_pos + v2{0, -50}, points_text, scale = 2.0)
				}

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -100}, currency_text, scale = 2.0)

				health_text := fmt.tprintf("Health: %d/%d", en.health, en.max_health)
				draw_text(ui_base_pos + v2{0, -150}, health_text, scale = 2.0)

				// -------- DEBUG (DELETE LATER) --------

				stats_pos := v2{600, 600}

				draw_debug_stats(&en, stats_pos)

				break
			}
		}

        draw_wave_button(gs)

	    for text in gs.floating_texts{
	       text_alpha := text.lifetime / text.max_lifetime
	       color := text.color
	       color.w = text_alpha
	       draw_text(text.pos, text.text, scale = 1.5, color = color)
	    }
	case .PAUSED:
		draw_tiles(gs, player)
		for en in gs.entities {
			#partial switch en.kind {
			case .player:
				draw_player(en)
			case .enemy, .player_projectile:
				render_pos := linalg.lerp(en.prev_pos, en.pos, alpha)

				if en.kind == .enemy {
					draw_enemy_at_pos(en, render_pos)
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
	}
}

draw_player :: proc(en: Entity) {
	img := Image_Id.player

	xform := Matrix4(1)
	xform *= xform_scale(v2{5, 5})

	draw_sprite(en.pos, img, pivot = .bottom_center, xform = xform)
}

draw_enemy_at_pos :: proc(en: Entity, pos: Vector2) {
	img := Image_Id.enemy

	xform := Matrix4(1)
	xform *= xform_scale(v2{5, 5})

	draw_sprite(pos, img, pivot = .bottom_center, xform = xform)
}

draw_player_projectile_at_pos :: proc(en: Entity, pos: Vector2){
    img := Image_Id.player_projectile

    angle := math.atan2(en.direction.y, en.direction.x)
    final_angle := math.to_degrees(angle)

    xform := Matrix4(1)
    xform *= xform_rotate(final_angle)
    xform *= xform_scale(v2{5,5})

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
	// Calculate overlap on each axis
	dx := (a.z + a.x) / 2 - (b.z + b.x) / 2
	dy := (a.w + a.y) / 2 - (b.w + b.y) / 2

	overlap_x := (a.z - a.x) / 2 + (b.z - b.x) / 2 - abs(dx)
	overlap_y := (a.w - a.y) / 2 + (b.w - b.y) / 2 - abs(dy)

	// If there is no overlap on any axis, there is no collision
	if overlap_x <= 0 || overlap_y <= 0 {
		return false, Vector2{}
	}

	// Find the penetration vector
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
		player.max_health =
			100 + int(f32(100) * ARMOR_BONUS_PER_LEVEL * f32(player.upgrade_levels.armor))
		player.health = player.max_health
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
