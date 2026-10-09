class_name VisionMode
extends Resource

## Cómo percibe el mundo un jugador; se aplica solo en el cliente dueño. Con shader de eco,
## [code]cull_mask[/code] solo aporta profundidad: lo que se ve tal cual va en la segunda
## pasada, [code]ethereal_cull_mask[/code] (0 = ninguna), iluminada solo por su ambiente
## propio. [code]perception_radius[/code] va en metros; 0 = el valor por defecto del shader.

@export_flags_3d_render var cull_mask: int = 0xFFFFF

@export_flags_3d_render var ethereal_cull_mask: int = 0

@export var post_process_shader: Shader

@export var shader_parameters: Dictionary[StringName, Variant] = {}

@export var perception_radius: float = 0.0

@export var ethereal_ambient_color: Color = Color(0.75, 0.88, 1.0)
@export var ethereal_ambient_energy: float = 1.0
