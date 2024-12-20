package main

Button :: struct {
	bounds:     AABB,
	text:       string,
	text_scale: f32,
	color:      Vector4,
}

Tile :: struct {
	type:       u8,
	debug_tile: bool,
}

Event_Kind :: enum {
	shoot,
}

Event :: struct {
	kind: Event_Kind,
}

Wave_Status :: enum{
    WAITING,
    IN_PROGRESS,
    COMPLETED,
}

Floating_Text :: struct {
    pos: Vector2,
    text: string,
    lifetime: f32,
    max_lifetime: f32,
    velocity:  Vector2,
    color: Vector4,
}

Game_State_Kind :: enum {
	MENU,
	PLAYING,
	PAUSED,
	SHOP,
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
	floating_texts:       [dynamic]Floating_Text,
	wave_status:          Wave_Status,
	active_enemies:       int,
	wave_config:          Wave_Config,
	current_wave_difficulty: f32,
}

Enemy_Target :: struct {
	entity:   ^Entity,
	distance: f32,
}

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
	id:                 Entity_Handle,
	kind:               Entity_Kind,
	flags:              bit_set[Entity_Flags],
	pos:                Vector2,
	prev_pos:           Vector2,
	direction:          Vector2,
	health:             int,
	max_health:         int,
	damage:             int,
	attack_speed:       f32,
	attack_timer:       f32,
	speed:              f32,
	value:              int,
	enemy_type:         int,
	state:              Enemy_state,
	target:             ^Entity,
	frame:              struct {},
	level:              int, // Current level
	experience:         int, // Current currency
	upgrade_levels:     struct {
		attack_speed: int,
		accuracy:     int,
		damage:       int,
		armor:        int,
		life_steal:   int,
		exp_gain:     int,
		crit_chance:  int,
		crit_damage:  int,
		multishot:    int,
		health_regen: int,
		dodge_chance: int,
		fov_range:    int,
	},
	health_regen_timer: f32,
	current_fov_range:  f32,
}

Wave_Config :: struct {
    base_enemy_count: int,
    enemy_count_increase: int,
    max_enemy_count: int,
    base_difficulty: f32,
    difficulty_scale_factor: f32,

    health_scale: f32,
    damage_scale: f32,
    speed_scale: f32,
}

