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
// :behaviour

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
	// Find player entity
	if en.target == nil {
		for &potential_target in gs.entities {
			if potential_target.kind == .player {
				en.target = &potential_target
				break
			}
		}
	}

	if en.target == nil do return // No target found

	direction := en.target.pos - en.pos
	distance := linalg.length(direction)

	// State transitions
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

	// State behaviors
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
		if en.kind != .enemy do continue // Only enemies
		if !(.allocated in en.flags) do continue // Only allocated entities (not destroyed)

		direction := en.pos - source_pos
		distance := linalg.length(direction)

		if distance <= actual_range {
			append(&targets, Enemy_Target{entity = &en, distance = distance})
		}
	}

	if len(targets) > 1 {
		// Sort with a simple bubble sorting algorithm for now.
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

	// While moving, enemy moves directly to the player.
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


	// Since we have a parabole effect, gonna use quadratic equation to solve intersection point
	effective_speed := f32(600.0)

	a := linalg.length2(target_velocity) - effective_speed * effective_speed
	b := 2 * linalg.dot(to_target, target_velocity)
	c := linalg.length2(to_target)

	discriminant := b * b - 4 * a * c

	// there is a possibility that there is not solution (enemy too fast or whatever) so aims at current position
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

setup_projectile :: proc(e: ^Entity, pos: Vector2, target_pos: Vector2, is_multishot := false) {
	e.kind = .player_projectile
	e.flags |= {.allocated}

	player_height := 32.0 * 5.0
	spawn_position := pos + v2{0, auto_cast player_height * 0.5}
	e.pos = spawn_position
	e.prev_pos = spawn_position

	player := find_player(&app_state.game)

    if player != nil && !is_multishot {
        multishot_level := player.upgrade_levels.multishot
        multishot_chance := f32(multishot_level) * MULTISHOT_CHANCE_PER_LEVEL

        for i := 0; i < 2; i += 1 {
            if rand.float32() < multishot_chance {
                extra_projectile := entity_create(&app_state.game)
                if extra_projectile != nil {
                    angle_offset := rand.float32_range(-0.2, 0.2)
                    modified_target := target_pos + Vector2{math.cos(angle_offset), math.sin(angle_offset)} * 50
                    setup_projectile(extra_projectile, pos, modified_target, true)
                }
            }
        }
    }

    accuracy_level := player != nil ? player.upgrade_levels.accuracy : 0

	to_target := target_pos - spawn_position
	distance := linalg.length(to_target)

	// These are hardcoded values, at level 0 Max Spread -> 20° at max range.
	// At max level (10), max spred is reduced by 90%, so it becomes almost perfectly accurate.

	base_spread := 0.35 // 20° in radians
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
	for &en in gs.entities {
		if en.kind == .player {
			add_experience(gs, &en, EXPERIENCE_PER_ENEMY)
			break
		}
	}

	add_currency_points(gs, POINTS_PER_ENEMY)
	gs.active_enemies -= 1

	if gs.active_enemies == 0 && gs.enemies_to_spawn == 0{
	   gs.wave_status = .COMPLETED
	}
}

when_projectile_hits_enemy :: proc(gs: ^Game_State, projectile: ^Entity, enemy: ^Entity) {
	player := find_player(gs)
	if player == nil do return

	total_damage := projectile.damage
	crit_hit := false

	crit_chance := f32(player.upgrade_levels.crit_chance) * CRIT_CHANCE_PER_LEVEL
	if rand.float32() < crit_chance {
	    crit_hit = true
		crit_multiplier := 1.5 + (f32(player.upgrade_levels.crit_damage) * CRIT_DAMAGE_PER_LEVEL)
		total_damage = int(f32(total_damage) * crit_multiplier)
	}

	life_steal_amount :=
		f32(total_damage) * (f32(player.upgrade_levels.life_steal) * LIFE_STEAL_PER_LEVEL)
	if life_steal_amount > 0 {
		heal_player(player, int(life_steal_amount))
	}

	enemy.health -= total_damage

    text_color := crit_hit ? v4{1, 0, 0, 1} : COLOR_WHITE
    spawn_floating_text(gs, enemy.pos, fmt.tprintf("%d", total_damage), text_color)

	if enemy.health <= 0 {
		exp_multiplier := 1.0 + (f32(player.upgrade_levels.exp_gain) * EXP_GAIN_BONUS_PER_LEVEL)
		exp_amount := int(f32(EXPERIENCE_PER_ENEMY) * exp_multiplier)
		add_experience(gs, player, exp_amount)

		when_enemy_dies(gs, enemy)
		entity_destroy(gs, enemy)
	}
}

heal_player :: proc(player: ^Entity, amount: int) {
	player.health = min(player.health + amount, player.max_health)
}

//
// :waves
SPAWN_MARGIN :: 100 // Some margin for the enemies to spawn on the right side of the screen (OUTSIDE)
WAVE_SPAWN_RATE :: 2.0 // Time between enemy spawns

init_wave_config :: proc() -> Wave_Config{
    return Wave_Config{
        base_enemy_count = 5,
        enemy_count_increase = 2,
        max_enemy_count = 25,
        base_difficulty = 1.0,
        difficulty_scale_factor = 0.15,

        health_scale = 0.05,
        damage_scale = 0.03,
        speed_scale = 0.01,
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

calculate_wave_enemies := proc(wave_number: int, config: Wave_Config) -> int {
    enemy_count := config.base_enemy_count + (wave_number - 1) * config.enemy_count_increase
    return min(enemy_count, config.max_enemy_count)
}

calculate_wave_difficulty :: proc(wave_number: int, config: Wave_Config) -> f32{
    difficulty_mult := 1.0 + math.log_f32(f32(wave_number), math.E) * config.difficulty_scale_factor
    return config.base_difficulty * difficulty_mult
}

process_wave :: proc(gs: ^Game_State, delta_t: f64) {
    if gs.wave_status != .IN_PROGRESS do return
	if gs.enemies_to_spawn <= 0 do return

	gs.wave_spawn_timer -= f32(delta_t)
	if gs.wave_spawn_timer <= 0 {
		enemy := entity_create(gs)
		if enemy != nil {
			map_width := f32(WORLD_W * TILE_LENGTH)
			screen_half_width := map_width * 0.5
			spawn_position := screen_half_width + SPAWN_MARGIN

			spawn_x := rand.float32_range(
				rand.float32_range(spawn_position, spawn_position + SPAWN_MARGIN * 1.2),
				spawn_position + SPAWN_MARGIN * 1.2,
			)

			setup_enemy(enemy, v2{spawn_x, -500}, gs.current_wave_difficulty)
			gs.active_enemies += 1
		}

		gs.enemies_to_spawn -= 1
		gs.wave_spawn_timer = gs.wave_spawn_rate
	}
}

//
// :render

draw_game_state :: proc(gs: ^Game_State, input_state: Input_State, messages_out: ^[dynamic]Event) {
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
// : Menus

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
