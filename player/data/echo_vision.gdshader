shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

// Eco del vidente: el mundo entero en negro, solo los bordes en blanco.
//
// Reconstruye la escena desde el DEPTH BUFFER y se queda únicamente con lo que
// un ciego puede "oír" del sitio: dónde se corta una superficie y dónde dos
// paredes se juntan. Las caras planas no devuelven nada, así que no se pintan.
//
// Va sobre un quad a pantalla completa con shader SPATIAL y no sobre un
// ColorRect: un shader canvas_item no tiene acceso al depth texture, así que un
// post-proceso 2D no puede reconstruir nada.
//
// El quad tapa todo lo que dibujó la cámara. Lo que el vidente sí tiene que ver
// tal cual (enemigos etéreos, compañeros, su propio item) NO se dibuja aquí:
// llega por la segunda pasada que compone PerceptionComponent por encima.

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// Alcance de la percepción en metros. SeerEchoAbility lo sube al pulsar.
uniform float perception_radius = 12.0;
// Fracción del radio a partir de la cual el contorno se empieza a apagar.
uniform float fade_start : hint_range(0.0, 1.0) = 0.45;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Grosor del contorno, en píxeles.
uniform float outline_width : hint_range(0.5, 4.0) = 1.0;
// Salto de profundidad relativo que cuenta como silueta.
uniform float outline_threshold = 0.030;
// Curvatura relativa que cuenta como arista interior.
uniform float crease_threshold = 0.010;
uniform float outline_energy : hint_range(0.0, 4.0) = 1.6;

// Cualquier profundidad por encima de esto es "nada": cielo, o el valor de
// limpieza del buffer.
const float FAR_LIMIT = 1.0e6;


// Profundidad lineal en metros desde la cámara.
//
// En el cielo el plano lejano es infinito y w sale 0: la división da inf y la
// comparación devuelve FAR_LIMIT, que es justo lo que se quiere. Vale igual con
// depth buffer normal o invertido porque nunca se interpreta el valor crudo.
float view_depth(vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_texture, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw, 1.0);
	float distance_to_plane = -view.z / view.w;
	return (distance_to_plane > 0.0 && distance_to_plane < FAR_LIMIT) ? distance_to_plane : FAR_LIMIT;
}


void vertex() {
	// Coordenadas de recorte directamente: el quad cubre la pantalla entera
	// mida lo que mida y esté donde esté.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


void fragment() {
	float center = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 color = vec3(0.0);

	if (center < perception_radius) {
		vec2 texel = outline_width / VIEWPORT_SIZE;
		float left = view_depth(SCREEN_UV - vec2(texel.x, 0.0), INV_PROJECTION_MATRIX);
		float right = view_depth(SCREEN_UV + vec2(texel.x, 0.0), INV_PROJECTION_MATRIX);
		float up = view_depth(SCREEN_UV - vec2(0.0, texel.y), INV_PROJECTION_MATRIX);
		float down = view_depth(SCREEN_UV + vec2(0.0, texel.y), INV_PROJECTION_MATRIX);

		// Silueta: salto de profundidad respecto a los vecinos. Relativo a la
		// distancia, o solo saldrían bordes a un palmo de la cara.
		float silhouette = max(max(abs(left - center), abs(right - center)),
			max(abs(up - center), abs(down - center))) / max(center, 0.001);
		// Arista interior: dos paredes en ángulo no dan salto, pero sí
		// curvatura. Sin esto las esquinas de una habitación desaparecen, y
		// siendo el contorno lo ÚNICO que se dibuja, el vidente se quedaría sin
		// forma que leer.
		float crease = (abs(left + right - 2.0 * center)
			+ abs(up + down - 2.0 * center)) / max(center, 0.001);

		float outline = max(
			smoothstep(outline_threshold, outline_threshold * 2.0, silhouette),
			smoothstep(crease_threshold, crease_threshold * 2.0, crease));

		float fade = 1.0 - smoothstep(perception_radius * fade_start, perception_radius, center);
		color = outline_color.rgb * outline * outline_energy * fade;
	}

	ALBEDO = color;
	// Escribir ALPHA es lo que mete el quad en la pasada transparente, que es
	// la única en la que DEPTH_TEXTURE ya está lleno.
	ALPHA = 1.0;
}
