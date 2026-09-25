class_name PerceptionComponent
extends PlayerComponent

## Aplica el VisionMode del rol a la cámara del jugador.
##
## Es puramente local: la percepción no se replica y no se configura en las
## copias remotas. El vidente ve fantasmas y contornos de pared porque su
## cull_mask y su shader son distintos, no porque el mundo cambie para él.
##
## Presupuesto de capas visuales (ver CLAUDE.md):
##   1 mundo · 2 etéreos · 3 viewmodel · 4 cuerpos de otros jugadores

@export var camera: Camera3D
## ColorRect a pantalla completa donde vive el post-proceso de eco.
@export var post_process: ColorRect

var vision_mode: VisionMode


func configure(profile: RoleProfile) -> void:
	super(profile)
	if not is_owner() or not profile:
		return
	apply_vision_mode(profile.vision_mode)


## También la usan items que otorguen percepción (unas gafas espirituales, por
## ejemplo): el sistema no asume que la visión venga solo del rol.
func apply_vision_mode(mode: VisionMode) -> void:
	vision_mode = mode
	if not camera or not mode:
		return

	camera.cull_mask = mode.cull_mask

	if not post_process:
		return
	if not mode.post_process_shader:
		post_process.hide()
		return

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = mode.post_process_shader
	for parameter: StringName in mode.shader_parameters:
		material.set_shader_parameter(parameter, mode.shader_parameters[parameter])
	if mode.perception_radius > 0.0:
		material.set_shader_parameter(&"perception_radius", mode.perception_radius)
	post_process.material = material
	post_process.show()


## Ajusta un uniform en caliente (el pulso de eco del vidente lo usa).
func set_shader_parameter(parameter: StringName, value: Variant) -> void:
	if not post_process:
		return
	var material: ShaderMaterial = post_process.material as ShaderMaterial
	if material:
		material.set_shader_parameter(parameter, value)
