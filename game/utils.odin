package main

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import t "core:time"

DEBUG_FLAGS :: struct {
	mouse_pos: bool,
}

DEBUG :: DEBUG_FLAGS {
	mouse_pos = true, // Change to false after testing
}

DEFAULT_UV :: v4{0, 0, 1, 1}
Vector2i :: [2]int
Vector2 :: [2]f32
Vector3 :: [3]f32
Vector4 :: [4]f32
v2 :: Vector2
v3 :: Vector3
v4 :: Vector4
Matrix4 :: linalg.Matrix4f32

COLOR_WHITE :: Vector4{1, 1, 1, 1}
COLOR_RED :: Vector4{1, 0, 0, 1}

loggie :: fmt.println
log_error :: fmt.println
log_warning :: fmt.println

init_time: t.Time
seconds_since_init :: proc() -> f64 {
	using t
	if init_time._nsec == 0 {
		log_error("invalid time")
		return 0
	}
	return duration_seconds(since(init_time))
}

xform_translate :: proc(pos: Vector2) -> Matrix4 {
	return linalg.matrix4_translate(v3{pos.x, pos.y, 0})
}
xform_rotate :: proc(angle: f32) -> Matrix4 {
	return linalg.matrix4_rotate(math.to_radians(angle), v3{0, 0, 1})
}
xform_scale :: proc(scale: Vector2) -> Matrix4 {
	return linalg.matrix4_scale(v3{scale.x, scale.y, 1})
}

Pivot :: enum {
	bottom_left,
	bottom_center,
	bottom_right,
	center_left,
	center_center,
	center_right,
	top_left,
	top_center,
	top_right,
}
scale_from_pivot :: proc(pivot: Pivot) -> Vector2 {
	switch pivot {
	case .bottom_left:
		return v2{0.0, 0.0}
	case .bottom_center:
		return v2{0.5, 0.0}
	case .bottom_right:
		return v2{1.0, 0.0}
	case .center_left:
		return v2{0.0, 0.5}
	case .center_center:
		return v2{0.5, 0.5}
	case .center_right:
		return v2{1.0, 0.5}
	case .top_center:
		return v2{0.5, 1.0}
	case .top_left:
		return v2{0.0, 1.0}
	case .top_right:
		return v2{1.0, 1.0}
	}
	return {}
}

sine_breathe :: proc(p: $T) -> T where intrinsics.type_is_float(T) {
	return (math.sin((p - .25) * 2.0 * math.PI) / 2.0) + 0.5
}
