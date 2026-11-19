class_name NoiseComponent
extends PlayerComponent

## Ruido que hace el jugador al correr; lo detecta el servidor.

## Metros hasta donde se oye una carrera.
@export var sprint_noise_radius: float = 8.0
## Segundos entre mediciones, y por tanto entre ruidos mientras corre.
@export_range(0.1, 2.0, 0.05) var step_interval: float = 0.4
## Veces la velocidad de esprint a partir de la cual el avance cuenta como teletransporte.
@export var teleport_speed_factor: float = 3.0

var _run_threshold: float = 0.0
var _max_speed: float = 0.0
var _window_start: Vector3 = Vector3.ZERO
var _window_left: float = 0.0
var _has_window: bool = false


## Fija los umbrales de velocidad del rol y procesa solo en el servidor.
func configure(profile: RoleProfile) -> void:
	super(profile)
	_run_threshold = (profile.move_speed + profile.sprint_speed) * 0.5
	_max_speed = profile.sprint_speed * teleport_speed_factor
	_has_window = false
	set_process(false)
	set_process_unhandled_input(false)
	set_physics_process(multiplayer.multiplayer_peer != null and multiplayer.is_server())


## Mide la velocidad cada [code]step_interval[/code] y emite el ruido si corrió.
func _physics_process(delta: float) -> void:
	if not player:
		return
	if not _has_window:
		_start_window()
		return
	_window_left -= delta
	if _window_left > 0.0:
		return
	var elapsed: float = step_interval - _window_left
	var speed: float = measure_speed(_window_start, player.global_position, elapsed)
	if is_running_speed(speed) and _can_make_noise():
		StimulusBus.broadcast(Statics.StimulusKind.NOISE, Stimulus.CAUSE_SPRINT,
			player.global_position, sprint_noise_radius, player)
	_start_window()


## Devuelve la velocidad media en planta, en m/s, de [param from] a [param to] en [param elapsed] s.
func measure_speed(from: Vector3, to: Vector3, elapsed: float) -> float:
	if elapsed <= 0.0:
		return 0.0
	return Vector2(to.x - from.x, to.z - from.z).length() / elapsed


## Devuelve [code]true[/code] si [param speed] es de carrera.
func is_running_speed(speed: float) -> bool:
	return speed >= _run_threshold and speed <= _max_speed


## Devuelve [code]true[/code] si el jugador está vivo y libre.
func _can_make_noise() -> bool:
	if player.health and player.health.is_dead:
		return false
	return not player.is_captured()


## Empieza a medir desde la posición actual.
func _start_window() -> void:
	_window_start = player.global_position
	_window_left = step_interval
	_has_window = true
