class_name FollowProgress
extends RefCounted

## Dice si un enemigo que va hacia el sitio de una creencia se está acercando a él.

const MIN_PROGRESS: float = 0.5

var patience: float = 4.0

var _mark: float = INF
var _left: float = 0.0
var _goal: Vector3 = Vector3.INF


## Empieza a contar de nuevo.
func reset() -> void:
	_mark = INF
	_left = patience


## Avanza un frame y devuelve [code]true[/code] si se está acercando a [param goal].
func update(locomotion: EnemyLocomotion, goal: Vector3, delta: float) -> bool:
	if _goal == Vector3.INF or goal.distance_to(_goal) > MIN_PROGRESS:
		_goal = goal
		reset()
	if not locomotion.is_moving and not locomotion.is_crossing():
		if locomotion.get_flat_distance_to(goal) <= locomotion.arrive_distance * 2.0:
			_left = 0.0
			return false
		_left -= delta
		return _left > 0.0
	var remaining: float = locomotion.get_remaining_distance()
	if remaining <= _mark - MIN_PROGRESS:
		_mark = remaining
		_left = patience
		return true
	_left -= delta
	return _left > 0.0


## Devuelve los segundos de paciencia que le quedan.
func get_patience_left() -> float:
	return maxf(_left, 0.0)
