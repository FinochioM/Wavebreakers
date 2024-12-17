package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:os"
import t "core:time"

import sapp "../sokol/app"
import sg "../sokol/gfx"
import sglue "../sokol/glue"
import slog "../sokol/log"

import stbi "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"
import stbtt "vendor:stb/truetype"

UserID :: u64

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
			window_title = "1WeekGame",
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
Tile :: struct {
	type:       u8,
	debug_tile: bool,
}

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
draw_tiles :: proc(gs: Game_State, player: Entity) {
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

	load_map_into_tiles(gs.tiles[:])
}

//
// :GAME STATE

Game_State_Kind :: enum {
	MENU,
	PLAYING,
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
	available_points:     int, // Experience
	currency_points:      int, // Currency
}

Message_Kind :: enum {
	create_player,
	shoot,
}

Message :: struct {
	kind:          Message_Kind,
	from_entity:   Entity_Handle,
	using variant: struct #raw_union {
		create_player: struct {
			user_id: UserID,
		},
	},
}

add_message :: proc(messages: ^[dynamic]Message, new_message: Message) -> ^Message {

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
	id:           Entity_Handle,
	kind:         Entity_Kind,
	flags:        bit_set[Entity_Flags],
	pos:          Vector2,
	direction:    Vector2,
	user_id:      UserID,
	health:       int,
	max_health:   int,
	damage:       int,
	attack_speed: f32,
	attack_timer: f32,
	speed:        f32,
	value:        int,
	enemy_type:   int,
	state:        Enemy_state,
	target:       ^Entity,
	frame:        struct {},
	level:        int, // Current level
	experience:   int, // Current currency
}

Entity_Handle :: u64


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
}

setup_enemy :: proc(e: ^Entity, pos: Vector2) {
	e.kind = .enemy
	e.flags |= {.allocated}

	e.pos = pos
	e.health = 10
	e.max_health = 100
	e.damage = 5
	e.state = .moving
	e.speed = 100.0
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

sim_game_state :: proc(gs: ^Game_State, delta_t: f64, messages: []Message) {
	defer gs.tick_index += 1

	#partial switch gs.state_kind {
	case .MENU:
		mouse_pos := screen_to_world_pos(app_state.input_state.mouse_pos)
		button_bounds := AABB {
			-MENU_BUTTON_WIDTH * 0.5,
			-MENU_BUTTON_HEIGHT * 0.5,
			MENU_BUTTON_WIDTH * 0.5,
			MENU_BUTTON_HEIGHT * 0.5,
		}

		if aabb_contains(button_bounds, mouse_pos) {
			if key_just_pressed(app_state.input_state, .LEFT_MOUSE) {
				gs.state_kind = .PLAYING
			}
		}
	case .PLAYING:
		for &en in gs.entities {
			en.frame = {}
		}

		for msg in messages {
			#partial switch msg.kind {
			case .create_player:
				{

					user_id := msg.create_player.user_id
					assert(user_id != 0, "invalid user id")

					existing_user := false
					for en in gs.entities {
						if en.user_id == user_id {
							existing_user = true
							break
						}
					}

					if !existing_user {
						e := entity_create(gs)
						setup_player(e)
						e.user_id = user_id
					}

				}
			}
		}

		for &en in gs.entities {
			// :player
			if en.kind == .player {
				en.attack_timer -= f32(delta_t)

				targets := find_enemies_in_range(gs, en.pos, FOV_RANGE)

				if DEBUG.player_fov {
					debug_draw_fov_range(en.pos, FOV_RANGE)
				}

				if en.attack_timer <= 0 && len(targets) > 0 {
					// Here we have a target in range and we can actually shoot.
					closest_enemy := targets[0].entity

					projectile := entity_create(gs)

					if projectile != nil {
						setup_projectile(projectile, en.pos, closest_enemy.pos)
					}

					en.attack_timer = 1.0 / en.attack_speed
				}
			}
			//:enemy
			if en.kind == .enemy {
				process_enemy_behaviour(&en, gs, f32(delta_t))
			}
			// :player_projectile
			if en.kind == .player_projectile {
				SUB_STEPS :: 4
				dt := f32(delta_t) / f32(SUB_STEPS)

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
							target.health -= en.damage
							entity_destroy(gs, &en)

							if target.health <= 0 {
								when_enemy_dies(gs, &target)
								entity_destroy(gs, &target)
							}
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
ENEMY_ATTACK_RANGE :: 100.0
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
		if distance > 1.0 {
			direction = linalg.normalize(direction)
			en.pos += direction * en.speed * delta_t
		}
	case .attacking:
		// Attack logic will go here later
		fmt.printf("Attacking\n")
	}
}

Enemy_Target :: struct {
	entity:   ^Entity,
	distance: f32,
}

find_enemies_in_range :: proc(gs: ^Game_State, source_pos: Vector2, range: f32) -> []Enemy_Target {
	targets: [dynamic]Enemy_Target
	targets.allocator = context.temp_allocator

	for &en in gs.entities {
		if en.kind != .enemy do continue // Only enemies
		if !(.allocated in en.flags) do continue // Only allocated entities (not destroyed)

		direction := en.pos - source_pos
		distance := linalg.length(direction)

		if distance <= range {
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

setup_projectile :: proc(e: ^Entity, pos: Vector2, target_pos: Vector2) {
	e.kind = .player_projectile
	e.flags |= {.allocated}

	player_height := 32.0 * 5.0
	spawn_position := pos + v2{0, auto_cast player_height * 0.5}
	e.pos = spawn_position

	to_target := target_pos - spawn_position
	distance := linalg.length(to_target)
	direction := linalg.normalize(to_target)

	flight_time := max(distance / 600.0, 0.5)

	gravity := PROJECTILE_GRAVITY
	dx := distance
	dy := target_pos.y - spawn_position.y

	vx := dx / flight_time
	vy := (dy + 0.5 * auto_cast gravity * flight_time * flight_time) / flight_time

	e.direction = {direction.x * vx, vy}

	//e.speed = PROJECTILE_SPEED
	e.damage = 10
}

when_enemy_dies :: proc(gs: ^Game_State, enemy: ^Entity) {
	for &en in gs.entities {
		if en.kind == .player {
			add_experience(gs, &en, EXPERIENCE_PER_ENEMY)
			break
		}
	}

	add_currency_points(gs, POINTS_PER_ENEMY)
}

//
// :waves
SPAWN_MARGIN :: 100 // Some margin for the enemies to spawn on the right side of the screen (OUTSIDE)
WAVE_SPAWN_RATE :: 2.0 // Time between enemy spawns

init_wave :: proc(gs: ^Game_State, wave_number: int) {
	gs.wave_number = wave_number
	gs.wave_spawn_timer = WAVE_SPAWN_RATE
	gs.wave_spawn_rate = WAVE_SPAWN_RATE
	gs.enemies_to_spawn = wave_number * 3 // This is a placeholder, later will make it so it scales with the wave number or some calculation.
}

process_wave :: proc(gs: ^Game_State, delta_t: f64) {
	if gs.enemies_to_spawn <= 0 do return

	gs.wave_spawn_timer -= f32(delta_t)
	if gs.wave_spawn_timer <= 0 {
		enemy := entity_create(gs)
		if enemy != nil {
			// Spawn on the right side, random so they don't all spawn at the same distances. (this spawns OUTSIDE of the screen)
			map_width := f32(WORLD_W * TILE_LENGTH)
			spawn_x := rand.float32_range(map_width * 0.6, map_width - SPAWN_MARGIN)

			setup_enemy(enemy, v2{spawn_x, -500})
		}

		gs.enemies_to_spawn -= 1
		gs.wave_spawn_timer = gs.wave_spawn_rate
	}
}

//
// :draw :user

draw_game_state :: proc(
	gs: Game_State,
	input_state: Input_State,
	messages_out: ^[dynamic]Message,
) {
	using linalg

	map_width := f32(WORLD_W * TILE_LENGTH) // 2048
	map_height := f32(WORLD_H * TILE_LENGTH) // 1280

	scale_x := window_w / map_width
	scale_y := window_h / map_height
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

	#partial switch gs.state_kind {
	case .MENU:
		draw_menu(gs)
	case .PLAYING:
		player: Entity
		player_handle: Entity_Handle
		for en in gs.entities {
			if en.kind == .player && en.user_id == app_state.user_id {
				player = en
				player_handle = entity_to_handle(gs, player)
				break
			}
		}

		if player_handle == 0 {
			append(
				messages_out,
				(Message){kind = .create_player, create_player = {user_id = app_state.user_id}},
			)
		}

		draw_tiles(gs, player)

		for en in gs.entities {
			#partial switch en.kind {
			case .player:
				draw_player(en)
			case .enemy:
				draw_enemy(en)
			case .player_projectile:
				draw_rect_aabb(en.pos - PROJECTILE_SIZE * 0.5, PROJECTILE_SIZE, col = COLOR_WHITE)
			}
		}

		for en in gs.entities {
			if en.kind == .player && en.user_id == app_state.user_id {
				ui_base_pos := v2{-1000, 600}

				level_text := fmt.tprintf("Current Level: %d", en.level)
				draw_text(ui_base_pos, level_text, scale = 2.0)

				if gs.available_points > 0 {
					points_text := fmt.tprintf("Available Points: %d", gs.available_points)
					draw_text(ui_base_pos + v2{0, -50}, points_text, scale = 2.0)
				}

				currency_text := fmt.tprintf("Currency: %d", gs.currency_points)
				draw_text(ui_base_pos + v2{0, -100}, currency_text, scale = 2.0)

				break
			}
		}
	}
}

draw_player :: proc(en: Entity) {

	img := Image_Id.player

	xform := Matrix4(1)
	xform *= xform_scale(v2{5, 5})

	draw_sprite(en.pos, img, pivot = .bottom_center, xform = xform)

}

draw_enemy :: proc(en: Entity) {
	img := Image_Id.enemy

	xform := Matrix4(1)
	xform *= xform_scale(v2{5, 5})

	draw_sprite(en.pos, img, pivot = .bottom_center, xform = xform)
}

screen_to_world_pos :: proc(screen_pos: Vector2) -> Vector2 {
	map_width := f32(WORLD_W * TILE_LENGTH)
	map_height := f32(WORLD_H * TILE_LENGTH)

	normalized_x := (screen_pos.x / f32(window_w)) * 2.0 - 1.0
	normalized_y := -((screen_pos.y / f32(window_h)) * 2.0 - 1.0)

	world_x := normalized_x * (map_width * 0.5)
	world_y := normalized_y * (map_height * 0.5)

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

draw_menu :: proc(gs: Game_State) {
	button_pos := v2{-MENU_BUTTON_WIDTH * 0.5, 0}

	draw_rect_aabb(
		button_pos,
		v2{MENU_BUTTON_WIDTH, MENU_BUTTON_HEIGHT},
		col = v4{0.2, 0.3, 0.8, 1.0},
	)

	text_pos := button_pos + v2{MENU_BUTTON_WIDTH * 0.2, MENU_BUTTON_HEIGHT * 0.3}
	draw_text(text_pos, "Play", scale = 2.0)
}
