class_name SeerEchoAbility
extends PlayerAbility

## Pulso de eco del vidente: expande temporalmente el radio de percepción del shader de eco.
## Su visión base no vive aquí, sino en su [VisionMode], que aplica [PerceptionComponent].

@export var pulse_radius: float = 25.0
@export var pulse_speed: float = 12.0

var _base_radius: float = 0.0
var _current_radius: float = 0.0


## Toma como radio base el [code]perception_radius[/code] del [VisionMode] del jugador (0 si
## no lo hay) y arranca desde él.
func _on_setup() -> void:
	if player and player.perception and player.perception.vision_mode:
		_base_radius = player.perception.vision_mode.perception_radius
	_current_radius = _base_radius


## No hace nada todavía: [code]_process()[/code] expande el radio mientras está activa.
func _on_activated() -> void:
	# TODO: el pulso debería alertar a los enemigos cercanos cuando existan.
	pass


## Además de la lógica base, acerca el radio a [code]pulse_radius[/code] si está activa
## (o al base si no) a [code]pulse_speed[/code] m/s y lo envía al shader de eco.
## Recibe: [param delta] — segundos del frame.
func _process(delta: float) -> void:
	super(delta)
	if not player or not player.perception:
		return
	var target: float = pulse_radius if is_active else _base_radius
	_current_radius = move_toward(_current_radius, target, pulse_speed * delta)
	player.perception.set_shader_parameter(&"perception_radius", _current_radius)
