shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

#include "res://player/data/vision_outline.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec4 outline = vision_outline(SCREEN_UV, VIEWPORT_SIZE, INV_PROJECTION_MATRIX);
	// El color ya fue reemplazado por el eco. Borra el alfa de las caras planas
	// y del exterior del radio para dejar ver los contornos de las paredes debajo.
	ALBEDO = vec3(1.0);
	ALPHA = outline.a > 0.000001 ? 1.0 : 0.0;
}
