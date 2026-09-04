class_name VisionMode
extends Resource

## Cómo percibe el mundo un jugador. Se aplica SOLO en el cliente dueño: la
## percepción no se replica.
##
## El vidente es ciego a la geometría normal, pero su eco se reconstruye desde
## el DEPTH BUFFER, así que su cámara TIENE que dibujar el mundo para tenerlo.
## Por eso su cull_mask es la capa 1 y solo esa: lo que ve del mundo es el eco,
## no el mundo. Todo lo que sí percibe tal cual —enemigos etéreos, compañeros,
## su propio item— llega por ethereal_cull_mask, una segunda pasada del mismo
## World3D que se compone POR ENCIMA del post-proceso.
##
## Esa segunda pasada no es un lujo: un shader a pantalla completa tapa por
## definición todo lo que la cámara dibujó, así que sin ella los enemigos no
## sobrevivirían al eco.

## Capas que dibuja la cámara del jugador. Con post_process_shader es además la
## fuente de profundidad del eco, y su color acaba tapado por él.
@export_flags_3d_render var cull_mask: int = 0xFFFFF

## Capas de una segunda pasada compuesta ENCIMA del post-proceso. 0 = ninguna,
## que es lo normal: solo el vidente la necesita.
@export_flags_3d_render var ethereal_cull_mask: int = 0

## Shader de post-proceso (spatial, a pantalla completa). Opcional.
@export var post_process_shader: Shader

## Uniforms del shader, aplicados por nombre. Sin tipo en el valor porque un
## uniform puede ser float, Color o vec3 según el caso.
@export var shader_parameters: Dictionary[StringName, Variant] = {}

## Alcance de la percepción en metros. 0.0 = sin límite.
@export var perception_radius: float = 0.0

## Luz ambiental de la segunda pasada. Es la ÚNICA que la ilumina, y por dos
## razones que apuntan al mismo sitio.
##
## Técnica: la capa (layers) de una Light3D decide qué cámaras ven su
## contribución, así que una luz del nivel en la capa 1 no ilumina nada de una
## cámara con cull_mask 14. Sin ambiente propio, todo lo que no sea unshaded
## saldría negro.
##
## De diseño: el vidente es ciego. Su percepción no puede depender de que
## alguien encienda la linterna, o un nivel a oscuras —que son todos— le dejaría
## sin ver a sus compañeros ni a los enemigos.
@export var ethereal_ambient_color: Color = Color(0.75, 0.88, 1.0)
@export var ethereal_ambient_energy: float = 1.0
