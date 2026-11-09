class_name SeerEchoAbility
extends PlayerAbility

## Pulso de eco del vidente: expande temporalmente el radio de percepción del shader de eco.
## El mazo le da su [VisionMode] y ajusta el pulso según la competencia del portador.

@export var pulse_radius: float = 25.0
@export var pulse_speed: float = 12.0

var echo_mode: VisionMode

var _equipped: bool = false
var _current_radius: float = 0.0


func _on_setup() -> void:
	_current_radius = echo_mode.perception_radius


func set_equipped(equipped: bool) -> void:
	_equipped = equipped
	if not _equipped:
		deactivate()
		_current_radius = echo_mode.perception_radius
		if player.perception.vision_mode == echo_mode:
			player.perception.set_shader_parameter(&"perception_radius", _current_radius)


func can_activate() -> bool:
	return _equipped and super() and player.perception.vision_mode == echo_mode \
		and not player.health.is_dead and not player.is_captured()


## No hace nada todavía: [code]_process()[/code] expande el radio mientras está activa.
func _on_activated() -> void:
	# TODO: el pulso debería alertar a los enemigos cercanos cuando existan.
	pass


## Además de la lógica base, acerca el radio a [code]pulse_radius[/code] si está activa
## (o al base si no) a [code]pulse_speed[/code] m/s y lo envía al shader de eco.
## Recibe: [param delta] — segundos del frame.
func _process(delta: float) -> void:
	super(delta)
	if not _equipped or player.perception.vision_mode != echo_mode:
		return
	var target: float = pulse_radius if is_active else echo_mode.perception_radius
	_current_radius = move_toward(_current_radius, target, pulse_speed * delta)
	player.perception.set_shader_parameter(&"perception_radius", _current_radius)
