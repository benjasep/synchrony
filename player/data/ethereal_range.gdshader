shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

#include "res://player/data/vision_depth.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float perception_radius = 12.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 position = vision_view_position(depth_texture, SCREEN_UV, INV_PROJECTION_MATRIX);
	// Multiplica el alfa existente: fuera del radio la segunda pasada queda
	// transparente, sin pintar negro encima de los contornos de la principal.
	ALBEDO = vec3(1.0);
	ALPHA = perception_radius <= 0.0 || length(position) < perception_radius ? 1.0 : 0.0;
}
