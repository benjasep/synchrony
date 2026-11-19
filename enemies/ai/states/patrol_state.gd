class_name PatrolState
extends EnemyState

## Patrulla: anda entre los marcadores del mapa con una pausa en cada uno.

signal point_reached(point: Node3D)

## Grupos cuyos nodos son puntos de patrulla.
@export var marker_groups: Array[StringName] = [ObjectiveZone.GROUP, Enemy.SPAWN_POINT_GROUP]
## Segundos mínimos de pausa en cada punto.
@export var pause_min: float = 2.0
## Segundos máximos de pausa en cada punto.
@export var pause_max: float = 5.0
## Si corre en vez de andar.
@export var run: bool = false
## Segundos entre intentos cuando no encuentra ningún punto al que ir.
@export var retry_interval: float = 1.0
## Metros, en planta, a los que le vale quedarse de un marcador al que no llega.
@export var approach_distance: float = 6.0
## Si al entrar prefiere un primer punto cercano.
@export var prefer_near_on_entry: bool = true
## Metros: escala de distancia del sorteo del primer punto.
@export var near_scale: float = 10.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _current_point: Node3D = null
var _last_point: Node3D = null
var _pause_left: float = 0.0
var _first_pick: bool = false


## Siembra el generador al azar.
func _ready() -> void:
	rng.randomize()


## Suelta la presa, escucha la llegada y el atasco y sale hacia el primer punto.
func enter() -> void:
	memory.clear_target()
	_current_point = null
	_pause_left = 0.0
	_first_pick = true
	locomotion.arrived.connect(_on_arrived)
	locomotion.blocked.connect(_on_blocked)
	_go_to_next_point()


## Deja de escuchar la llegada y el atasco.
func exit() -> void:
	if locomotion.arrived.is_connected(_on_arrived):
		locomotion.arrived.disconnect(_on_arrived)
	if locomotion.blocked.is_connected(_on_blocked):
		locomotion.blocked.disconnect(_on_blocked)
	_current_point = null


## Descuenta la pausa al llegar y sale hacia el siguiente punto.
func tick(delta: float) -> void:
	if _current_point and locomotion.is_moving:
		return
	_current_point = null
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	_go_to_next_point()


## Devuelve el punto hacia el que va, o [code]null[/code].
func get_current_point() -> Node3D:
	return _current_point


## Devuelve el último punto al que llegó o en el que se atascó, o [code]null[/code].
func get_last_point() -> Node3D:
	return _last_point


## Devuelve los puntos de patrulla del nivel, sin repetir.
func get_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for group: StringName in marker_groups:
		for node: Node in get_tree().get_nodes_in_group(group):
			var point: Node3D = node as Node3D
			if point and point.is_inside_tree() and not points.has(point):
				points.append(point)
	return points


## Devuelve el peso en el sorteo del primer punto de uno a [param distance] metros.
func get_nearness_weight(distance: float) -> float:
	return exp(-maxf(distance, 0.0) / maxf(near_scale, 0.001))


## Baraja [param points] dando más probabilidad de ir primero a los cercanos a [param origin].
func order_by_nearness(points: Array[Node3D], origin: Vector3,
		generator: RandomNumberGenerator) -> Array[Node3D]:
	var keys: Dictionary[Node3D, float] = {}
	for point: Node3D in points:
		var offset: Vector3 = point.global_position - origin
		offset.y = 0.0
		var weight: float = maxf(get_nearness_weight(offset.length()), 1e-300)
		keys[point] = log(maxf(generator.randf(), 1e-12)) / weight
	var ordered: Array[Node3D] = points.duplicate()
	ordered.sort_custom(func(a: Node3D, b: Node3D) -> bool: return keys[a] > keys[b])
	return ordered


## Sale hacia el siguiente punto al que sabe ir, sin repetir el último.
func _go_to_next_point() -> void:
	var candidates: Array[Node3D] = get_points()
	candidates.erase(_last_point)
	if _first_pick and prefer_near_on_entry:
		candidates = order_by_nearness(candidates, enemy.global_position, rng)
	else:
		candidates.shuffle()
	var speed: float = locomotion.run_speed if run else locomotion.walk_speed
	for point: Node3D in candidates:
		var target: Vector3 = point.global_position
		if locomotion.move_to(target, speed):
			_current_point = point
			_first_pick = false
			return
		var near: Vector3 = locomotion.get_nearest_reachable_point(target)
		if Vector2(near.x - target.x, near.z - target.z).length() <= approach_distance \
				and locomotion.move_to(near, speed):
			_current_point = point
			_first_pick = false
			return
	_pause_left = retry_interval


## Apunta el punto alcanzado y sortea la pausa.
func _on_arrived() -> void:
	if not _current_point:
		return
	_last_point = _current_point
	_current_point = null
	_pause_left = lerpf(pause_min, maxf(pause_min, pause_max), randf())
	point_reached.emit(_last_point)


## Apunta el punto en el que se atascó y elige otro sin pausa.
func _on_blocked() -> void:
	if not _current_point:
		return
	_last_point = _current_point
	_current_point = null
	_pause_left = 0.0
