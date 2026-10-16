#include "res://player/data/vision_depth.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float perception_radius = 12.0;
uniform float fade_start : hint_range(0.0, 1.0) = 0.45;
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_width : hint_range(0.5, 4.0) = 1.0;
uniform float outline_threshold = 0.030;
uniform float crease_threshold = 0.010;
uniform float outline_energy : hint_range(0.0, 4.0) = 1.6;

const float FAR_LIMIT = 1.0e6;

float view_depth(vec2 uv, mat4 inv_projection) {
	float distance_to_plane = -vision_view_position(depth_texture, uv, inv_projection).z;
	return distance_to_plane > 0.0 && distance_to_plane < FAR_LIMIT ? distance_to_plane : FAR_LIMIT;
}

// RGB: color del borde. Alfa: intensidad con alcance esférico y desvanecimiento.
vec4 vision_outline(vec2 uv, vec2 viewport_size, mat4 inv_projection) {
	float distance_to_camera = length(vision_view_position(depth_texture, uv, inv_projection));
	if (distance_to_camera >= perception_radius) {
		return vec4(outline_color.rgb * outline_energy, 0.0);
	}
	float center = view_depth(uv, inv_projection);
	vec2 texel = outline_width / viewport_size;
	float left = view_depth(uv - vec2(texel.x, 0.0), inv_projection);
	float right = view_depth(uv + vec2(texel.x, 0.0), inv_projection);
	float up = view_depth(uv - vec2(0.0, texel.y), inv_projection);
	float down = view_depth(uv + vec2(0.0, texel.y), inv_projection);
	float silhouette = max(max(abs(left - center), abs(right - center)),
		max(abs(up - center), abs(down - center))) / max(center, 0.001);
	float crease = (abs(left + right - 2.0 * center)
		+ abs(up + down - 2.0 * center)) / max(center, 0.001);
	float outline = max(
		smoothstep(outline_threshold, outline_threshold * 2.0, silhouette),
		smoothstep(crease_threshold, crease_threshold * 2.0, crease));
	float fade = 1.0 - smoothstep(perception_radius * fade_start, perception_radius, distance_to_camera);
	return vec4(outline_color.rgb * outline_energy, outline * fade);
}
