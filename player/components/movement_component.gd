class_name MovementComponent
extends PlayerComponent

## Locomoción en primera persona. Idéntica para los tres roles: solo cambian los
## stats, que vienen del RoleProfile.
##
## Autoridad de cliente: solo el dueño simula. Los demás peers reciben el
## transform por MultiplayerSynchronizer, por eso configure() apaga el
## _physics_process en las copias remotas.

signal jumped
signal landed

@export var acceleration: float = 12.0
@export var air_control: float = 0.3

var move_speed: float = 4.0
var sprint_speed: float = 6.5
var jump_velocity: float = 4.5

var input_direction: Vector2 = Vector2.ZERO
var wants_sprint: bool = false

var _modifiers: Dictionary[StringName, MovementModifier] = {}
var _was_on_floor: bool = true


func configure(profile: RoleProfile) -> void:
	super(profile)
	if not profile:
		return
	move_speed = profile.move_speed
	sprint_speed = profile.sprint_speed
	jump_velocity = profile.jump_velocity


## Registra un modificador. La misma source sobrescribe el anterior.
func add_modifier(source: StringName, modifier: MovementModifier) -> void:
	_modifiers[source] = modifier


func remove_modifier(source: StringName) -> void:
	_modifiers.erase(source)


func get_current_speed() -> float:
	var base: float = sprint_speed if is_sprinting() else move_speed
	var multiplier: float = 1.0
	for modifier: MovementModifier in _modifiers.values():
		multiplier *= modifier.speed_multiplier
	return base * multiplier


func is_sprinting() -> bool:
	if not wants_sprint or input_direction.is_zero_approx():
		return false
	for modifier: MovementModifier in _modifiers.values():
		if not modifier.allows_sprint:
			return false
	return true


func _physics_process(delta: float) -> void:
	if not player:
		return
	_read_input()
	apply_motion(delta)


## Separado de _physics_process para poder simularlo con input inyectado desde
## los tests, sin depender del teclado.
func apply_motion(delta: float) -> void:
	if not player:
		return

	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta

	var direction: Vector3 = (player.global_basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()
	var target: Vector3 = direction * get_current_speed()
	var control: float = acceleration if player.is_on_floor() else acceleration * air_control

	player.velocity.x = move_toward(player.velocity.x, target.x, control * delta)
	player.velocity.z = move_toward(player.velocity.z, target.z, control * delta)

	if Input.is_action_just_pressed(&"jump") and player.is_on_floor():
		player.velocity.y = jump_velocity * _get_jump_multiplier()
		jumped.emit()

	player.move_and_slide()

	if player.is_on_floor() and not _was_on_floor:
		landed.emit()
	_was_on_floor = player.is_on_floor()


func _read_input() -> void:
	input_direction = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	wants_sprint = Input.is_action_pressed(&"sprint")


func _get_jump_multiplier() -> float:
	var multiplier: float = 1.0
	for modifier: MovementModifier in _modifiers.values():
		multiplier *= modifier.jump_multiplier
	return multiplier
