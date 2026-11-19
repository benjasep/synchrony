class_name ChargeState
extends EnemyState

## Carga: corre hacia la presa y la ataca en cuanto puede.

signal attack_launched(target: Player)

## Segundos que corre sin conseguir atacar antes de rendirse.
@export var max_duration: float = 6.0
## Segundos entre órdenes de persecución.
@export var chase_interval: float = 0.1

var _attacked: bool = false
var _chase_left: float = 0.0


## Sale corriendo hacia la presa; sin presa, termina.
func enter() -> void:
	_attacked = false
	_chase_left = 0.0
	var target: Player = memory.get_target()
	if not target:
		finish()
		return
	_chase(target)


## No hace nada: el estado que entra hereda el movimiento.
func exit() -> void:
	pass


## Persigue a la presa, la ataca en cuanto puede y termina cuando acaba el ataque.
func tick(delta: float) -> void:
	if _attacked:
		if not combat.is_busy():
			finish()
		return
	if is_finished:
		return
	var target: Player = memory.get_target()
	if not target or not TargetSelector.is_valid_prey(target):
		finish()
		return
	if combat.can_attack(target) and combat.attack(target):
		_attacked = true
		locomotion.halt()
		attack_launched.emit(target)
		return
	if time_in_state >= max_duration:
		finish()
		return
	_chase_left -= delta
	if _chase_left > 0.0:
		return
	_chase_left = chase_interval
	_chase(target)


## Devuelve [code]true[/code] si ya lanzó su ataque en esta carga.
func has_attacked() -> bool:
	return _attacked


## Corre hacia [param target], o hacia su rastro si no lo percibe.
func _chase(target: Player) -> void:
	var point: Vector3 = target.global_position if senses.can_perceive(target) \
		else memory.get_trail_goal()
	if not locomotion.run_to(point, false):
		finish()
