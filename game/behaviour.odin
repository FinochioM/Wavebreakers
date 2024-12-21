package main

import "core:strings"
import "core:math/linalg"
import "core:math/rand"
import "core:math"
import "core:fmt"

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

			if gs.active_skill != nil{
			     skill_exp := int(math.floor(f32(EXPERIENCE_PER_ENEMY) * 0.5))
			     add_skill_experience(gs, skill_exp)
			}
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