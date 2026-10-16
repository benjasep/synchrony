shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

#include "res://player/data/vision_outline.gdshaderinc"

// Reconstruye los bordes desde profundidad, sin muestrear texturas ni materiales.
// En la principal cubre el escenario con negro; en la segunda pasada una máscara
// posterior vuelve transparente todo lo que no sea un borde.
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec4 outline = vision_outline(SCREEN_UV, VIEWPORT_SIZE, INV_PROJECTION_MATRIX);
	ALBEDO = outline.rgb * outline.a;
	// La pasada transparente permite leer DEPTH_TEXTURE una vez lleno.
	ALPHA = 1.0;
}
