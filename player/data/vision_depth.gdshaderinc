// Posición del fragmento en metros respecto a la cámara. La longitud da un
// radio esférico; -z solo da distancia al plano de la cámara.
vec3 vision_view_position(sampler2D depth_buffer, vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_buffer, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = raw * 2.0 - 1.0;
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	if (abs(view.w) < 0.000001) {
		return vec3(1.0e6);
	}
	return view.xyz / view.w;
}
