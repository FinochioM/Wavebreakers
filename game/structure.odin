package main

Button :: struct {
	bounds:     AABB,
	text:       string,
	text_scale: f32,
	color:      Vector4,
}

Tile :: struct {
    color: Vector4,
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
	GAME_OVER,
	SKILLS,
	QUESTS,
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
	currency_points:      int, // Currency
	floating_texts:       [dynamic]Floating_Text,
	wave_status:          Wave_Status,
	active_enemies:       int,
	wave_config:          Wave_Config,
	current_wave_difficulty: f32,
    skills: [Skill_Kind]Skill,
    active_skill: Maybe(Skill_Kind),
    skills_scroll_offset: f32,
    quests: map[Quest_Kind]Quest,
    active_quest: Maybe(Quest_Kind),
    quest_scroll_offset: f32,
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
	energy_field_charge: int,
	current_element: Element_Kind,
	chain_reaction_range: f32,
	is_multishot: bool,
}

Element_Kind :: enum{
    None,
    Fire, // damage over time
    Ice, // slows enemies
    Lightning, // chain damage to nearby enemies
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

Skill_Kind :: enum {
    damage,
    attack_speed,
    armor,
    life_steal,
    crit_damage,
    health_regen,
}

Skill :: struct {
    kind: Skill_Kind,
    level: int,
    experience: int,
    unlocked: bool
}

Quest_Category :: enum {
    Combat_Flow,
    Resource_Management,
    Strategic,
}

Quest_Kind :: enum {
    Time_Dilation,
    Chain_Reaction,
    Energy_Field,
    Projectile_Master,
    Critical_Cascade,

    Gold_Fever,
    Experience_Flow,
    Blood_Ritual,
    Fortune_Seeker,
    Risk_Reward,

    Priority_Target,
    Sniper_Protocol,
    Crowd_Suppression,
    Elemental_Rotation,
    Defensive_Matrix,
}

Quest_State :: enum{
    Locked,
    Available,
    Purchased,
    Active,
}

Quest :: struct {
    kind: Quest_Kind,
    state: Quest_State,
    progress: int,
    max_progress: int,
    effects: struct {
        damage_mult: f32,
        attack_speed_mult: f32,
        currency_mult: f32,
        health_mult: f32,
        experience_mult: f32,
    },
}

Quest_Info :: struct {
    kind: Quest_Kind,
    category: Quest_Category,
    unlock_level: int,
    base_cost: int,
    description: string,
}