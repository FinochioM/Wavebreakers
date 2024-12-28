package main

import "core:strings"
import "core:math/linalg"
import "core:math/rand"
import "core:math"
import "core:fmt"

CHAIN_REACTION_RANGE :: 20.0
CHAIN_REACTION_DAMAGE_MULT :: 0.5

ENERGY_FIELD_MAX_CHARGE :: 100
ENERGY_FIELD_CHARGE_PER_HIT :: 10
ENERGY_FIELD_RANGE :: 30.0
ENERGY_FIELD_DAMAGE_MULT :: 2.0

PROJECTILE_MASTER_SHOT_COUNT :: 3
PROJECTILE_MASTER_ANGLE_SPREAD :: 15.0

CRITICAL_CASCADE_RELOAD_CHANCE :: 0.5

spawn_floating_text :: proc(gs: ^Game_State, pos: Vector2, text: string, color := COLOR_WHITE){
    text_copy := strings.clone(text, context.allocator)
    append(&gs.floating_texts, Floating_Text{
        pos = pos + v2{0, 15},
        text = text_copy,
        lifetime = 1.2,
        max_lifetime = 1.2,
        velocity = v2{0, 1},
        color = color,
    })
}


//
// : enemies
boss_states: map[Entity_Handle]Boss_State
enemy_state: map[Entity_Handle]Enemy_State

REST_DURATION :: 1.0
STRONG_ATTACK_MULTIPLIER :: 1.1
CURRENT_TIMER_ATTACK := 0

process_boss_behaviour :: proc(en: ^Entity, gs: ^Game_State, delta_t: f32) {
    if en.enemy_type != 10 do return

    state, exists := &boss_states[en.id]
    if !exists {
        boss_states[en.id] = Boss_State{
            current_attack = .Normal_Attack_1,
            attack_count = 0,
            rest_timer = REST_DURATION,
            first_encounter = true,
        }
        state = &boss_states[en.id]
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

    x_direction := en.target.pos.x - en.pos.x
    x_distance := abs(x_direction)

    #partial switch en.state {
        case .moving:
            play_animation_by_name(&en.animations, "boss10_move")
            if x_distance <= BOSS_ATTACK_RANGE {
                en.state = .attacking
                en.attack_timer = 0
            } else if x_distance > 2.0 {
                en.prev_pos = en.pos
                move_direction := x_direction > 0 ? 1.0 : -1.0
                en.pos.x += f32(move_direction) * f32(en.speed) * f32(delta_t)
            }

        case .attacking:
            if x_distance > BOSS_ATTACK_RANGE {
                en.state = .moving
                return
            }

            en.prev_pos = en.pos
            en.attack_timer -= delta_t

            if state.current_attack == .Rest {
                state.rest_timer -= delta_t
                if state.rest_timer <= 0 {
                    state.current_attack = .Normal_Attack_1
                    state.attack_count = 0
                    state.rest_timer = REST_DURATION
                    en.attack_timer = 0
                }
                return
            }

            current_anim := en.animations.animations[en.animations.current_animation]
            if current_anim.name == "boss10_move" {
                current_anim.state = .Stopped
            }

            if en.attack_timer <= 0 && current_anim.state == .Stopped{
                #partial switch state.current_attack {
                    case .Normal_Attack_1:
                        reset_and_play_animation(&en.animations, "boss10_attack1", 1.0)
                        if CURRENT_TIMER_ATTACK == 0 {
                            state.current_attack = .Normal_Attack_1
                            CURRENT_TIMER_ATTACK += 1
                        }else{
                            state.current_attack = .Strong_Attack
                        }
                        state.damage_dealt = false
                        en.attack_timer = BOSS_ATTACK_COOLDOWN
                    case .Strong_Attack:
                        reset_and_play_animation(&en.animations, "boss10_attack2", 1.0)
                        state.current_attack = .Normal_Attack_1
                        state.damage_dealt = false
                        en.attack_timer = BOSS_ATTACK_COOLDOWN * 1.2
                        CURRENT_TIMER_ATTACK = 0
                }
            }

            if anim, ok := &en.animations.animations[en.animations.current_animation]; ok{
                wave_num := gs.wave_number
                if anim.state == .Stopped {
                    if wave_num <= 9{
                        play_animation_by_name(&en.animations, "boss10_idle")
                    }else if wave_num <= 19{
                        play_animation_by_name(&en.animations, "boss10_idle")
                    }
                }

                damage_frame := 5
                    if anim.current_frame == damage_frame && anim.state == .Playing && !state.damage_dealt {
                        if anim.name == "boss10_attack1" {
                            damage := process_enemy_damage(en.target, en.damage)
                            spawn_floating_text(gs, en.target.pos, fmt.tprintf("%d", damage), v4{1, 0.5, 0, 1})
                            en.target.health -= damage
                            state.damage_dealt = true
                        } else if anim.name == "boss10_attack2" {
                            damage := process_enemy_damage(en.target, int(f32(en.damage) * STRONG_ATTACK_MULTIPLIER))
                            spawn_floating_text(gs, en.target.pos, fmt.tprintf("%d", damage), v4{1, 0.5, 0, 1})
                            en.target.health -= damage
                            state.damage_dealt = true
                        }
                    }

                    if en.target.health <= 0 {
                        en.target.health = 0
                    }
                }
    }
}

BOSS_ATTACK_RANGE :: 60.0
BOSS_ATTACK_COOLDOWN :: 1.0
ENEMY_ATTACK_RANGE :: 20.0
ENEMY_ATTACK_COOLDOWN :: 1.5
process_enemy_behaviour :: proc(en: ^Entity, gs: ^Game_State, delta_t: f32) {
    if en.enemy_type == 10 {
        process_boss_behaviour(en, gs, delta_t)
        return
    }

    state, exists := &enemy_state[en.id]
    if !exists {
        enemy_state[en.id] = Enemy_State{
            current_attack = .Attacking,
            first_encounter = true,
            damage_dealt = false,
        }
        state = &enemy_state[en.id]
    }

	if gs.active_quest != nil && gs.active_quest.? == .Time_Dilation{
	   last_speed := en.speed
	   en.speed = min(en.speed * (1 + delta_t), last_speed)
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
	   wave_num := gs.wave_number
	    if wave_num <= 9 {
       	     if wave_num <= 9 {
    	       play_animation_by_name(&en.animations, "enemy1_10_move")
    	     }else if wave_num <= 19 {
    	       play_animation_by_name(&en.animations, "enemy11_19_move")
	        }
	    }

		if distance <= ENEMY_ATTACK_RANGE {
			en.state = .attacking
			en.attack_timer = 0
			state.damage_dealt = false
		}else if distance > 2.0{
		    en.prev_pos = en.pos
		    direction = linalg.normalize(direction)
		    en.pos += direction * en.speed * delta_t
		}
	case .attacking:
		if distance > ENEMY_ATTACK_RANGE {
			en.state = .moving
			return
		}

        en.prev_pos = en.pos
        en.speed = 0
        en.attack_timer -= delta_t

        wave_num := gs.wave_number
        if en.attack_timer <= 0 {
            state.damage_dealt = false
            if wave_num <= 9 {
                reset_and_play_animation(&en.animations, "enemy1_10_attack", 1.0)
            } else if wave_num <= 19 {
                reset_and_play_animation(&en.animations, "enemy11_19_attack", 1.0)
            }
            en.attack_timer = ENEMY_ATTACK_COOLDOWN
        }


        if anim, ok := &en.animations.animations[en.animations.current_animation]; ok {
            if anim.state == .Stopped {
                if wave_num <= 9{
                    play_animation_by_name(&en.animations, "enemy1_10_move")
                }else if wave_num <= 19{
                    play_animation_by_name(&en.animations, "enemy11_19_move")
                }
            }

            damage_frame := 7
            if anim.current_frame == damage_frame && anim.state == .Playing && !state.damage_dealt {
                damage := process_enemy_damage(en.target, en.damage)
                spawn_floating_text(gs, en.target.pos, fmt.tprintf("%d", damage), v4{1, 0.5, 0, 1})
                en.target.health -= damage
                state.damage_dealt = true

                if en.target.health <= 0{
                    en.target.health = 0
                }
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

PROJECTILE_SPEED :: 500.0
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


	// Since we have a parabole effect, gonna use quadratic equation to solve intersection point
	effective_speed := f32(500.0)

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

setup_projectile :: proc(gs: ^Game_State, e: ^Entity, pos: Vector2, target_pos: Vector2, is_multishot := false) {
	e.kind = .player_projectile
	e.flags |= {.allocated}
    e.is_multishot = is_multishot

	player_height := 16.0
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

    enemy.hit_state.is_hit = true
    enemy.hit_state.hit_timer = 0.08
    enemy.hit_state.color_override = v4{1,1,1,1}

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
            player.attack_timer = 0  // Instant reload
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
            if rand.float32() < 0.35 {  // 35% chance
                spawn_floating_text(gs, enemy.pos, "Double rewards!", v4{1, 0.8, 0, 1})
                add_currency_points(gs, POINTS_PER_ENEMY)  // Add extra points
                exp_multiplier := 1.0 + (f32(player.upgrade_levels.exp_gain) * EXP_GAIN_BONUS_PER_LEVEL)
                exp_amount := int(f32(EXPERIENCE_PER_ENEMY) * exp_multiplier)
                add_experience(gs, player, exp_amount)  // Add extra exp
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
SPAWN_MARGIN :: 5 // Some margin for the enemies to spawn on the right side of the screen (OUTSIDE)
WAVE_SPAWN_RATE :: 2.0 // Time between enemy spawns

init_wave_config :: proc() -> Wave_Config{
    return Wave_Config{
        base_enemy_count = 3,
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
            map_width := 512.0
            screen_half_width := map_width * 0.5
            spawn_position := screen_half_width + SPAWN_MARGIN

            spawn_x := rand.float32_range(
                rand.float32_range(auto_cast spawn_position, auto_cast spawn_position + SPAWN_MARGIN * 0.2),
                auto_cast spawn_position + SPAWN_MARGIN * 0.2,
            )

            if is_boss_wave {
                setup_enemy(enemy, v2{spawn_x, -130}, gs.current_wave_difficulty)
            }else{
                setup_enemy(enemy, v2{spawn_x, -115}, gs.current_wave_difficulty)
            }
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