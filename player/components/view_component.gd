class_name ViewComponent
extends PlayerComponent

## Mirada en primera persona: yaw en el cuerpo, pitch en la cabeza.
##
## Es el punto de entrada de los debuffs que afectan a la cámara. Un arma en
## manos inexpertas registra aquí un ViewModifier con sway; el componente agrega
## todos los modificadores activos sin saber de dónde vienen.

@export var head: Node3D
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0

var _modifiers: Dictionary[StringName, ViewModifier] = {}
var _pitch: float = 0.0
var _sway_time: float = 0.0
var _recoil: Vector2 = Vector2.ZERO


func configure(profile: RoleProfile) -> void:
	super(profile)
	if is_owner():
		capture_mouse()


## Sin esto la mirada no responde: _unhandled_input exige el ratón capturado.
func capture_mouse() -> void:
	if is_owner():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	if is_owner():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		release_mouse()
	else:
		capture_mouse()


func add_modifier(source: StringName, modifier: ViewModifier) -> void:
	_modifiers[source] = modifier


func remove_modifier(source: StringName) -> void:
	_modifiers.erase(source)


## Empujón instantáneo de la cámara (retroceso de disparo, impacto recibido).
func apply_recoil(pitch_amount: float, yaw_amount: float) -> void:
	_recoil += Vector2(pitch_amount, yaw_amount)


## Dirección a la que mira el jugador. La usan armas e interacción.
func get_aim_basis() -> Basis:
	if head:
		return head.global_basis
	return player.global_basis if player else Basis.IDENTITY


func _unhandled_input(event: InputEvent) -> void:
	if not player:
		return
	if event.is_action_pressed(&"ui_cancel"):
		toggle_mouse_capture()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if not motion:
		return
	var sensitivity: float = mouse_sensitivity * _get_sensitivity_multiplier()
	player.rotate_y(-motion.relative.x * sensitivity)
	_pitch = clampf(_pitch - motion.relative.y * sensitivity, deg_to_rad(min_pitch), deg_to_rad(max_pitch))


func _process(delta: float) -> void:
	if not head:
		return

	_sway_time += delta * _get_sway_frequency()
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(delta * 8.0, 0.0, 1.0))

	var sway: float = _get_sway_amplitude()
	var sway_pitch: float = sin(_sway_time * TAU) * sway
	var sway_yaw: float = cos(_sway_time * TAU * 0.7) * sway

	head.rotation.x = _pitch + sway_pitch + _recoil.x
	head.rotation.y = sway_yaw + _recoil.y


func _get_sway_amplitude() -> float:
	var total: float = 0.0
	for modifier: ViewModifier in _modifiers.values():
		total += modifier.sway_amplitude
	return total


func _get_sway_frequency() -> float:
	var highest: float = 1.0
	for modifier: ViewModifier in _modifiers.values():
		highest = maxf(highest, modifier.sway_frequency)
	return highest


func _get_sensitivity_multiplier() -> float:
	var multiplier: float = 1.0
	for modifier: ViewModifier in _modifiers.values():
		multiplier *= modifier.sensitivity_multiplier
	return multiplier
