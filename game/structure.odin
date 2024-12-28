package main

import "core:os"
import "core:encoding/json"
import "core:strings"
import "core:fmt"
import "core:time"

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
    ui_hot_reload: UI_Hot_Reload,
    hit_color_override: v4,
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
	animations: Animation_Collection,
	hit_state: struct {
	   is_hit: bool,
	   hit_timer: f32,
	   hit_duration: f32,
	   color_override: Vector4,
	}
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

Animation_State :: enum {
    Playing,
    Paused,
    Stopped,
}

Animation :: struct {
    frames: []Image_Id,
    current_frame: int,
    frame_duration: f32,
    frame_timer: f32,
    state: Animation_State,
    loops: bool,
    name: string,
    base_duration: f32,
}

Animation_Collection :: struct {
    animations: map[string]Animation,
    current_animation: string,
}

UI_Config :: struct {
    // General menu sizing
    menu_button_width: f32,
    menu_button_height: f32,
    pause_menu_button_width: f32,
    pause_menu_button_height: f32,
    pause_menu_spacing: f32,

    // Wave button
    wave_button_width: f32,
    wave_button_height: f32,

    // Skills menu
    skills_panel_width: f32,
    skills_panel_height: f32,
    skills_title_offset_x: f32,
    skills_title_offset_y: f32,
    skills_title_text_scale: f32,
    skills_entry_padding_x: f32,
    skills_entry_height: f32,
    skills_entry_spacing: f32,
    skills_entry_text_offset_x: f32,
    skills_entry_text_offset_y: f32,
    skills_entry_text_scale: f32,
    skills_progress_bar_height: f32,
    skills_progress_bar_offset_bottom: f32,
    skills_progress_bar_padding_x: f32,
    skills_scrollbar_width: f32,
    skills_scrollbar_offset_right: f32,
    skills_scrollbar_padding_y: f32,
    skills_content_top_offset: f32,
    skills_content_bottom_offset: f32,
    skills_scroll_speed: f32,

    // Quest panel
    quest_panel_width: f32,
    quest_panel_height: f32,
    quest_title_offset_x: f32,
    quest_title_offset_y: f32,
    quest_title_scale: f32,
    quest_currency_offset_x: f32,
    quest_currency_offset_y: f32,
    quest_currency_scale: f32,
    quest_category_spacing: f32,
    quest_category_text_offset_x: f32,
    quest_category_text_scale: f32,
    quest_category_bottom_spacing: f32,
    quest_entry_height: f32,
    quest_entry_padding: f32,
    quest_entry_side_padding: f32,
    quest_entry_title_offset_x: f32,
    quest_entry_title_offset_y: f32,
    quest_entry_title_scale: f32,
    quest_entry_desc_offset_x: f32,
    quest_entry_desc_offset_y: f32,
    quest_entry_desc_scale: f32,
    quest_entry_status_offset_x: f32,
    quest_entry_status_offset_y: f32,
    quest_entry_status_scale: f32,
    quest_scrollbar_width: f32,
    quest_scrollbar_offset_right: f32,
    quest_scrollbar_padding_y: f32,
    quest_scroll_speed: f32,
    quest_content_top_offset: f32,
    quest_content_bottom_offset: f32,
     quest_button_width: f32,
    quest_button_height: f32,

    // Shop menu
    shop_panel_width: f32,
    shop_panel_height: f32,
    shop_title_offset_x: f32,
    shop_title_offset_y: f32,
    shop_content_padding: f32,
    shop_button_spacing_y: f32,
    shop_row_start_offset: f32,
    shop_column_start_offset: f32,
    shop_text_scale_title: f32,
    shop_text_scale_currency: f32,
    shop_text_scale_button: f32,
    shop_text_scale_upgrade: f32,
    shop_button_width: f32,
    shop_button_height: f32,
    shop_button_vertical_padding: f32,
    shop_upgrade_text_offset_y: f32,
    shop_max_text_offset_x: f32,
    shop_max_text_offset_y: f32,
    shop_back_button_offset_y: f32,
    shop_back_button_width: f32,
    shop_back_button_height: f32,
    shop_back_button_text_scale: f32,
    shop_currency_text_offset_x: f32,
    shop_currency_text_offset_y: f32,
    shop_currency_text_scale: f32,
    skills_back_button_y: f32,
    skills_back_button_x: f32,
}

UI_Hot_Reload :: struct {
    config: UI_Config,
    config_path: string,
    last_modified_time: time.Time,
}

Screen_Button :: struct {
    screen_bounds: AABB,
    world_bounds: AABB,
    text: string,
    text_scale: f32,
    color: Vector4,
}

Boss_Attack_State :: enum {
    Normal_Attack_1,
    Strong_Attack,
    Rest
}

Boss_State :: struct {
    current_attack: Boss_Attack_State,
    attack_count: int,
    rest_timer: f32,
    first_encounter: bool,
    damage_dealt: bool,
}

Enemy_Attack_State :: enum {
    Attacking,
}

Enemy_State :: struct {
    current_attack: Enemy_Attack_State,
    rest_timer: f32,
    first_encounter: bool,
    damage_dealt: bool,
}

Hit_State :: struct {
    is_hit: bool,
    hit_timer: f32,
    hit_duration: f32,
}
