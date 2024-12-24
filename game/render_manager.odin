package main

import "core:math/linalg"
import "core:fmt"

draw_sprite :: proc(
	pos: Vector2,
	img_id: Image_Id,
	pivot := Pivot.bottom_left,
	xform := Matrix4(1),
	color_override := v4{0, 0, 0, 0},
	deferred := false,
) {
    if int(img_id) < 0 || int(img_id) >= len(images) {
        fmt.println("Invalid image ID:", img_id, "at position", int(img_id))
        return
    }

	image := images[img_id]
	size := v2{auto_cast image.width, auto_cast image.height}

	xform0 := Matrix4(1)
	xform0 *= xform_translate(pos)
	xform0 *= xform // we slide in here because rotations + scales work nicely at this point
	xform0 *= xform_translate(size * -scale_from_pivot(pivot))

	draw_rect_xform(
		xform0,
		size,
		img_id = img_id,
		color_override = color_override,
		deferred = deferred,
	)
}

draw_rect_aabb :: proc(
	pos: Vector2,
	size: Vector2,
	col: Vector4 = COLOR_WHITE,
	uv: Vector4 = DEFAULT_UV,
	img_id: Image_Id = .nil,
	color_override := v4{0, 0, 0, 0},
	deferred := false,
) {
	xform := linalg.matrix4_translate(v3{pos.x, pos.y, 0})
	draw_rect_xform(xform, size, col, uv, img_id, color_override, deferred = deferred)
}

draw_rect_xform :: proc(
	xform: Matrix4,
	size: Vector2,
	col: Vector4 = COLOR_WHITE,
	uv: Vector4 = DEFAULT_UV,
	img_id: Image_Id = .nil,
	color_override := v4{0, 0, 0, 0},
	deferred := false,
) {
	draw_rect_projected(
		draw_frame.projection * draw_frame.camera_xform * xform,
		size,
		col,
		uv,
		img_id,
		color_override,
		deferred = deferred,
	)
}

Vertex :: struct {
	pos:            Vector2,
	col:            Vector4,
	uv:             Vector2,
	tex_index:      u8,
	_pad:           [3]u8,
	color_override: Vector4,
}

Quad :: [4]Vertex

MAX_QUADS :: 65536
MAX_VERTS :: MAX_QUADS * 4

Draw_Frame :: struct {
	scuffed_deferred_quads: [MAX_QUADS / 4]Quad,
	quads:                  [MAX_QUADS]Quad,
	projection:             Matrix4,
	camera_xform:           Matrix4,
	using reset:            struct {
		quad_count:                  int,
		sucffed_deferred_quad_count: int,
	},
}
draw_frame: Draw_Frame

// below is the lower level draw rect stuff

draw_rect_projected :: proc(
	world_to_clip: Matrix4,
	size: Vector2,
	col: Vector4 = COLOR_WHITE,
	uv: Vector4 = DEFAULT_UV,
	img_id: Image_Id = .nil,
	color_override := v4{0, 0, 0, 0},
	deferred := false,
) {

	bl := v2{0, 0}
	tl := v2{0, size.y}
	tr := v2{size.x, size.y}
	br := v2{size.x, 0}

	uv0 := uv
	if uv == DEFAULT_UV {
		uv0 = images[img_id].atlas_uvs
	}

	tex_index: u8 = images[img_id].tex_index
	if img_id == .nil {
		tex_index = 255 // bypasses texture sampling
	}

	draw_quad_projected(
		world_to_clip,
		{bl, tl, tr, br},
		{col, col, col, col},
		{uv0.xy, uv0.xw, uv0.zw, uv0.zy},
		{tex_index, tex_index, tex_index, tex_index},
		{color_override, color_override, color_override, color_override},
		deferred = deferred,
	)

}

draw_quad_projected :: proc(
	world_to_clip: Matrix4,
	positions: [4]Vector2,
	colors: [4]Vector4,
	uvs: [4]Vector2,
	tex_indicies: [4]u8,
	//flags:           [4]Quad_Flags,
	color_overrides: [4]Vector4,
	//hsv:             [4]Vector3
	deferred := false,
) {
	using linalg

	if draw_frame.quad_count >= MAX_QUADS {
		log_error("max quads reached")
		return
	}

	verts := cast(^[4]Vertex)&draw_frame.quads[draw_frame.quad_count]
	if deferred {
		// randy: me no like this, but it was needed for #debug_draw_on_sim so we could see what's
		// happening.
		verts =
		cast(^[4]Vertex)&draw_frame.scuffed_deferred_quads[draw_frame.sucffed_deferred_quad_count]
		draw_frame.sucffed_deferred_quad_count += 1
	} else {
		draw_frame.quad_count += 1
	}


	verts[0].pos = (world_to_clip * Vector4{positions[0].x, positions[0].y, 0.0, 1.0}).xy
	verts[1].pos = (world_to_clip * Vector4{positions[1].x, positions[1].y, 0.0, 1.0}).xy
	verts[2].pos = (world_to_clip * Vector4{positions[2].x, positions[2].y, 0.0, 1.0}).xy
	verts[3].pos = (world_to_clip * Vector4{positions[3].x, positions[3].y, 0.0, 1.0}).xy

	verts[0].col = colors[0]
	verts[1].col = colors[1]
	verts[2].col = colors[2]
	verts[3].col = colors[3]

	verts[0].uv = uvs[0]
	verts[1].uv = uvs[1]
	verts[2].uv = uvs[2]
	verts[3].uv = uvs[3]

	verts[0].tex_index = tex_indicies[0]
	verts[1].tex_index = tex_indicies[1]
	verts[2].tex_index = tex_indicies[2]
	verts[3].tex_index = tex_indicies[3]

	verts[0].color_override = color_overrides[0]
	verts[1].color_override = color_overrides[1]
	verts[2].color_override = color_overrides[2]
	verts[3].color_override = color_overrides[3]
}
