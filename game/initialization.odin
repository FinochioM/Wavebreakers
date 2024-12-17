package main

import sapp "../sokol/app"
import sg "../sokol/gfx"
import sglue "../sokol/glue"
import slog "../sokol/log"
import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import t "core:time"

initialize :: proc "c" () {
	using linalg, fmt
	context = runtime.default_context()

	init_time = t.now()

	sg.setup(
		{
			environment = sglue.environment(),
			logger = {func = slog.func},
			d3d11_shader_debugging = ODIN_DEBUG,
		},
	)

	// :init
	init_images()
	init_fonts()
	first_time_init_game_state(&app_state.game)

	rand.reset(auto_cast runtime.read_cycle_counter())
	app_state.user_id = rand.uint64()
	//loggie(app_state.user_id)

	// make the vertex buffer
	app_state.bind.vertex_buffers[0] = sg.make_buffer(
		{usage = .DYNAMIC, size = size_of(Quad) * len(draw_frame.quads)},
	)

	// make & fill the index buffer
	index_buffer_count :: MAX_QUADS * 6
	indices: [index_buffer_count]u16
	i := 0
	for i < index_buffer_count {
		indices[i + 0] = auto_cast ((i / 6) * 4 + 0)
		indices[i + 1] = auto_cast ((i / 6) * 4 + 1)
		indices[i + 2] = auto_cast ((i / 6) * 4 + 2)
		indices[i + 3] = auto_cast ((i / 6) * 4 + 0)
		indices[i + 4] = auto_cast ((i / 6) * 4 + 2)
		indices[i + 5] = auto_cast ((i / 6) * 4 + 3)
		i += 6
	}
	app_state.bind.index_buffer = sg.make_buffer(
		{type = .INDEXBUFFER, data = {ptr = &indices, size = size_of(indices)}},
	)

	// image stuff
	app_state.bind.samplers[SMP_default_sampler] = sg.make_sampler({})

	// setup pipeline
	pipeline_desc: sg.Pipeline_Desc = {
		shader = sg.make_shader(quad_shader_desc(sg.query_backend())),
		index_type = .UINT16,
		layout = {
			attrs = {
				ATTR_quad_position = {format = .FLOAT2},
				ATTR_quad_color0 = {format = .FLOAT4},
				ATTR_quad_uv0 = {format = .FLOAT2},
				ATTR_quad_bytes0 = {format = .UBYTE4N},
				ATTR_quad_color_override0 = {format = .FLOAT4},
			},
		},
	}
	blend_state: sg.Blend_State = {
		enabled          = true,
		src_factor_rgb   = .SRC_ALPHA,
		dst_factor_rgb   = .ONE_MINUS_SRC_ALPHA,
		op_rgb           = .ADD,
		src_factor_alpha = .ONE,
		dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
		op_alpha         = .ADD,
	}
	pipeline_desc.colors[0] = {
		blend = blend_state,
	}
	app_state.pip = sg.make_pipeline(pipeline_desc)

	// default pass action
	app_state.pass_action = {
		colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}},
	}
}

frame_init :: proc "c" () {
	using runtime, linalg
	context = runtime.default_context()

	current_time := t.now()
	frame_time: f64 = t.duration_seconds(t.diff(last_time, current_time))
	last_time = current_time
	frame_time = sapp.frame_duration()
	//loggie(frame_time)

	accumulator += frame_time
	for (accumulator >= sims_per_second) {
		sim_game_state(&app_state.game, sims_per_second, app_state.message_queue[:])
		last_sim_time = seconds_since_init()
		clear(&app_state.message_queue)
		accumulator -= sims_per_second
	}

	draw_frame.reset = {}

	smooth_rendering := true
	if smooth_rendering {
		dt := seconds_since_init() - last_sim_time

		temp_gs := new_clone(app_state.game)
		sim_game_state(temp_gs, dt, app_state.message_queue[:])

		draw_game_state(temp_gs^, app_state.input_state, &app_state.message_queue)
	} else {
		draw_game_state(app_state.game, app_state.input_state, &app_state.message_queue)
	}
	reset_input_state_for_next_frame(&app_state.input_state)

	for i in 0 ..< draw_frame.sucffed_deferred_quad_count {
		draw_frame.quads[draw_frame.quad_count] = draw_frame.scuffed_deferred_quads[i]
		draw_frame.quad_count += 1
	}

	app_state.bind.images[IMG_tex0] = atlas.sg_image
	app_state.bind.images[IMG_tex1] = images[font.img_id].sg_img

	sg.update_buffer(
		app_state.bind.vertex_buffers[0],
		{ptr = &draw_frame.quads[0], size = size_of(Quad) * len(draw_frame.quads)},
	)
	sg.begin_pass({action = app_state.pass_action, swapchain = sglue.swapchain()})
	sg.apply_pipeline(app_state.pip)
	sg.apply_bindings(app_state.bind)
	sg.draw(0, 6 * draw_frame.quad_count, 1)
	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
}
