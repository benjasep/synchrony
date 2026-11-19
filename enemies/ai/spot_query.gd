class_name SpotQuery
extends RefCounted

## Consulta de sitios: genera candidatos sobre la malla de un enemigo alrededor de un centro, los
## puntúa y devuelve los mejores a los que llega.

const MAX_VERTICAL_SNAP: float = 1.0
const MIN_RING_SAMPLES: int = 6
const SIGHT_COLLISION_MASK: int = 1


## Un sitio candidato con su puntuación y lo que se sabe de él.
class Candidate:
	extends RefCounted

	var position: Vector3 = Vector3.ZERO
	var score: float = 0.0
	var hidden: float = 0.0
	var index: int = 0
	var checked: bool = false
	var reachable: bool = false
	var path_length: float = INF


var center: Vector3 = Vector3.ZERO
var radius: float = 8.0
var ring_spacing: float = 1.5
var sample_spacing: float = 1.5
var rotation: float = 0.0
var snap_tolerance: float = 0.5
var duplicate_distance: float = 0.75

var proximity_weight: float = 0.0
var direction: Vector3 = Vector3.ZERO
var direction_weight: float = 0.0
var avoid_points: PackedVector3Array = PackedVector3Array()
var avoid_radius: float = 2.0
var avoid_weight: float = 0.0
var observers: PackedVector3Array = PackedVector3Array()
var observer_range: float = INF
var target_height: float = 0.5
var hidden_weight: float = 0.0
var prefer_hidden: bool = true

var min_distance: float = 0.0
var boundary_point: Vector3 = Vector3.ZERO
var boundary_normal: Vector3 = Vector3.ZERO

var require_reachable: bool = true
var allow_squeeze: bool = true
var max_path_length: float = INF
var max_results: int = 1
var max_reach_checks: int = 16

var _candidates: Array[Candidate] = []
var _results: Array[Candidate] = []


## Genera, filtra y puntúa los candidatos y comprueba si [param locomotion] llega a los mejores.
func run(locomotion: EnemyLocomotion) -> Array[Candidate]:
	_candidates.clear()
	_results.clear()
	var enemy: Enemy = locomotion.enemy if locomotion else null
	var space: PhysicsDirectSpaceState3D = null
	if enemy and enemy.is_inside_tree():
		space = enemy.get_world_3d().direct_space_state
	var index: int = 0
	for sample: Vector3 in generate_samples():
		var spot: Vector3 = sample
		if locomotion:
			spot = locomotion.get_nearest_reachable_point(sample)
		if not _passes_filters(sample, spot, enemy):
			continue
		var candidate: Candidate = Candidate.new()
		candidate.position = spot
		candidate.index = index
		index += 1
		_score(candidate, space, enemy)
		_candidates.append(candidate)
	_candidates.sort_custom(_is_better)
	var checks: int = 0
	for candidate: Candidate in _candidates:
		if _results.size() >= max_results:
			break
		if not require_reachable or not locomotion:
			_results.append(candidate)
			continue
		if checks >= max_reach_checks:
			break
		checks += 1
		candidate.checked = true
		candidate.path_length = locomotion.measure_path(candidate.position, allow_squeeze)
		candidate.reachable = not is_inf(candidate.path_length) \
			and candidate.path_length <= max_path_length
		if candidate.reachable:
			_results.append(candidate)
	return _results.duplicate()


## Devuelve las muestras sin llevar a la malla: el centro y luego los anillos de dentro hacia fuera.
func generate_samples() -> PackedVector3Array:
	var samples: PackedVector3Array = PackedVector3Array([center])
	if ring_spacing <= 0.0 or sample_spacing <= 0.0:
		return samples
	var ring: int = 1
	while ring_spacing * ring <= radius + 0.001:
		var ring_radius: float = ring_spacing * ring
		var count: int = maxi(MIN_RING_SAMPLES, ceili(TAU * ring_radius / sample_spacing))
		var step: float = TAU / count
		var offset: float = rotation + (step * 0.5 if ring % 2 == 1 else 0.0)
		for i: int in count:
			var angle: float = offset + step * i
			samples.append(center + Vector3(cos(angle), 0.0, sin(angle)) * ring_radius)
		ring += 1
	return samples


## Devuelve los candidatos de la última consulta, del mejor al peor.
func get_candidates() -> Array[Candidate]:
	return _candidates.duplicate()


## Devuelve el resultado de la última consulta.
func get_results() -> Array[Candidate]:
	return _results.duplicate()


## Devuelve la puntuación más alta posible con los pesos actuales.
func get_max_score() -> float:
	var total: float = maxf(proximity_weight, 0.0) + maxf(avoid_weight, 0.0) \
		+ maxf(hidden_weight, 0.0)
	if _flat(direction).length_squared() > 0.000001:
		total += maxf(direction_weight, 0.0)
	return total


## Devuelve [code]true[/code] si [param spot] pasa los filtros para ser candidato.
func _passes_filters(sample: Vector3, spot: Vector3, enemy: Enemy) -> bool:
	if _flat(spot - sample).length() > snap_tolerance \
			or absf(spot.y - sample.y) > MAX_VERTICAL_SNAP:
		return false
	if _flat(spot - center).length() > radius:
		return false
	for other: Candidate in _candidates:
		if _flat(other.position - spot).length() < duplicate_distance:
			return false
	for point: Vector3 in avoid_points:
		if _flat(point - spot).length() < avoid_radius:
			return false
	if enemy and min_distance > 0.0 \
			and _flat(spot - enemy.global_position).length() < min_distance:
		return false
	var normal: Vector3 = _flat(boundary_normal)
	if normal.length_squared() > 0.000001 \
			and (spot - boundary_point).dot(normal.normalized()) > 0.0:
		return false
	return true


## Puntúa [param candidate] con los criterios que tienen peso.
func _score(candidate: Candidate, space: PhysicsDirectSpaceState3D, enemy: Enemy) -> void:
	var offset: Vector3 = _flat(candidate.position - center)
	var score: float = 0.0
	if proximity_weight != 0.0 and radius > 0.0:
		score += proximity_weight * (1.0 - clampf(offset.length() / radius, 0.0, 1.0))
	var wanted: Vector3 = _flat(direction)
	if direction_weight != 0.0 and wanted.length_squared() > 0.000001 and radius > 0.0:
		var along: float = offset.dot(wanted.normalized()) / radius
		score += direction_weight * (clampf(along, -1.0, 1.0) * 0.5 + 0.5)
	if avoid_weight != 0.0 and not avoid_points.is_empty() and avoid_radius > 0.0:
		var nearest: float = INF
		for point: Vector3 in avoid_points:
			nearest = minf(nearest, _flat(point - candidate.position).length())
		score += avoid_weight * clampf((nearest - avoid_radius) / avoid_radius, 0.0, 1.0)
	if not observers.is_empty():
		candidate.hidden = _hidden_fraction(candidate.position, space, enemy)
		if hidden_weight != 0.0:
			score += hidden_weight * (candidate.hidden if prefer_hidden else 1.0 - candidate.hidden)
	candidate.score = score


## Devuelve la fracción de [code]observers[/code] para los que [param spot] está oculto.
func _hidden_fraction(spot: Vector3, space: PhysicsDirectSpaceState3D, enemy: Enemy) -> float:
	var target: Vector3 = spot + Vector3.UP * target_height
	var hidden: int = 0
	for eye: Vector3 in observers:
		if _flat(spot - eye).length() > observer_range:
			hidden += 1
			continue
		if not space or eye.is_equal_approx(target):
			continue
		var exclude: Array[RID] = []
		if enemy:
			exclude.append(enemy.get_rid())
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, target,
			SIGHT_COLLISION_MASK, exclude)
		if not space.intersect_ray(query).is_empty():
			hidden += 1
	return float(hidden) / observers.size()


## Devuelve [code]true[/code] si [param a] va antes que [param b]: más puntuación o generado antes.
static func _is_better(a: Candidate, b: Candidate) -> bool:
	if not is_equal_approx(a.score, b.score):
		return a.score > b.score
	return a.index < b.index


## Devuelve [param vector] sin componente vertical.
static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)
