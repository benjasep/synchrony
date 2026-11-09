shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

#include "res://player/data/vision_outline.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec4 outline = vision_outline(SCREEN_UV, VIEWPORT_SIZE, INV_PROJECTION_MATRIX);
	ALBEDO = outline.rgb * outline.a;
	ALPHA = 1.0;
}
