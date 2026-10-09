class_name ViewComponent
extends PlayerComponent

## Mirada en primera persona: yaw en el cuerpo, pitch en la cabeza. Combina los
## [ViewModifier] activos (temblor, sensibilidad) sin saber quién los registra.

@export var head: Node3D
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0

var _modifiers: Dictionary[StringName, ViewModifier] = {}
var _pitch: float = 0.0
var _sway_time: float = 0.0
var _recoil: Vector2 = Vector2.ZERO


## Captura el ratón si este peer es el dueño del jugador.
## Recibe: [param profile] — perfil del rol, que solo usa la clase base.
func configure(profile: RoleProfile) -> void:
	super(profile)
	if is_owner():
		capture_mouse()


## Captura el ratón, solo en el dueño. Sin esto la mirada no responde: el input solo gira la
## cámara con el ratón capturado.
func capture_mouse() -> void:
	if is_owner():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Libera y muestra el ratón, solo en el dueño. [Player] lo usa al quedar derribado o morir.
func release_mouse() -> void:
	if is_owner():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Alterna entre capturar y liberar el ratón.
func toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		release_mouse()
	else:
		capture_mouse()


## Registra un modificador de vista; si ya había uno con la misma fuente, lo sustituye.
## Recibe: [param source] — quién aplica el efecto; [param modifier] — temblor y sensibilidad.
func add_modifier(source: StringName, modifier: ViewModifier) -> void:
	_modifiers[source] = modifier


## Quita el modificador registrado con [param source]; si no existe, no hace nada.
func remove_modifier(source: StringName) -> void:
	_modifiers.erase(source)


## Suma un empujón instantáneo a la cámara (retroceso de disparo, impacto recibido) que
## [code]_process[/code] disipa solo.
## Recibe: [param pitch_amount] — radianes de pitch; [param yaw_amount] — radianes de yaw.
func apply_recoil(pitch_amount: float, yaw_amount: float) -> void:
	_recoil += Vector2(pitch_amount, yaw_amount)


## Devuelve la orientación con la que apunta el jugador: la de la cabeza o, sin ella, la del
## cuerpo ([code]IDENTITY[/code] si tampoco hay jugador). La usa
## [code]Player.get_aim_direction()[/code].
func get_aim_basis() -> Basis:
	if head:
		return head.global_basis
	return player.global_basis if player else Basis.IDENTITY


## Con [code]ui_cancel[/code] alterna la captura del ratón; con el ratón capturado, gira el
## cuerpo en yaw y acumula el pitch entre [code]min_pitch[/code] y [code]max_pitch[/code]
## (grados), escalando por la sensibilidad de los modificadores. Solo corre en el dueño.
## Recibe: [param event] — evento de input no consumido.
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


## Orienta la cabeza con el pitch acumulado más el temblor de los modificadores y el retroceso,
## que se va disipando. Solo corre en el dueño.
## Recibe: [param delta] — segundos desde el frame anterior.
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


## Devuelve la amplitud total del temblor en radianes: la suma de la de cada modificador.
func _get_sway_amplitude() -> float:
	var total: float = 0.0
	for modifier: ViewModifier in _modifiers.values():
		total += modifier.sway_amplitude
	return total


## Devuelve la frecuencia del temblor en ciclos por segundo: la mayor entre los modificadores,
## nunca menos de [code]1.0[/code].
func _get_sway_frequency() -> float:
	var highest: float = 1.0
	for modifier: ViewModifier in _modifiers.values():
		highest = maxf(highest, modifier.sway_frequency)
	return highest


## Devuelve el producto de los multiplicadores de sensibilidad de los modificadores activos.
func _get_sensitivity_multiplier() -> float:
	var multiplier: float = 1.0
	for modifier: ViewModifier in _modifiers.values():
		multiplier *= modifier.sensitivity_multiplier
	return multiplier
