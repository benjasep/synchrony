class_name InvestigateState
extends EnemyState

## Investigar: sigue lo que cree y busca en movimiento hasta dejar de creerlo.

signal phase_changed(phase: Phase)
signal search_point_reached(point: Vector3, contradicted: bool)

enum Phase {
	FOLLOWING,
	PEEKING,
	CIRCLING,
	SEARCHING,
}

## Temas de creencia que puede seguir.
@export var focus_topics: Array[StringName] = [EnemyMemory.BELIEF_TRAIL, EnemyMemory.BELIEF_NOISE]
## Segundos de antigüedad de la evidencia por debajo de los que corre en vez de andar.
@export var run_below_age: float = 3.0
## Segundos que sostiene su foco sin acercarse a él.
@export var follow_patience: float = 4.0
## Certeza que quita a su foco cada punto de búsqueda en el que no percibe a nadie.
@export_range(0.0, 1.0, 0.01) var search_contradiction: float = 0.1
## Segundos entre órdenes de movimiento mientras sigue su foco.
@export var move_interval: float = 0.25

@export_group("Búsqueda")
## Metros, en planta, del sitio de su foco a los que empieza a buscar.
@export var search_start_distance: float = 2.0
## Metros, en planta, a los que da por alcanzado un punto de búsqueda.
@export var search_reach_distance: float = 1.0
## Metros, en planta, hasta los que busca alrededor del centro.
@export var search_radius: float = 8.0
## Metros entre anillos y entre muestras de la consulta.
@export var search_spacing: float = 1.5
## Metros, en planta, a los que tiene que quedar el siguiente punto de donde está.
@export var search_min_distance: float = 2.5
## Metros alrededor de un punto visitado en los que no vuelve a buscar.
@export var visited_radius: float = 2.0
## Metros de camino que, como mucho, puede costar llegar a un punto de búsqueda.
@export var search_max_path: float = 16.0
## Peso de la consulta hacia donde iba lo que sigue.
@export var direction_weight: float = 1.0
## Peso de la consulta para los puntos ocultos a sus ojos.
@export var hidden_weight: float = 1.0
## Peso de la consulta para los puntos cerca del centro.
@export var proximity_weight: float = 1.0
## Peso de la consulta para alejarse de lo visitado.
@export var avoid_weight: float = 0.5
## Segundos tras los que reintenta si la consulta no dio ningún punto.
@export var retry_interval: float = 0.5

@export_group("Umbral")
## Metros, en planta, de la boca de una barrera a los que da por llegada.
@export var mouth_arrive_distance: float = 1.0
## Segundos mínimos que se asoma al hueco.
@export var peek_min: float = 2.0
## Segundos máximos que se asoma al hueco.
@export var peek_max: float = 3.0
## Segundos mínimos que ronda la boca.
@export var circle_min: float = 3.0
## Segundos máximos que ronda la boca.
@export var circle_max: float = 4.0
## Metros, en planta, que se aparta como mucho de la boca al rondar.
@export var circle_radius: float = 2.5
## Segundos que mira el hueco en cada parada al rondar.
@export var circle_pause: float = 0.6

var _phase: Phase = Phase.FOLLOWING
var _focus_topic: StringName = &""
var _focus_usec: int = 0
var _goal: Vector3 = Vector3.ZERO
var _on_threshold: bool = false
var _barrier_passage: Passage = null
var _barrier_mouth: Vector3 = Vector3.ZERO
var _move_left: float = 0.0
var _phase_left: float = 0.0
var _circle_moving: bool = false
var _pause_left: float = 0.0
var _search_point: Vector3 = Vector3.ZERO
var _has_search_point: bool = false
var _visited: PackedVector3Array = PackedVector3Array()
var _retry_left: float = 0.0
var _last_query: SpotQuery = null
var _progress: FollowProgress = FollowProgress.new()


## Toma como foco la creencia más reciente; sin ninguna, termina.
func enter() -> void:
	_focus_topic = &""
	_focus_usec = 0
	_last_query = null
	var focus: EnemyBelief = _pick_focus()
	if not focus:
		finish()
		return
	_orient(focus)


## Olvida el punto de búsqueda.
func exit() -> void:
	_has_search_point = false


## Se reorienta si su foco cambió; si no, avanza la fase.
func tick(delta: float) -> void:
	if is_finished:
		return
	var focus: EnemyBelief = _pick_focus()
	if not focus:
		finish()
		return
	if focus.topic != _focus_topic or focus.updated_usec != _focus_usec:
		_orient(focus)
		return
	match _phase:
		Phase.FOLLOWING:
			_tick_following(focus, delta)
		Phase.PEEKING:
			_tick_peeking(focus, delta)
		Phase.CIRCLING:
			_tick_circling(focus, delta)
		Phase.SEARCHING:
			_tick_searching(focus, delta)


## Devuelve la fase actual.
func get_phase() -> Phase:
	return _phase


## Devuelve el nombre de la fase actual.
func get_phase_name() -> String:
	return get_phase_label(_phase)


## Devuelve el nombre de [param phase].
static func get_phase_label(phase: Phase) -> String:
	match phase:
		Phase.PEEKING:
			return "asomándose"
		Phase.CIRCLING:
			return "rondando"
		Phase.SEARCHING:
			return "buscando"
	return "siguiendo"


## Devuelve el tema de la creencia que sigue.
func get_focus_topic() -> StringName:
	return _focus_topic


## Devuelve el sitio de su foco al que va.
func get_destination() -> Vector3:
	return _goal


## Devuelve [code]true[/code] mientras recorre puntos de búsqueda.
func is_searching() -> bool:
	return _phase == Phase.SEARCHING


## Devuelve [code]true[/code] si su foco termina en una barrera.
func is_on_threshold() -> bool:
	return _on_threshold


## Devuelve el hueco de la barrera en cuyo umbral está, o [code]null[/code].
func get_threshold_passage() -> Passage:
	return _barrier_passage if _on_threshold and is_instance_valid(_barrier_passage) else null


## Devuelve [code]true[/code] si va hacia un punto de búsqueda o de ronda.
func has_search_point() -> bool:
	return _has_search_point


## Devuelve el punto de búsqueda o de ronda hacia el que va.
func get_search_point() -> Vector3:
	return _search_point


## Devuelve una copia de los puntos que ya visitó.
func get_visited_points() -> PackedVector3Array:
	return _visited.duplicate()


## Devuelve la última consulta de sitios que lanzó, o [code]null[/code].
func get_last_query() -> SpotQuery:
	return _last_query


## Devuelve la creencia de [code]focus_topics[/code] con la evidencia más reciente.
func _pick_focus() -> EnemyBelief:
	var best: EnemyBelief = null
	for topic: StringName in focus_topics:
		var belief: EnemyBelief = memory.get_belief(topic)
		if belief and (not best or belief.updated_usec > best.updated_usec):
			best = belief
	return best


## Toma [param focus] como foco y sale hacia su sitio.
func _orient(focus: EnemyBelief) -> void:
	_focus_topic = focus.topic
	_focus_usec = focus.updated_usec
	_on_threshold = false
	_barrier_passage = null
	_has_search_point = false
	_visited.clear()
	_move_left = 0.0
	_progress.patience = follow_patience
	_progress.reset()
	_set_phase(Phase.FOLLOWING)
	_tick_following(focus, 0.0)


## Va al sitio de su foco y lo sostiene mientras se acerca.
func _tick_following(focus: EnemyBelief, delta: float) -> void:
	var barrier: EnemyLocomotion.Barrier = memory.get_belief_barrier(focus)
	_goal = memory.get_belief_goal(focus)
	var distance: float = locomotion.get_flat_distance_to(_goal)
	if barrier:
		if distance <= mouth_arrive_distance and not locomotion.is_moving:
			_begin_peeking(focus, barrier)
			return
	elif distance <= search_start_distance:
		_begin_searching(focus)
		return
	_move_left -= delta
	if _move_left <= 0.0 or not locomotion.is_moving:
		_move_left = move_interval
		var speed: float = locomotion.run_speed if focus.age < run_below_age \
			else locomotion.walk_speed
		if not locomotion.move_to(_goal, speed):
			_begin_searching(focus)
			return
	_progress.patience = follow_patience
	if _progress.update(locomotion, _goal, delta):
		memory.hold(focus.topic)


## Devuelve [code]true[/code] mientras sigue su foco y lo sostiene.
func is_holding_focus() -> bool:
	return _phase == Phase.FOLLOWING and memory != null and memory.is_held(_focus_topic)


## Se para en la boca de [param barrier] a mirar el hueco.
func _begin_peeking(focus: EnemyBelief, barrier: EnemyLocomotion.Barrier) -> void:
	_on_threshold = true
	_barrier_passage = barrier.passage
	_barrier_mouth = barrier.mouth
	if focus.topic == EnemyMemory.BELIEF_TRAIL:
		memory.note_escape(barrier.passage)
	locomotion.stop()
	_phase_left = lerpf(peek_min, maxf(peek_min, peek_max), randf())
	_set_phase(Phase.PEEKING)


## Mira el hueco hasta que se le acaba el tiempo y pasa a rondar.
func _tick_peeking(focus: EnemyBelief, delta: float) -> void:
	_look_at_passage(delta)
	_phase_left -= delta
	if _phase_left <= 0.0:
		_begin_circling(focus)


## Empieza a rondar la boca durante un tiempo sorteado.
func _begin_circling(_focus: EnemyBelief) -> void:
	_phase_left = lerpf(circle_min, maxf(circle_min, circle_max), randf())
	_set_phase(Phase.CIRCLING)
	_next_circle_spot()


## Ronda la boca parándose a mirar el hueco y, al acabar, pasa a buscar.
func _tick_circling(focus: EnemyBelief, delta: float) -> void:
	_phase_left -= delta
	if _phase_left <= 0.0:
		_begin_searching(focus)
		return
	if _circle_moving:
		if locomotion.is_moving:
			return
		_circle_moving = false
		_has_search_point = false
		_pause_left = circle_pause
	_look_at_passage(delta)
	_pause_left -= delta
	if _pause_left <= 0.0:
		_next_circle_spot()


## Elige un punto cerca de la boca, de su lado, y va andando.
func _next_circle_spot() -> void:
	var query: SpotQuery = SpotQuery.new()
	query.center = _barrier_mouth
	query.radius = circle_radius
	query.ring_spacing = circle_radius * 0.5
	query.sample_spacing = 1.0
	query.rotation = randf() * TAU
	query.min_distance = 1.0
	query.proximity_weight = 1.0
	if _has_search_point:
		query.avoid_points = PackedVector3Array([_search_point])
		query.avoid_radius = 0.8
	_limit_to_own_side(query)
	query.allow_squeeze = false
	query.max_path_length = circle_radius * 3.0
	var results: Array[SpotQuery.Candidate] = query.run(locomotion)
	_last_query = query
	_has_search_point = false
	if not results.is_empty():
		_search_point = results[0].position
		_circle_moving = locomotion.walk_to(_search_point, false)
		_has_search_point = _circle_moving
	if not _circle_moving:
		_pause_left = circle_pause


## Empieza a buscar y pide el primer punto.
func _begin_searching(focus: EnemyBelief) -> void:
	_set_phase(Phase.SEARCHING)
	_visited.append(_barrier_mouth if _on_threshold else _goal)
	_next_search_point(focus)


## Recorre los puntos de búsqueda y pide uno nuevo al llegar o al pararse.
func _tick_searching(focus: EnemyBelief, delta: float) -> void:
	if _has_search_point:
		if locomotion.get_flat_distance_to(_search_point) <= search_reach_distance:
			_reach_search_point(focus)
			return
		if locomotion.is_moving:
			return
		_visited.append(_search_point)
		_has_search_point = false
		_next_search_point(focus)
		return
	_retry_left -= delta
	if _retry_left <= 0.0:
		_next_search_point(focus)


## Apunta el punto alcanzado y, si no percibe a nadie, contradice su foco.
func _reach_search_point(focus: EnemyBelief) -> void:
	var point: Vector3 = _search_point
	_visited.append(point)
	_has_search_point = false
	var contradicted: bool = senses.get_perceived_players().is_empty()
	if contradicted:
		memory.contradict(focus.topic, search_contradiction)
	search_point_reached.emit(point, contradicted)
	if memory.get_belief(focus.topic) != focus:
		return
	_next_search_point(focus)


## Pide a la consulta el siguiente punto de búsqueda y va andando.
func _next_search_point(focus: EnemyBelief) -> void:
	var results: Array[SpotQuery.Candidate] = _run_search_query(focus)
	if results.is_empty() and _visited.size() > 1:
		_visited = PackedVector3Array([_visited[_visited.size() - 1]])
		results = _run_search_query(focus)
	_has_search_point = false
	if results.is_empty():
		_retry_left = retry_interval
		return
	_search_point = results[0].position
	_has_search_point = locomotion.walk_to(_search_point, not _on_threshold)
	if not _has_search_point:
		_visited.append(_search_point)
		_retry_left = retry_interval


## Lanza la consulta de búsqueda y la guarda.
func _run_search_query(focus: EnemyBelief) -> Array[SpotQuery.Candidate]:
	var query: SpotQuery = SpotQuery.new()
	query.center = _barrier_mouth if _on_threshold else _goal
	query.radius = search_radius
	query.ring_spacing = search_spacing
	query.sample_spacing = search_spacing
	query.rotation = randf() * TAU
	query.proximity_weight = proximity_weight
	if not _on_threshold:
		query.direction = focus.get_direction()
		query.direction_weight = direction_weight
	query.avoid_points = _visited
	query.avoid_radius = visited_radius
	query.avoid_weight = avoid_weight
	query.observers = PackedVector3Array([senses.get_eye_position()])
	query.observer_range = senses.sight_range
	query.hidden_weight = hidden_weight
	query.min_distance = search_min_distance
	query.allow_squeeze = not _on_threshold
	query.max_path_length = search_max_path
	if _on_threshold:
		_limit_to_own_side(query)
	_last_query = query
	return query.run(locomotion)


## Limita [param query] a su lado del muro del hueco.
func _limit_to_own_side(query: SpotQuery) -> void:
	if not is_instance_valid(_barrier_passage):
		return
	query.boundary_point = _barrier_passage.global_position
	var inward: Vector3 = _barrier_passage.global_position - _barrier_mouth
	inward.y = 0.0
	query.boundary_normal = inward


## Gira hacia el hueco de la barrera sin moverse.
func _look_at_passage(delta: float) -> void:
	if is_instance_valid(_barrier_passage):
		locomotion.face_towards(_barrier_passage.global_position, delta)


## Cambia de fase y emite [code]phase_changed[/code].
func _set_phase(phase: Phase) -> void:
	var changed: bool = phase != _phase
	_phase = phase
	if changed or phase == Phase.FOLLOWING:
		phase_changed.emit(phase)
