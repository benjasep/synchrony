shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_back, shadows_disabled, fog_disabled;

// Rayo del modo debug de combate, con el mismo grosor en pantalla esté cerca o lejos.
//
// La malla es un cilindro de radio 1 y alto 1 a lo largo de Y, y el nodo lo estira en Y
// hasta la longitud del rayo sin escalar X ni Z. Aquí cada vértice se acerca al eje hasta
// un radio proporcional a su distancia a la cámara que dibuja, así que el rayo ocupa los
// mismos píxeles en todo su recorrido. Con un radio fijo, un rayo de 10 m visto desde su
// origen sería un pegote junto a la cámara y menos de un píxel al final, justo donde
// importa; una línea de ImmediateMesh mide 1 px y apenas se ve.
//
// La distancia se mide en cada pasada contra su propia cámara, así que también vale para
// la segunda pasada del vidente, que tiene otra cámara.
//
// Sin prueba de profundidad: se ve a través de las paredes, como las hitboxes. Es una
// ayuda de depuración, no geometría del mundo.

uniform vec4 color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
// Medio ancho angular del rayo, en radianes: radio = distancia a la cámara × esto.
uniform float half_width = 0.003;


void vertex() {
	vec3 axis_point = (MODEL_MATRIX * vec4(0.0, VERTEX.y, 0.0, 1.0)).xyz;
	float distance_to_camera = length(axis_point - INV_VIEW_MATRIX[3].xyz);
	VERTEX.xz *= distance_to_camera * half_width;
}


void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
