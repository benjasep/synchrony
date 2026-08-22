class_name VisionMode
extends Resource

## Cómo percibe el mundo un jugador. Se aplica SOLO en el cliente dueño: la
## percepción no se replica.
##
## El vidente es ciego a la geometría normal: su cull_mask excluye la capa del
## mundo e incluye la de entidades etéreas, y el post-proceso reconstruye los
## contornos de pared desde el depth buffer. La geometría sigue existiendo para
## colisiones y para el depth prepass, simplemente no se dibuja para él.

## Capas visuales que renderiza la cámara de este jugador.
@export_flags_3d_render var cull_mask: int = 0xFFFFF

## Shader de post-proceso aplicado sobre la cámara (eco/sonar). Opcional.
@export var post_process_shader: Shader

## Parámetros del shader, aplicados como uniforms por nombre.
@export var shader_parameters: Dictionary[StringName, float] = {}

## Alcance de la percepción en metros. 0.0 = sin límite.
@export var perception_radius: float = 0.0

## Multiplicador de la luz ambiental percibida.
@export var ambient_energy: float = 1.0
