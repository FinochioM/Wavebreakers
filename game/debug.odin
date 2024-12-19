package main

import "core:fmt"

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

    // Survival Stats Section
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

    // Utility Stats Section
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