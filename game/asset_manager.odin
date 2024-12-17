package main

import "core:fmt"
import "core:mem"
import "core:os"

import sg "../sokol/gfx"
import stbi "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"
import stbtt "vendor:stb/truetype"

//
// :IMAGE STUFF
//
Image_Id :: enum {
	nil,
	player,
}

Image :: struct {
	width, height: i32,
	tex_index:     u8,
	sg_img:        sg.Image,
	data:          [^]byte,
	atlas_uvs:     Vector4,
}
images: [128]Image
image_count: int

init_images :: proc() {
	using fmt

	img_dir := "A:/Desarrollos/1WeekGame/res/images/"

	highest_id := 0
	for img_name, id in Image_Id {
		if id == 0 {continue}

		if id > highest_id {
			highest_id = id
		}

		path := tprint(img_dir, img_name, ".png", sep = "")
		png_data, succ := os.read_entire_file(path)
		assert(succ)

		stbi.set_flip_vertically_on_load(1)
		width, height, channels: i32
		img_data := stbi.load_from_memory(
			raw_data(png_data),
			auto_cast len(png_data),
			&width,
			&height,
			&channels,
			4,
		)
		assert(img_data != nil, "stbi load failed, invalid image?")

		img: Image
		img.width = width
		img.height = height
		img.data = img_data

		images[id] = img
	}
	image_count = highest_id + 1

	pack_images_into_atlas()
}

Atlas :: struct {
	w, h:     int,
	sg_image: sg.Image,
}
atlas: Atlas

pack_images_into_atlas :: proc() {
	atlas.w = 128
	atlas.h = 128

	cont: stbrp.Context
	nodes: [128]stbrp.Node
	stbrp.init_target(&cont, auto_cast atlas.w, auto_cast atlas.h, &nodes[0], auto_cast atlas.w)

	rects: [dynamic]stbrp.Rect
	for img, id in images {
		if img.width == 0 {
			continue
		}
		append(
			&rects,
			stbrp.Rect{id = auto_cast id, w = auto_cast img.width, h = auto_cast img.height},
		)
	}

	succ := stbrp.pack_rects(&cont, &rects[0], auto_cast len(rects))
	if succ == 0 {
		assert(false, "failed to pack all the rects, ran out of space?")
	}

	// allocate big atlas
	raw_data, err := mem.alloc(atlas.w * atlas.h * 4)
	defer mem.free(raw_data)
	mem.set(raw_data, 255, atlas.w * atlas.h * 4)

	// copy rect row-by-row into destination atlas
	for rect in rects {
		img := &images[rect.id]

		// copy row by row into atlas
		for row in 0 ..< rect.h {
			src_row := mem.ptr_offset(&img.data[0], row * rect.w * 4)
			dest_row := mem.ptr_offset(
				cast(^u8)raw_data,
				((rect.y + row) * auto_cast atlas.w + rect.x) * 4,
			)
			mem.copy(dest_row, src_row, auto_cast rect.w * 4)
		}

		// yeet old data
		stbi.image_free(img.data)
		img.data = nil

		// img.atlas_x = auto_cast rect.x
		// img.atlas_y = auto_cast rect.y

		img.atlas_uvs.x = cast(f32)rect.x / cast(f32)atlas.w
		img.atlas_uvs.y = cast(f32)rect.y / cast(f32)atlas.h
		img.atlas_uvs.z = img.atlas_uvs.x + cast(f32)img.width / cast(f32)atlas.w
		img.atlas_uvs.w = img.atlas_uvs.y + cast(f32)img.height / cast(f32)atlas.h
	}

	stbi.write_png(
		"atlases/atlas.png",
		auto_cast atlas.w,
		auto_cast atlas.h,
		4,
		raw_data,
		4 * auto_cast atlas.w,
	)

	// setup image for GPU
	desc: sg.Image_Desc
	desc.width = auto_cast atlas.w
	desc.height = auto_cast atlas.h
	desc.pixel_format = .RGBA8
	desc.data.subimage[0][0] = {
		ptr  = raw_data,
		size = auto_cast (atlas.w * atlas.h * 4),
	}
	atlas.sg_image = sg.make_image(desc)
	if atlas.sg_image.id == sg.INVALID_ID {
		log_error("failed to make image")
	}
}

//
// :FONT
//
draw_text :: proc(pos: Vector2, text: string, scale := 1.0) {
	using stbtt

	x: f32
	y: f32

	for char in text {

		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(
			&font.char_data[0],
			font_bitmap_w,
			font_bitmap_h,
			cast(i32)char - 32,
			&advance_x,
			&advance_y,
			&q,
			false,
		)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right


		size := v2{abs(q.x0 - q.x1), abs(q.y0 - q.y1)}

		bottom_left := v2{q.x0, -q.y1}
		top_right := v2{q.x1, -q.y0}
		assert(bottom_left + size == top_right)

		offset_to_render_at := v2{x, y} + bottom_left

		uv := v4{q.s0, q.t1, q.s1, q.t0}

		xform := Matrix4(1)
		xform *= xform_translate(pos)
		xform *= xform_scale(v2{auto_cast scale, auto_cast scale})
		xform *= xform_translate(offset_to_render_at)
		draw_rect_xform(xform, size, uv = uv, img_id = font.img_id)

		x += advance_x
		y += -advance_y
	}

}

font_bitmap_w :: 256
font_bitmap_h :: 256
char_count :: 96
Font :: struct {
	char_data: [char_count]stbtt.bakedchar,
	img_id:    Image_Id,
}
font: Font

init_fonts :: proc() {
	using stbtt

	bitmap, _ := mem.alloc(font_bitmap_w * font_bitmap_h)
	font_height := 15 // for some reason this only bakes properly at 15 ? it's a 16px font dou...
	path := "A:/Desarrollos/1WeekGame/res/fonts/alagard.ttf"
	ttf_data, err := os.read_entire_file(path)
	assert(ttf_data != nil, "failed to read font")

	ret := BakeFontBitmap(
		raw_data(ttf_data),
		0,
		auto_cast font_height,
		auto_cast bitmap,
		font_bitmap_w,
		font_bitmap_h,
		32,
		char_count,
		&font.char_data[0],
	)
	assert(ret > 0, "not enough space in bitmap")

	stbi.write_png(
		"atlases/font.png",
		auto_cast font_bitmap_w,
		auto_cast font_bitmap_h,
		1,
		bitmap,
		auto_cast font_bitmap_w,
	)

	// setup font atlas so we can use it in the shader
	desc: sg.Image_Desc
	desc.width = auto_cast font_bitmap_w
	desc.height = auto_cast font_bitmap_h
	desc.pixel_format = .R8
	desc.data.subimage[0][0] = {
		ptr  = bitmap,
		size = auto_cast (font_bitmap_w * font_bitmap_h),
	}
	sg_img := sg.make_image(desc)
	if sg_img.id == sg.INVALID_ID {
		log_error("failed to make image")
	}

	id := store_image(font_bitmap_w, font_bitmap_h, 1, sg_img)
	font.img_id = id
}
// kind scuffed...
// but I'm abusing the Images to store the font atlas by just inserting it at the end with the next id
store_image :: proc(w: int, h: int, tex_index: u8, sg_img: sg.Image) -> Image_Id {

	img: Image
	img.width = auto_cast w
	img.height = auto_cast h
	img.tex_index = tex_index
	img.sg_img = sg_img
	img.atlas_uvs = DEFAULT_UV

	id := image_count
	images[id] = img
	image_count += 1

	return auto_cast id
}
