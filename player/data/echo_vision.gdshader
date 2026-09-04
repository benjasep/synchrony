shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

// Eco/sonar del vidente.
//
// Reconstruye el mundo desde el DEPTH BUFFER y lo dibuja como lo "oye" un
// ciego: la profundidad en bruto es una nube de puntos, y los bordes y las
// esquinas —lo único con lo que se navega— se marcan como contorno.
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
// Fracción del radio a partir de la cual se empieza a apagar.
uniform float fade_start : hint_range(0.0, 1.0) = 0.45;

uniform vec4 dot_color : source_color = vec4(0.30, 0.68, 0.90, 1.0);
// Separación de la rejilla de puntos, en metros.
uniform float dot_spacing = 0.22;
// Tamaño del punto como fracción de la celda.
uniform float dot_size : hint_range(0.01, 1.0) = 0.32;
// Distancia a la que la rejilla empieza a duplicar su separación.
uniform float dot_lod_distance = 3.0;
uniform float dot_energy : hint_range(0.0, 4.0) = 1.0;

uniform vec4 outline_color : source_color = vec4(0.80, 0.95, 1.0, 1.0);
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


// Rejilla de puntos anclada al mundo: los puntos se quedan pegados a las
// superficies en vez de nadar por la pantalla al girar la cabeza.
//
// La rejilla se mide SOLO en los dos ejes tangentes a la superficie, y ahí está
// todo el truco. Con los tres ejes, una pared plana tiene su tercera coordenada
// constante: si cae entre dos planos de la rejilla, ningún punto de la pared
// llega nunca al nodo y la pared entera se queda a oscuras. Descartando el eje
// de la normal siempre queda una rejilla 2D sobre la superficie.
float lattice(vec3 world_position, vec3 surface_normal, float spacing) {
	vec3 offset = abs(fract(world_position / spacing + 0.5) - 0.5);
	// Peso 0 al eje dominante de la normal, 1 a los otros dos.
	float dominant = max(max(surface_normal.x, surface_normal.y), surface_normal.z);
	vec3 tangent_weight = 1.0 - step(dominant - 0.0001, surface_normal);
	float distance_to_node = length(offset * tangent_weight) * 2.0;
	return 1.0 - smoothstep(dot_size * 0.5, dot_size, distance_to_node);
}


void vertex() {
	// Coordenadas de recorte directamente: el quad cubre la pantalla entera
	// mida lo que mida y esté donde esté.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


void fragment() {
	float center = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);

	// Fuera del if: dFdx/dFdy solo están definidas si TODOS los píxeles del
	// bloque de 2x2 ejecutan la misma rama.
	vec4 view = INV_PROJECTION_MATRIX
		* vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_texture, SCREEN_UV).r, 1.0);
	vec3 world_position = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	// Normal reconstruida de la propia profundidad: no hace falta el buffer de
	// normales, y basta para saber qué eje descartar en la rejilla.
	vec3 surface_normal = abs(normalize(cross(dFdx(world_position), dFdy(world_position))));

	vec3 color = vec3(0.0);

	if (center < perception_radius) {
		// Rejilla con nivel de detalle: al doblar la distancia se dobla la
		// separación. Sin esto los puntos lejanos se apelmazan en una mancha.
		float level = max(log2(max(center, 0.001) / dot_lod_distance), 0.0);
		float lod = floor(level);
		float dots = mix(
			lattice(world_position, surface_normal, dot_spacing * exp2(lod)),
			lattice(world_position, surface_normal, dot_spacing * exp2(lod + 1.0)),
			level - lod);

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
		// curvatura. Sin esto las esquinas de una habitación desaparecen y el
		// vidente no puede leer la forma del sitio.
		float crease = (abs(left + right - 2.0 * center)
			+ abs(up + down - 2.0 * center)) / max(center, 0.001);

		float outline = max(
			smoothstep(outline_threshold, outline_threshold * 2.0, silhouette),
			smoothstep(crease_threshold, crease_threshold * 2.0, crease));

		float fade = 1.0 - smoothstep(perception_radius * fade_start, perception_radius, center);
		color = (dot_color.rgb * dots * dot_energy
			+ outline_color.rgb * outline * outline_energy) * fade;
	}

	ALBEDO = color;
	// Escribir ALPHA es lo que mete el quad en la pasada transparente, que es
	// la única en la que DEPTH_TEXTURE ya está lleno.
	ALPHA = 1.0;
}
