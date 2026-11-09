shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

#include "res://player/data/vision_outline.gdshaderinc"
#include "res://player/data/pickup_echo_palette.gdshaderinc"

uniform sampler2D opaque_color : hint_screen_texture, repeat_disable, filter_nearest;

// El depth define el contorno; la marca del render opaco solo decide su color.
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 edge_source_uv;
	vec4 outline = vision_outline(SCREEN_UV, VIEWPORT_SIZE, INV_PROJECTION_MATRIX, edge_source_uv);
	vec3 color = outline.rgb;
	if (outline.a > 0.0) {
		vec3 marker = textureLod(opaque_color, edge_source_uv, 0.0).rgb;
		color = pickup_echo_color(marker, outline_color.rgb) * outline_energy;
	}
	ALBEDO = color * outline.a;
	// La pasada transparente permite leer DEPTH_TEXTURE una vez lleno.
	ALPHA = 1.0;
}
