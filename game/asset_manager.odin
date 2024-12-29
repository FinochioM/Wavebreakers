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
	// MAP
	background_map0,
	background_map1,
	background_map2,

	// PARALAX
	cloud1,
	cloud2,
	cloud3,
	cloud4,

	// PLAYER
	player_attack1,
	player_attack2,
	player_attack3,
	player_attack4,
	player_attack5,
	player_attack6,
	player_attack7,
	player_attack8,
	player_idle1,
	player_idle2,
	player_idle3,
	player_idle4,
	player_idle5,
	player_idle6,
	player_idle7,
	player_idle8,
	player_projectile,

	// ENEMIES

	// Enemy 1
	enemy1_10_1_move,
	enemy1_10_2_move,
	enemy1_10_3_move,
	enemy1_10_4_move,
	enemy1_10_5_move,
	enemy1_10_6_move,
	enemy1_10_7_move,
	enemy1_10_8_move,
	enemy1_10_1_attack,
	enemy1_10_2_attack,
	enemy1_10_3_attack,
	enemy1_10_4_attack,
	enemy1_10_5_attack,
	enemy1_10_6_attack,
	enemy1_10_7_attack,
	enemy1_10_8_attack,
	enemy1_10_hit1,
	enemy1_10_hit2,
	enemy1_10_hit3,
	enemy1_10_hit4,

	// Enemy 2
    enemy11_19_move1,
    enemy11_19_move2,
    enemy11_19_move3,
    enemy11_19_move4,
    enemy11_19_move5,
    enemy11_19_move6,
    enemy11_19_move7,
    enemy11_19_move8,
    enemy11_19_attack1,
    enemy11_19_attack2,
    enemy11_19_attack3,
    enemy11_19_attack4,
    enemy11_19_attack5,
    enemy11_19_attack6,
    enemy11_19_attack7,
    enemy11_19_attack8,


	// BOSSES
	boss10_run_1,
	boss10_run_2,
	boss10_run_3,
	boss10_run_4,
	boss10_run_5,
	boss10_run_6,
	boss10_run_7,
	boss10_run_8,
	boss10_attack_1,
	boss10_attack_2,
	boss10_attack_3,
	boss10_attack_4,
	boss10_attack_5,
	boss10_attack_6,
	boss10_attack_7,
	boss10_attack_8,
	boss10_attack2_1,
	boss10_attack2_2,
	boss10_attack2_3,
	boss10_attack2_4,
	boss10_attack2_5,
	boss10_attack2_6,
	boss10_attack2_7,
	boss10_attack2_8,
	boss10_rest_1,
	boss10_rest_2,
	boss10_rest_3,

	boss20,
}

Image :: struct {
	width, height: i32,
	tex_index:     u8,
	sg_img:        sg.Image,
	data:          [^]byte,
	atlas_uvs:     Vector4,
}
images: [512]Image
image_count: int

init_images :: proc() {
	using fmt

	img_dir := "./res/images/"

	highest_id := 0
	for img_name, id in Image_Id {
		if id == 0 {
		continue
	}

		if id > highest_id {
			highest_id = id
		}

		path := tprint(img_dir, img_name, ".png", sep = "")

		png_data, succ := os.read_entire_file(path)
        if !succ {
            continue
        }
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
    max_width := 0
    max_height := 0
    total_area := 0

    for img, id in images {
        if img.width == 0 do continue
        max_width = max(max_width, int(img.width))
        max_height = max(max_height, int(img.height))
        total_area += int(img.width) * int(img.height)
    }

    min_size := 128
    for min_size * min_size < total_area * 2 { // * 2 for some padding
        min_size *= 2
    }

    atlas.w = min_size
    atlas.h = min_size

    nodes := make([dynamic]stbrp.Node, atlas.w)
    defer delete(nodes)

    cont: stbrp.Context
    stbrp.init_target(&cont, auto_cast atlas.w, auto_cast atlas.h, raw_data(nodes), auto_cast len(nodes))

    rects := make([dynamic]stbrp.Rect)
    defer delete(rects)

    for img, id in images {
        if img.width == 0 do continue
        rect := stbrp.Rect{
            id = auto_cast id,
            w = auto_cast img.width,
            h = auto_cast img.height,
        }
        append(&rects, rect)
    }

    if len(rects) == 0 {
        return
    }

    succ := stbrp.pack_rects(&cont, raw_data(rects), auto_cast len(rects))
    if succ == 0 {
        for rect, i in rects {
            fmt.printf("Rect %d: %dx%d = %d pixels\n",
                rect.id, rect.w, rect.h, rect.w * rect.h)
        }
        assert(false, "failed to pack all the rects, ran out of space?")
    }

    // allocate big atlas with proper size
    raw_data_size := atlas.w * atlas.h * 4
    atlas_data, err := mem.alloc(raw_data_size)
    if err != nil {
        return
    }
    defer mem.free(atlas_data)

    mem.set(atlas_data, 255, raw_data_size)

    // copy rect row-by-row into destination atlas
    for rect in rects {
        img := &images[rect.id]
        if img == nil || img.data == nil {
            continue
        }

        // copy row by row into atlas
        for row in 0 ..< rect.h {
            src_row := mem.ptr_offset(&img.data[0], row * rect.w * 4)
            dest_row := mem.ptr_offset(
                cast(^u8)atlas_data,
                ((rect.y + row) * auto_cast atlas.w + rect.x) * 4,
            )
            mem.copy(dest_row, src_row, auto_cast rect.w * 4)
        }

        stbi.image_free(img.data)
        img.data = nil

        img.atlas_uvs.x = cast(f32)rect.x / cast(f32)atlas.w
        img.atlas_uvs.y = cast(f32)rect.y / cast(f32)atlas.h
        img.atlas_uvs.z = img.atlas_uvs.x + cast(f32)img.width / cast(f32)atlas.w
        img.atlas_uvs.w = img.atlas_uvs.y + cast(f32)img.height / cast(f32)atlas.h
    }

    // Write debug atlas
    stbi.write_png(
        "atlases/atlas.png",
        auto_cast atlas.w,
        auto_cast atlas.h,
        4,
        atlas_data,
        4 * auto_cast atlas.w,
    )

    // setup image for GPU
    desc: sg.Image_Desc
    desc.width = auto_cast atlas.w
    desc.height = auto_cast atlas.h
    desc.pixel_format = .RGBA8
    desc.data.subimage[0][0] = {
        ptr = atlas_data,
        size = auto_cast raw_data_size,
    }

    atlas.sg_image = sg.make_image(desc)
    if atlas.sg_image.id == sg.INVALID_ID {
        log_error("failed to make image")
    }
}

//
// :FONT
//
draw_text :: proc(pos: Vector2, text: string, scale := 1.0, color := COLOR_WHITE) {
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
		draw_rect_xform(xform, size, col = color, uv = uv, img_id = font.img_id)

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
	path := "./res/fonts/rainyhearts.ttf"
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
