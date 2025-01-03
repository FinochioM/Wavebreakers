package main
import "core:fmt"

setup_boss_10_animations :: proc(e: ^Entity) {
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

    boss10_idle_frames: []Image_Id = {
        .boss10_rest_1, .boss10_rest_2, .boss10_rest_3,
    }
    boss10_idle_anim := create_animation(boss10_idle_frames, 0.1, false, "boss10_idle")

    boss10_death_frames: []Image_Id = {
        .boss10_death_1, .boss10_death_2, .boss10_death_3, .boss10_death_4,
        .boss10_death_5, .boss10_death_6, .boss10_death_7
    }
    boss10_death_anim := create_animation(boss10_death_frames, 0.15, false, "boss10_death")

    add_animation(&e.animations, boss10_move_anim)
    add_animation(&e.animations, boss10_attack_anim)
    add_animation(&e.animations, boss10_attack2_anim)
    add_animation(&e.animations, boss10_idle_anim)
    add_animation(&e.animations, boss10_death_anim)
}


setup_enemy_type_1_animations :: proc(e: ^Entity) {
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

    enemy_death_frames: []Image_Id = {
        .enemy1_10_death1, .enemy1_10_death2, .enemy1_10_death3, .enemy1_10_death4,
    }
    enemy_death_anim := create_animation(enemy_death_frames, 0.15, false, "enemy1_10_death")

	add_animation(&e.animations, enemy_move_anim)
	add_animation(&e.animations, enemy_attack_anim)
	add_animation(&e.animations, enemy_death_anim)

    enemy_attack_anim.state = .Playing
    enemy_attack_anim.current_frame = 0
    enemy_attack_anim.frame_timer = 0

    play_animation_by_name(&e.animations, "enemy1_10_move")
}

setup_enemy_type_2_animations :: proc(e: ^Entity) {
    enemy2_move_frames: []Image_Id = {
        .enemy11_19_move1, .enemy11_19_move2, .enemy11_19_move3, .enemy11_19_move4,
        .enemy11_19_move5, .enemy11_19_move6, .enemy11_19_move7, .enemy11_19_move8,
    }

    enemy2_move_anim := create_animation(enemy2_move_frames, 0.12, true, "enemy11_19_move")

    enemy2_attack_frames: []Image_Id = {
        .enemy11_19_attack1, .enemy11_19_attack2, .enemy11_19_attack3, .enemy11_19_attack4,
        .enemy11_19_attack5, .enemy11_19_attack6, .enemy11_19_attack7, .enemy11_19_attack8,
    }

    enemy2_attack_anim := create_animation(enemy2_attack_frames, 0.1, false, "enemy11_19_attack")

    add_animation(&e.animations, enemy2_move_anim)
    add_animation(&e.animations, enemy2_attack_anim)

    enemy2_move_anim.state = .Playing
    enemy2_move_anim.current_frame = 0
    enemy2_move_anim.frame_timer = 0

    play_animation_by_name(&e.animations, "enemy11_19_move")
}

setup_enemy_type_3_animations :: proc(e: ^Entity) {
    enemy3_move_frames: []Image_Id = {
        .enemy21_29_move1, .enemy21_29_move2, .enemy21_29_move3, .enemy21_29_move4,
        .enemy21_29_move5, .enemy21_29_move6, .enemy21_29_move7, .enemy21_29_move8,
    }
    enemy3_move_anim := create_animation(enemy3_move_frames, 0.1, true, "enemy21_29_move")

    enemy3_attack_frames: []Image_Id = {
        .enemy21_29_attack1, .enemy21_29_attack2, .enemy21_29_attack3, .enemy21_29_attack4,
        .enemy21_29_attack5, .enemy21_29_attack6, .enemy21_29_attack7, .enemy21_29_attack8,
    }
    enemy3_attack_anim := create_animation(enemy3_attack_frames, 0.12, false, "enemy21_29_attack")

    enemy3_death_frames: []Image_Id = {
        .enemy21_29_death1, .enemy21_29_death2, .enemy21_29_death3, .enemy21_29_death4,
    }
    enemy3_death_anim := create_animation(enemy3_death_frames, 0.12, false, "enemy21_29_death")

    add_animation(&e.animations, enemy3_move_anim)
    add_animation(&e.animations, enemy3_attack_anim)
    add_animation(&e.animations, enemy3_death_anim)

    enemy3_move_anim.state = .Playing
    enemy3_move_anim.current_frame = 0
    enemy3_move_anim.frame_timer = 0
    play_animation_by_name(&e.animations, "enemy21_29_move")
}

setup_boss_20_animations :: proc(e: ^Entity) {
    boss20_move_frames: []Image_Id = {
        .boss20_move1, .boss20_move2, .boss20_move3, .boss20_move4,
        .boss20_move5, .boss20_move6, .boss20_move7, .boss20_move8,
    }

    boss20_move_anim := create_animation(boss20_move_frames, 0.14, true, "boss20_move")

    boss20_attack_frames: []Image_Id = {
        .boss20_attack1, .boss20_attack2, .boss20_attack3, .boss20_attack4,
        .boss20_attack7, .boss20_attack6, .boss20_attack7, .boss20_attack8,
    }

    boss20_attack_anim := create_animation(boss20_attack_frames, 0.1, false, "boss20_attack")

    boss20_death_frames: []Image_Id = {
        .boss20_death1, .boss20_death2, .boss20_death3, .boss20_death4,
        .boss20_death5,
    }
    boss20_death_anim := create_animation(boss20_death_frames, 0.16, false, "boss20_death")

    add_animation(&e.animations, boss20_move_anim)
    add_animation(&e.animations, boss20_attack_anim)
    add_animation(&e.animations, boss20_death_anim)

    boss20_move_anim.state = .Playing
    boss20_move_anim.current_frame = 0
    boss20_move_anim.frame_timer = 0

    play_animation_by_name(&e.animations, "boss20_move")
}

setup_boss_30_animations :: proc(e: ^Entity) {
    boss30_move_frames: []Image_Id = {
        .boss30_move1, .boss30_move2, .boss30_move3, .boss30_move4,
        .boss30_move5, .boss30_move6, .boss30_move7, .boss30_move8,
    }
    boss30_move_anim := create_animation(boss30_move_frames, 0.1, true, "boss30_move")

    boss30_attack_frames: []Image_Id = {
        .boss30_attack1, .boss30_attack2, .boss30_attack3, .boss30_attack4,
        .boss30_attack5, .boss30_attack6, .boss30_attack7, .boss30_attack8,
        .boss30_attack9, .boss30_attack10, .boss30_attack11, .boss30_attack12,
        .boss30_attack13,
    }
    boss30_attack_anim := create_animation(boss30_attack_frames, 0.1, false, "boss30_attack")

    boss30_death_frames: []Image_Id = {
        .boss30_death1, .boss30_death2, .boss30_death3, .boss30_death4,
        .boss30_death5, .boss30_death6, .boss30_death7, .boss30_death8,
        .boss30_death9, .boss30_death10, .boss30_death11, .boss30_death12,
        .boss30_death13, .boss30_death14, .boss30_death15, .boss30_death16,
        .boss30_death7, .boss30_death18,
    }
    boss30_death_anim := create_animation(boss30_death_frames, 0.1, false, "boss30_death")

    add_animation(&e.animations, boss30_move_anim)
    add_animation(&e.animations, boss30_attack_anim)
    add_animation(&e.animations, boss30_death_anim)

    boss30_move_anim.state = .Playing
    boss30_move_anim.current_frame = 0
    boss30_move_anim.frame_timer = 0

    play_animation_by_name(&e.animations, "boss30_move")
}