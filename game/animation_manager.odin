package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

Animation_Frame :: struct {
	file_name:          string,
	frame:              struct {
		x, y:          f32,
		width, height: i32,
	},
	rotated:            bool,
	trimmed:            bool,
	sprite_source_size: struct {
		x, y:          i32,
		width, height: i32,
	},
	source_size:        struct {
		width, height: i32,
		is_empty:      bool,
	},
	pivot:              string,
}

Animation_Metadata :: struct {
	app:     string,
	version: string,
	image:   string,
	format:  string,
	size:    struct {
		w, h: i32,
	},
	scale:   string,
}

Animation_JSON :: struct {
	frames: []Animation_Frame,
	meta:   Animation_Metadata,
}

Animation_Cycle :: struct {
	name:           string,
	frames:         []int,
	is_looping:     bool,
	frame_duration: f32,
}

Animation_Atlas :: struct {
	texture:       string,
	texture_path:  string,
	region_width:  i32,
	region_height: i32,
}

Animation_CSA :: struct {
	texture_atlas: Animation_Atlas,
	json_file:     string,
	cycles:        map[string]Animation_Cycle,
}

Animation_State :: struct {
	current_cycle:    string,
	current_frame:    int,
	time_accumulator: f32,
	is_playing:       bool,
	is_finished:      bool,
}

Animation_Instance :: struct {
	atlas_image: Image_Id,
	json_data:   Animation_JSON,
	csa_data:    Animation_CSA,
	state:       Animation_State,
}

animations: map[string]Animation_Instance

init_animation_system :: proc() {
	animations = make(map[string]Animation_Instance)
}

load_animation :: proc(name: string, csa_path: string) -> (ok: bool) {
	// Here we load the CSA file and we parse it.
	csa_data, csa_ok := os.read_entire_file(csa_path)
	if !csa_ok {
		fmt.println("Error loading the CSA file: ", csa_path)
		return false
	}

	defer delete(csa_data)

	animation: Animation_Instance
	if err := json.unmarshal(csa_data, &animation.csa_data); err != nil {
		fmt.println("Error parsing the CSA file: ", csa_path)
		return false
	}

	// Here we load the JSON file and we parse it.
	json_path := animation.csa_data.json_file
	json_data, json_ok := os.read_entire_file(json_path)
	if !json_ok {
		fmt.println("Error loading the JSON file: ", json_path)
		return false
	}

	defer delete(json_data)

	if err := json.unmarshal(json_data, &animation.json_data); err != nil {
		fmt.println("Error parsing the JSON file: ", json_path)
		return false
	}

	// In this part we should load the actual image using the atlas system.
	// TODO

	animation.state = {
		current_cycle    = "",
		current_frame    = 0,
		time_accumulator = 0.0,
		is_playing       = false,
		is_finished      = false,
	}

	animations[name] = animation
	return true
}

play_animation :: proc(name: string, cycle_name: string) -> bool {
	if animation, exists := &animations[name]; exists {
		if _, cycle_exists := animation.csa_data.cycles[cycle_name]; cycle_exists {
			animation.state = {
				current_cycle    = cycle_name,
				current_frame    = 0,
				time_accumulator = 0.0,
				is_playing       = true,
				is_finished      = false,
			}

			return true
		}
	}

	return false
}

update_animation :: proc(name: string, dt: f32) {
	if animation, exists := &animations[name]; exists && animation.state.is_playing {
		if cycle, ok := animation.csa_data.cycles[animation.state.current_cycle]; ok {
			animation.state.time_accumulator += dt
			if animation.state.time_accumulator >= cycle.frame_duration {
				animation.state.time_accumulator -= cycle.frame_duration
				animation.state.current_frame += 1

				if animation.state.current_frame >= len(cycle.frames) {
					if cycle.is_looping {
						animation.state.current_frame = 0
					} else {
						animation.state.current_frame = len(cycle.frames) - 1
						animation.state.is_finished = true
						animation.state.is_playing = false
					}
				}
			}
		}
	}
}

draw_animation :: proc(
	name: string,
	pos: Vector2,
	scale: Vector2 = {1, 1},
	color: Vector4 = COLOR_WHITE,
) {
	if animation, exists := &animations[name]; exists {
		if cycle, ok := animation.csa_data.cycles[animation.state.current_cycle]; ok {
			frame_index := cycle.frames[animation.state.current_frame]
			frame := animation.json_data.frames[frame_index]

			// We have to create an UV rect here.
			uv := Vector4 {
				auto_cast frame.frame.x / auto_cast animation.json_data.meta.size.w,
				auto_cast frame.frame.y / auto_cast animation.json_data.meta.size.h,
				auto_cast (frame.frame.x + auto_cast frame.frame.width) /
				auto_cast animation.json_data.meta.size.w,
				auto_cast (frame.frame.y + auto_cast frame.frame.height) /
				auto_cast animation.json_data.meta.size.h,
			}

			size := v2{auto_cast frame.frame.width, auto_cast frame.frame.height}

			draw_sprite(
				pos,
				animation.atlas_image,
				pivot = .center_center,
				xform = matrix_scale(v3{scale.x, scale.y, 1}),
				color = color,
			)
		}
	}
}
