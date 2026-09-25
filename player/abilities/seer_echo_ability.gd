class_name SeerEchoAbility
extends PlayerAbility

## Pulso de eco del vidente: expande temporalmente su radio de percepción.
##
## La visión base del vidente NO está aquí: es su VisionMode (cull_mask + shader)
## aplicado por PerceptionComponent. Esta habilidad solo modula un uniform, que
## es justo la razón de que PerceptionComponent exponga set_shader_parameter().

@export var pulse_radius: float = 25.0
@export var pulse_speed: float = 12.0

var _base_radius: float = 0.0
var _current_radius: float = 0.0


func _on_setup() -> void:
	if player and player.perception and player.perception.vision_mode:
		_base_radius = player.perception.vision_mode.perception_radius
	_current_radius = _base_radius


func _on_activated() -> void:
	# TODO: el pulso debería alertar a los enemigos cercanos cuando existan.
	pass


func _process(delta: float) -> void:
	super(delta)
	if not player or not player.perception:
		return
	var target: float = pulse_radius if is_active else _base_radius
	_current_radius = move_toward(_current_radius, target, pulse_speed * delta)
	player.perception.set_shader_parameter(&"perception_radius", _current_radius)
