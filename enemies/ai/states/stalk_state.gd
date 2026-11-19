class_name StalkState
extends EnemyState

## Acecho: ronda a su presa a cierta distancia y sigue su rastro cuando la pierde.

## Metros, en planta, a los que ronda a la presa.
@export var stalk_distance: float = 6.0
## Metros de holgura alrededor de [code]stalk_distance[/code] en los que se queda quieta.
@export var distance_tolerance: float = 1.0
## Si se aparta corriendo en vez de andando.
@export var back_off_run: bool = true
## Segundos entre órdenes de movimiento.
@export var move_interval: float = 0.25
## Segundos de antigüedad del rastro por debajo de los que corre en vez de andar.
@export var run_below_age: float = 3.0
## Segundos que sostiene el rastro sin acercarse a él.
@export var follow_patience: float = 4.0

var _move_left: float = 0.0
var _backing_off: bool = false
var _following: bool = false
var _progress: FollowProgress = FollowProgress.new()


## Se asegura una presa entre los jugadores que percibe.
func enter() -> void:
	_move_left = 0.0
	_backing_off = false
	_following = false
	var current: Player = memory.get_target()
	if not current or not senses.can_perceive(current):
		var chosen: Player = brain.choose_target(senses.get_perceived_players())
		if chosen:
			memory.set_target(chosen)
	_ensure_target()


## Deja de apartarse y de seguir el rastro.
func exit() -> void:
	_backing_off = false
	_following = false


## Mantiene la distancia a la presa mirándola o, si no la percibe, sigue su rastro.
func tick(delta: float) -> void:
	_ensure_target()
	var target: Player = memory.get_target()
	if not target:
		locomotion.stop()
		return
	if _backing_off:
		if locomotion.is_moving:
			return
		_backing_off = false
	if not senses.can_perceive(target):
		_follow_trail(delta)
		return
	_following = false
	var focus: Vector3 = target.global_position
	var distance: float = locomotion.get_flat_distance_to(focus)
	var close_enough: bool = distance <= stalk_distance + distance_tolerance
	var too_close: bool = distance < stalk_distance - distance_tolerance
	if close_enough and not too_close:
		locomotion.stop()
		locomotion.face_towards(focus, delta)
		return
	if not locomotion.is_moving:
		locomotion.face_towards(focus, delta)
	_move_left -= delta
	if _move_left > 0.0:
		return
	_move_left = move_interval
	if not close_enough:
		locomotion.walk_to(focus)
		return
	_back_off_from(focus)


## Devuelve [code]true[/code] si está dentro de la holgura de acecho de su presa.
func is_holding_distance() -> bool:
	var target: Player = memory.get_target()
	if not target:
		return false
	return absf(locomotion.get_flat_distance_to(target.global_position) - stalk_distance) \
		<= distance_tolerance


## Devuelve [code]true[/code] mientras se aparta de la presa.
func is_backing_off() -> bool:
	return _backing_off


## Devuelve [code]true[/code] mientras sigue el rastro de la presa.
func is_following_trail() -> bool:
	return _following


## Va al sitio del rastro de la presa y lo sostiene mientras se acerca.
func _follow_trail(delta: float) -> void:
	var trail: EnemyBelief = memory.get_trail()
	var goal: Vector3 = memory.get_trail_goal() if trail else memory.last_seen_position
	var was_following: bool = _following
	_following = true
	if not was_following:
		_progress.patience = follow_patience
		_progress.reset()
	var arrived: bool = not locomotion.is_moving \
		and locomotion.get_flat_distance_to(goal) <= locomotion.arrive_distance * 2.0
	_move_left -= delta
	if not arrived and (not was_following or _move_left <= 0.0 or not locomotion.is_moving):
		_move_left = move_interval
		var age: float = trail.age if trail else INF
		var speed: float = locomotion.run_speed if age < run_below_age else locomotion.walk_speed
		locomotion.move_to(goal, speed)
	if trail and _progress.update(locomotion, goal, delta):
		memory.hold(EnemyMemory.BELIEF_TRAIL)


## Conserva la presa si sigue siendo válida o elige otra entre las que percibe.
func _ensure_target() -> void:
	var current: Player = memory.get_target()
	if current and TargetSelector.is_valid_prey(current):
		return
	if current and current.is_captured():
		return
	memory.set_target(brain.choose_target(senses.get_perceived_players()))


## Se aparta de [param focus] hasta [code]stalk_distance[/code].
func _back_off_from(focus: Vector3) -> void:
	var away: Vector3 = enemy.global_position - focus
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -locomotion.get_facing()
	var spot: Vector3 = focus + away.normalized() * stalk_distance
	spot.y = enemy.global_position.y
	var speed: float = locomotion.run_speed if back_off_run else locomotion.walk_speed
	_backing_off = locomotion.move_to(spot, speed)
	if not _backing_off:
		locomotion.stop()
