shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;

#include "res://player/data/pickup_echo_palette.gdshaderinc"

uniform bool mission_pickup = false;

void fragment() {
	// Las cámaras que ven el modelo normal (capa 7) no necesitan la marca.
	if ((CAMERA_VISIBLE_LAYERS & 64u) != 0u) {
		discard;
	}
	ALBEDO = mission_pickup ? MISSION_PICKUP_MARKER : CLASS_PICKUP_MARKER;
}
