package main

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

    add_animation(&e.animations, boss10_move_anim)
    add_animation(&e.animations, boss10_attack_anim)
    add_animation(&e.animations, boss10_attack2_anim)
    add_animation(&e.animations, boss10_idle_anim)
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

	add_animation(&e.animations, enemy_move_anim)
	add_animation(&e.animations, enemy_attack_anim)
}

setup_enemy_type_2_animations :: proc(e: ^Entity) {
    enemy2_move_frames: []Image_Id = {
        .enemy11_19_move1, .enemy11_19_move2, .enemy11_19_move3, .enemy11_19_move4,
        .enemy11_19_move5, .enemy11_19_move6, .enemy11_19_move7, .enemy11_19_move8,
    }
    enemy2_move_anim := create_animation(enemy2_move_frames, 0.14, true, "enemy11_19_move")

    enemy2_attack_frames: []Image_Id = {
        .enemy11_19_attack1, .enemy11_19_attack2, .enemy11_19_attack3, .enemy11_19_attack4,
        .enemy11_19_attack5, .enemy11_19_attack6, .enemy11_19_attack7, .enemy11_19_attack8,
    }
    enemy2_attack_anim := create_animation(enemy2_attack_frames, 0.1, false, "enemy11_19_attack")

    add_animation(&e.animations, enemy2_move_anim)
    add_animation(&e.animations, enemy2_attack_anim)
}
