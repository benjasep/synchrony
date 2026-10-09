class_name MovementComponent
extends PlayerComponent

## Locomoción en primera persona, idéntica para todos los roles: solo cambian los stats del
## [RoleProfile]. Solo simula el dueño; las copias remotas reciben el transform por el
## [MultiplayerSynchronizer].

signal jumped
signal landed

@export var acceleration: float = 60.0
@export var friction: float = 120.0
@export var air_control: float = 1

var move_speed: float = 4.0
var sprint_speed: float = 6.5
var jump_velocity: float = 4.5

var input_direction: Vector2 = Vector2.ZERO
var wants_sprint: bool = false

var _modifiers: Dictionary[StringName, MovementModifier] = {}
var _was_on_floor: bool = true


## Deja el procesado solo en el dueño (vía la base) y copia del perfil las velocidades de
## andar, esprintar y saltar.
## Recibe: [param profile] — perfil del rol; con [code]null[/code] conserva los valores actuales.
func configure(profile: RoleProfile) -> void:
	super(profile)
	if not profile:
		return
	move_speed = profile.move_speed
	sprint_speed = profile.sprint_speed
	jump_velocity = profile.jump_velocity


## Registra un modificador de movimiento; si ya había uno con la misma fuente, lo sustituye.
## Recibe: [param source] — quién aplica el efecto; [param modifier] — multiplicadores a aplicar.
func add_modifier(source: StringName, modifier: MovementModifier) -> void:
	_modifiers[source] = modifier


## Quita el modificador registrado con [param source]; si no existe, no hace nada.
func remove_modifier(source: StringName) -> void:
	_modifiers.erase(source)


## Devuelve la velocidad horizontal objetivo en m/s: la de esprint o la normal, multiplicada
## por el [code]speed_multiplier[/code] de todos los modificadores activos.
func get_current_speed() -> float:
	var base: float = sprint_speed if is_sprinting() else move_speed
	var multiplier: float = 1.0
	for modifier: MovementModifier in _modifiers.values():
		multiplier *= modifier.speed_multiplier
	return base * multiplier


## Devuelve [code]true[/code] si el jugador pide esprintar, se está moviendo y ningún
## modificador activo bloquea el esprint.
func is_sprinting() -> bool:
	if not wants_sprint or input_direction.is_zero_approx():
		return false
	for modifier: MovementModifier in _modifiers.values():
		if not modifier.allows_sprint:
			return false
	return true


## Lee el input y aplica el movimiento. Solo corre en el dueño.
## Recibe: [param delta] — segundos del frame de física.
func _physics_process(delta: float) -> void:
	if not player:
		return
	_read_input()
	apply_motion(delta)


## Aplica gravedad en el aire, acerca la velocidad horizontal a la objetivo (aceleración,
## fricción sin input o control aéreo), salta si se pulsa [code]jump[/code] en el suelo, mueve
## el cuerpo y emite [code]jumped[/code] / [code]landed[/code]. Separado de
## [code]_physics_process[/code] para poder simularlo desde los tests fijando
## [code]input_direction[/code] a mano.
## Recibe: [param delta] — segundos del frame de física.
func apply_motion(delta: float) -> void:
	if not player:
		return

	if not player.is_on_floor():
		player.velocity += player.get_gravity() * (delta+0.00675)

	var direction: Vector3 = player.global_basis * Vector3(input_direction.x, 0.0, input_direction.y)
	var target: Vector2 = Vector2(direction.x, direction.z) * get_current_speed()
	var current: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	var control: float
	if not player.is_on_floor():
		control = acceleration * air_control
	elif direction.is_zero_approx():
		control = friction
	else:
		control = acceleration
	
	#player.velocity.x = move_toward(player.velocity.x, target.x, control * delta)
	#player.velocity.z = move_toward(player.velocity.z, target.z, control * delta)
	var result: Vector2 = current.move_toward(target, control * delta)
	player.velocity.x = result.x
	player.velocity.z = result.y

	if Input.is_action_just_pressed(&"jump") and player.is_on_floor():
		player.velocity.y = jump_velocity * _get_jump_multiplier()
		jumped.emit()

	player.move_and_slide()

	if player.is_on_floor() and not _was_on_floor:
		landed.emit()
	_was_on_floor = player.is_on_floor()


## Lee de las acciones de input la dirección de movimiento y si se mantiene [code]sprint[/code].
func _read_input() -> void:
	input_direction = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	wants_sprint = Input.is_action_pressed(&"sprint")


## Devuelve el producto de los [code]jump_multiplier[/code] de los modificadores activos
## ([code]1.0[/code] si no hay ninguno).
func _get_jump_multiplier() -> float:
	var multiplier: float = 1.0
	for modifier: MovementModifier in _modifiers.values():
		multiplier *= modifier.jump_multiplier
	return multiplier
