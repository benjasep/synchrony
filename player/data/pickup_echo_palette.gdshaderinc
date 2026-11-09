// Marcas HDR del render opaco, separadas de los colores que muestra el eco.
const vec3 MISSION_PICKUP_MARKER = vec3(0.0, 32.0, 16.0);
const vec3 CLASS_PICKUP_MARKER = vec3(32.0, 16.0, 0.0);

vec3 pickup_echo_color(vec3 marker, vec3 fallback_color) {
	if (marker.g > 4.0 && marker.r < 0.01 && abs(marker.b - 0.5 * marker.g) < 0.02 * marker.g) {
		return vec3(0.25, 1.0, 0.35);
	}
	if (marker.r > 4.0 && marker.b < 0.01 && abs(marker.g - 0.5 * marker.r) < 0.02 * marker.r) {
		return vec3(1.0, 0.85, 0.2);
	}
	return fallback_color;
}
