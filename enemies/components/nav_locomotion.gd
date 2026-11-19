class_name NavLocomotion
extends EnemyLocomotion

## Locomoción a pie por la malla de navegación de su tamaño de agente, con gravedad y colisiones.

enum CrossingPhase {
	NONE,
	ALIGNING,
	CROSSING,
}

const LINE_GAIN: float = 6.0
const LINE_MAX_SPEED: float = 0.6
const ALIGN_GAIN: float = 8.0
const JOIN_TOLERANCE: float = 0.05
const JOIN_ANGLE_DEGREES: float = 4.0
const JOIN_GAIN: float = 2.5
const JOIN_REFERENCE_SPEED: float = 0.5

## Agente de [LevelNavigation] cuya malla usa.
@export var navigation_agent: StringName = LevelNavigation.LARGE_AGENT

@export_group("Camino")
## Metros, en planta, a los que da por pasado un punto intermedio del camino.
@export var waypoint_distance: float = 0.3
## Metros, en planta, entre el final del camino y el destino para darlo por alcanzable.
@export var reach_tolerance: float = 1.5
## Segundos sin avanzar [code]stuck_distance[/code] tras los que se da por atascado.
@export var stuck_time: float = 1.5
## Metros que tiene que avanzar para no contar como atascado.
@export var stuck_distance: float = 0.15

@export_group("Huecos")
## Si sabe colarse por huecos más chicos que su cuerpo.
@export var can_squeeze: bool = true
## Velocidad, en m/s, mientras cruza colándose.
@export var squeeze_speed: float = 0.4
## Metros antes del muro a los que empieza a frenar hacia [code]squeeze_speed[/code].
@export var squeeze_approach_start: float = 4.0
## Metros antes del muro a los que ya va a [code]squeeze_speed[/code].
@export var squeeze_approach_end: float = 3.0
## Metros pasado el muro a los que empieza a recuperar su marcha.
@export var squeeze_release_start: float = 1.5
## Metros pasado el muro a los que ya recuperó su marcha.
@export var squeeze_release_end: float = 2.1
## Metros antes de la entrada de un hueco a los que deja el camino y se une a su eje.
@export var join_distance: float = 2.0
## Metros antes del muro a los que ya tiene que ir sobre el eje y mirando a lo largo de él.
@export var join_before_wall: float = 2.4
## Metros, en local, que la línea media del modelo se aparta del origen del enemigo.
@export var midline_offset: Vector3 = Vector3.ZERO
## Metros de tolerancia al colocarse quieta sobre el eje de un hueco.
@export var align_distance: float = 0.03
## Grados de tolerancia al colocarse quieta sobre el eje de un hueco.
@export_range(0.0, 45.0, 0.5, "degrees") var align_angle: float = 1.0

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _path_links: Dictionary[int, LevelNavigation.PassageLink] = {}
var _stuck_left: float = 0.0
var _stuck_origin: Vector3 = Vector3.ZERO

var _phase: CrossingPhase = CrossingPhase.NONE
var _link: LevelNavigation.PassageLink = null
var _cross_from: Vector3 = Vector3.ZERO
var _cross_to: Vector3 = Vector3.ZERO
var _cross_direction: Vector3 = Vector3.ZERO
var _cross_facing: Vector3 = Vector3.ZERO
var _reversed: bool = false
var _join_limit: float = 0.0
var _precise: bool = false
var _replan_after_crossing: bool = false

var _parameters: NavigationPathQueryParameters3D = NavigationPathQueryParameters3D.new()
var _result: NavigationPathQueryResult3D = NavigationPathQueryResult3D.new()


## Prepara las consultas de camino y abandona el cruce si el enemigo se retira o reaparece.
func _ready() -> void:
	super()
	_parameters.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES \
		| NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_RIDS
	if enemy:
		enemy.retreated.connect(_abandon_crossing)
		enemy.returned.connect(_abandon_crossing)


## Devuelve el camino que está siguiendo; vacío si no va a ningún sitio.
func get_path_points() -> PackedVector3Array:
	return _path


## Devuelve el índice del punto del camino hacia el que va.
func get_path_index() -> int:
	return _path_index


## Devuelve los enlaces de hueco del camino en curso, por índice del punto donde empiezan.
func get_path_links() -> Dictionary[int, LevelNavigation.PassageLink]:
	return _path_links.duplicate()


## Devuelve la fase del cruce en curso.
func get_crossing_phase() -> CrossingPhase:
	return _phase


## Devuelve el [Passage] que está cruzando o al que se está colocando, o [code]null[/code].
func get_crossing_passage() -> Passage:
	return _link.passage if _link else null


## Devuelve [code]true[/code] mientras atraviesa un hueco.
func is_crossing() -> bool:
	return _phase == CrossingPhase.CROSSING


## Devuelve los metros, en planta, que le quedan del camino en curso.
func get_remaining_distance() -> float:
	if not enemy or (not is_moving and _phase != CrossingPhase.CROSSING):
		return 0.0
	var from: Vector3 = enemy.global_position
	var total: float = 0.0
	if _phase != CrossingPhase.NONE and _link:
		var line: Vector3 = _cross_to - _cross_from
		line.y = 0.0
		var offset: Vector3 = from - _cross_from
		offset.y = 0.0
		total += maxf(line.length() - offset.dot(_cross_direction), 0.0)
		from = _cross_to
	for index: int in range(_path_index, _path.size()):
		var step: Vector3 = _path[index] - from
		step.y = 0.0
		total += step.length()
		from = _path[index]
	return total


## Devuelve [code]true[/code] si se está colocando quieta ante un hueco antes de cruzar.
func is_aligning_in_place() -> bool:
	return _phase == CrossingPhase.ALIGNING and _precise


## Devuelve [code]true[/code] si la malla de su agente existe y ya está horneada.
func is_navigation_ready() -> bool:
	var region: LevelNavigation = LevelNavigation.find(navigation_agent)
	return region != null and region.is_baked and region.get_polygon_count() > 0


## Devuelve las capas de navegación que puede usar; la de colarse, solo si sabe y [param squeeze].
func get_navigation_layers(squeeze: bool = true) -> int:
	if can_squeeze and squeeze:
		return LevelNavigation.WALK_LAYER | LevelNavigation.SQUEEZE_LAYER
	return LevelNavigation.WALK_LAYER


## Devuelve el camino por la malla desde donde está hasta [param target].
func find_path(target: Vector3, squeeze: bool = true) -> PackedVector3Array:
	var links: Dictionary[int, LevelNavigation.PassageLink] = {}
	return _query_path(target, links, get_navigation_layers(squeeze))


## Devuelve, en orden, los [Passage] por los que pasa el camino hasta [param target].
func find_passages(target: Vector3, squeeze: bool = true) -> Array[Passage]:
	var links: Dictionary[int, LevelNavigation.PassageLink] = {}
	_query_path(target, links, get_navigation_layers(squeeze))
	var indices: Array[int] = links.keys()
	indices.sort()
	var passages: Array[Passage] = []
	for index: int in indices:
		passages.append(links[index].passage)
	return passages


## Devuelve lo que cuesta, en metros, su camino hasta [param target], huecos incluidos.
func measure_path(target: Vector3, squeeze: bool = true) -> float:
	var links: Dictionary[int, LevelNavigation.PassageLink] = {}
	var path: PackedVector3Array = _query_path(target, links, get_navigation_layers(squeeze))
	if path.is_empty():
		return INF
	var length: float = 0.0
	var from: Vector3 = enemy.global_position
	for point: Vector3 in path:
		length += from.distance_to(point)
		from = point
	var region: LevelNavigation = LevelNavigation.find(navigation_agent)
	for index: int in links:
		if links[index].squeezes and region:
			length += region.squeeze_cost
	return length


## Devuelve el punto de su malla más cercano a [param target].
func get_nearest_reachable_point(target: Vector3) -> Vector3:
	if not is_navigation_ready():
		return target
	var region: LevelNavigation = LevelNavigation.find(navigation_agent)
	return NavigationServer3D.map_get_closest_point(region.get_navigation_map(), target)


## Devuelve el punto más cercano a [param target] al que llega desde donde está.
func get_closest_reachable_point(target: Vector3, squeeze_allowed: bool = true) -> Vector3:
	if not enemy or not is_navigation_ready():
		return target
	var region: LevelNavigation = LevelNavigation.find(navigation_agent)
	_parameters.map = region.get_navigation_map()
	_parameters.start_position = enemy.global_position
	_parameters.target_position = target
	_parameters.navigation_layers = get_navigation_layers(squeeze_allowed)
	NavigationServer3D.query_path(_parameters, _result)
	var path: PackedVector3Array = _result.path
	if path.is_empty():
		return enemy.global_position
	return path[path.size() - 1]


## Devuelve la barrera de colarse entre el enemigo y [param target_point], o [code]null[/code].
func find_barrier(target_point: Vector3) -> EnemyLocomotion.Barrier:
	if can_squeeze or not enemy or not is_navigation_ready():
		return null
	var links: Dictionary[int, LevelNavigation.PassageLink] = {}
	if not _query_path(target_point, links, LevelNavigation.WALK_LAYER).is_empty():
		return null
	links.clear()
	var path: PackedVector3Array = _query_path(target_point, links,
		LevelNavigation.WALK_LAYER | LevelNavigation.SQUEEZE_LAYER)
	if path.is_empty():
		return null
	var indices: Array[int] = links.keys()
	indices.sort()
	for index: int in indices:
		var link: LevelNavigation.PassageLink = links[index]
		if not link.squeezes:
			continue
		var barrier: EnemyLocomotion.Barrier = EnemyLocomotion.Barrier.new()
		barrier.kind = EnemyLocomotion.Barrier.Kind.SQUEEZE
		barrier.passage = link.passage
		barrier.mouth = path[index]
		return barrier
	return null


## Devuelve el enlace del nivel por [param passage] en la malla de su agente, o [code]null[/code].
func get_passage_link(passage: Passage) -> LevelNavigation.PassageLink:
	var region: LevelNavigation = LevelNavigation.find(navigation_agent)
	if not region or not passage:
		return null
	for link: LevelNavigation.PassageLink in region.get_passage_links():
		if link.passage == passage:
			return link
	return null


## Planea el camino hasta [param target_point], o lo deja para cuando salga del hueco.
func _plan(target_point: Vector3) -> bool:
	if _phase == CrossingPhase.CROSSING:
		_replan_after_crossing = true
		return true
	var links: Dictionary[int, LevelNavigation.PassageLink] = {}
	var path: PackedVector3Array = _query_path(target_point, links,
		get_navigation_layers(_squeeze))
	if path.is_empty():
		return false
	_phase = CrossingPhase.NONE
	_link = null
	_path = path
	_path_links = links
	_path_index = 0
	_reset_stuck()
	return true


## Devuelve [code]true[/code] si hay camino hasta [param target_point].
func _can_reach(target_point: Vector3, squeeze_allowed: bool) -> bool:
	return not find_path(target_point, squeeze_allowed).is_empty()


## Lleva el último punto del camino al nuevo destino.
func _on_retargeted() -> void:
	if not _path.is_empty():
		_path[_path.size() - 1] = get_target()


## Olvida el camino.
func _on_stopped() -> void:
	_path = PackedVector3Array()
	_path_links.clear()
	_path_index = 0
	_replan_after_crossing = false
	if _phase == CrossingPhase.CROSSING:
		return
	_phase = CrossingPhase.NONE
	_link = null


## Avanza por el camino o por el cruce en curso y comprueba si llegó o se atascó.
func _advance(delta: float) -> void:
	if _phase == CrossingPhase.CROSSING:
		_advance_crossing(delta)
		return
	if not is_moving:
		return
	if _phase == CrossingPhase.NONE:
		_skip_reached_waypoints()
	if _phase == CrossingPhase.ALIGNING:
		_advance_alignment(delta)
		return
	if _path_index >= _path.size():
		_finish_arrived()
		return
	var to_point: Vector3 = _path[_path_index] - enemy.global_position
	to_point.y = 0.0
	if to_point.length_squared() > 0.0001:
		var speed: float = _speed
		if _path_index == _path.size() - 1:
			speed = minf(speed, sqrt(2.0 * braking * to_point.length()))
		_walk_towards(to_point, speed, delta)
	else:
		_move(Vector3.ZERO, delta)
	if _is_stuck(delta):
		_finish_blocked()


## Da por pasados los puntos ya alcanzados y empieza a alinearse al llegar a un hueco.
func _skip_reached_waypoints() -> void:
	while _path_index < _path.size():
		var is_last: bool = _path_index == _path.size() - 1
		var distance: float = get_flat_distance_to(_path[_path_index])
		if _path_links.has(_path_index) and not is_last \
				and distance <= maxf(join_distance, waypoint_distance):
			_begin_alignment(_path_links[_path_index], _path[_path_index])
			_path_index += 2
			return
		if distance > (arrive_distance if is_last else waypoint_distance):
			return
		_path_index += 1


## Prepara el cruce de [param link] por el extremo más cercano a [param entry].
func _begin_alignment(link: LevelNavigation.PassageLink, entry: Vector3) -> void:
	var side: int = 0
	if entry.distance_squared_to(link.ends[1]) < entry.distance_squared_to(link.ends[0]):
		side = 1
	var heading: float = 1.0 if side == 0 else -1.0
	_cross_direction = link.passage.get_axis() * heading
	_cross_facing = _cross_direction
	var facing_forward: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	var offset: Vector3 = Basis(Vector3.UP,
		facing_forward.signed_angle_to(_cross_direction, Vector3.UP)) * midline_offset
	offset.y = 0.0
	_cross_from = link.passage.get_axis_point(-heading * link.reach[side]) - offset
	_cross_to = link.passage.get_axis_point(heading * link.reach[1 - side]) - offset
	_join_limit = maxf(link.reach[side] - join_before_wall, 0.0)
	_precise = false
	_link = link
	_reversed = false
	_phase = CrossingPhase.ALIGNING
	_reset_stuck()


## Se une andando a la línea del cruce y empieza a cruzar en cuanto va sobre ella.
func _advance_alignment(delta: float) -> void:
	var offset: Vector3 = enemy.global_position - _cross_from
	offset.y = 0.0
	var along: float = offset.dot(_cross_direction)
	var drift: float = offset.dot(Vector3.UP.cross(_cross_direction))
	if not _precise and along > _join_limit + align_distance:
		_precise = true
	if _precise:
		_align_in_place(_cross_from + _cross_direction * _join_limit, delta)
		return
	var angle: float = absf(get_facing().signed_angle_to(_cross_facing, Vector3.UP))
	if along >= -align_distance and absf(drift) <= JOIN_TOLERANCE \
			and angle <= deg_to_rad(JOIN_ANGLE_DEGREES):
		_begin_crossing()
		return
	var current: float = Vector2(enemy.velocity.x, enemy.velocity.z).length()
	var steer: float = atan2(JOIN_GAIN * absf(drift), maxf(current, JOIN_REFERENCE_SPEED))
	var toward_line: Vector3 = -Vector3.UP.cross(_cross_direction) * signf(drift)
	_walk_towards(_cross_direction * cos(steer) + toward_line * sin(steer), _get_joining_speed(),
		delta)
	if _is_stuck(delta):
		_finish_blocked()


## Se coloca quieta en [param spot], mirando a lo largo de la línea del cruce.
func _align_in_place(spot: Vector3, delta: float) -> void:
	var to_spot: Vector3 = spot - enemy.global_position
	to_spot.y = 0.0
	var distance: float = to_spot.length()
	var angle: float = absf(get_facing().signed_angle_to(_cross_facing, Vector3.UP))
	if distance <= align_distance and angle <= deg_to_rad(align_angle):
		_begin_crossing()
		return
	var wanted: Vector3 = Vector3.ZERO
	if distance > align_distance * 0.5:
		wanted = to_spot / distance * minf(minf(_speed, walk_speed), distance * ALIGN_GAIN)
	_turn_towards(_cross_facing, delta)
	_move(wanted, delta)
	if _is_stuck(delta) and distance > align_distance:
		_finish_blocked()


## Devuelve la velocidad a la que se une al eje del hueco.
func _get_joining_speed() -> float:
	return minf(_get_crossing_speed(_get_past_wall()), walk_speed)


## Devuelve los metros que lleva pasado el muro del hueco que cruza.
func _get_past_wall() -> float:
	return (enemy.global_position - _link.passage.global_position).dot(_cross_direction)


## Empieza a atravesar el hueco.
func _begin_crossing() -> void:
	_phase = CrossingPhase.CROSSING
	if _link.squeezes:
		enemy.set_squeezing(true)
	_reset_stuck()


## Avanza por la línea del cruce corrigiendo lo que se aparte de ella.
func _advance_crossing(delta: float) -> void:
	var line: Vector3 = _cross_to - _cross_from
	line.y = 0.0
	var length: float = line.length()
	var offset: Vector3 = enemy.global_position - _cross_from
	offset.y = 0.0
	var done: float = offset.dot(_cross_direction)
	if done >= length - align_distance:
		_end_crossing()
		return
	var lateral: Vector3 = Vector3.UP.cross(_cross_direction)
	var drift: float = offset.dot(lateral)
	var wanted: Vector3 = _cross_direction * _get_crossing_speed(_get_past_wall()) \
		- lateral * clampf(drift * LINE_GAIN, -LINE_MAX_SPEED, LINE_MAX_SPEED)
	_turn_towards(_cross_facing, delta)
	_move(wanted, delta)
	if _is_stuck(delta):
		_handle_crossing_blocked()


## Devuelve la velocidad del cruce a [param past] metros pasado el muro.
func _get_crossing_speed(past: float) -> float:
	var cruise: float = _speed if is_moving and _speed > 0.0 else walk_speed
	if not _link.squeezes:
		return cruise
	if _reversed:
		return squeeze_speed
	var pace: float = minf(cruise, walk_speed)
	if past < 0.0:
		return lerpf(pace, squeeze_speed, smoothstep(-squeeze_approach_start,
			maxf(-squeeze_approach_end, -squeeze_approach_start + 0.01), past))
	return lerpf(squeeze_speed, pace, smoothstep(squeeze_release_start,
		maxf(squeeze_release_end, squeeze_release_start + 0.01), past))


## Retrocede por donde vino si algo le cierra el paso a mitad del hueco.
func _handle_crossing_blocked() -> void:
	if _reversed:
		_end_crossing()
		return
	_reversed = true
	var swap: Vector3 = _cross_from
	_cross_from = _cross_to
	_cross_to = swap
	_cross_direction = -_cross_direction
	_reset_stuck()


## Sale del hueco y decide qué sigue.
func _end_crossing() -> void:
	var gave_up: bool = _reversed
	var replan: bool = _replan_after_crossing
	_abandon_crossing()
	if gave_up:
		_finish_blocked()
		return
	if not is_moving:
		_start_braking()
		return
	if replan and not _plan(get_target()):
		_finish_blocked()
		return
	_reset_stuck()


## Olvida el cruce en curso y devuelve al enemigo su caja de movimiento normal.
func _abandon_crossing() -> void:
	if enemy and _phase == CrossingPhase.CROSSING and _link and _link.squeezes:
		enemy.set_squeezing(false)
	_phase = CrossingPhase.NONE
	_link = null
	_reversed = false
	_replan_after_crossing = false


## Gira hacia [param direction] y avanza hacia donde mira, más lento cuanto más le falta girar.
func _walk_towards(direction: Vector3, speed: float, delta: float) -> void:
	_turn_towards(direction, delta)
	var facing: Vector3 = get_facing()
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	_move(facing * speed * clampf(facing.dot(flat), 0.0, 1.0), delta)


## Acelera hacia [param wanted], aplica la gravedad y mueve al enemigo.
func _move(wanted: Vector3, delta: float) -> void:
	var velocity: Vector3 = enemy.velocity
	if not enemy.is_on_floor():
		velocity += enemy.get_gravity() * delta
	var flat: Vector2 = Vector2(velocity.x, velocity.z).move_toward(
		Vector2(wanted.x, wanted.z), acceleration * delta)
	enemy.velocity = Vector3(flat.x, velocity.y, flat.y)
	enemy.move_and_slide()


## Pide el camino hasta [param target] y anota en [param links] los huecos que cruza.
func _query_path(target: Vector3, links: Dictionary[int, LevelNavigation.PassageLink],
		layers: int) -> PackedVector3Array:
	var empty: PackedVector3Array = PackedVector3Array()
	if not enemy or not is_navigation_ready():
		return empty
	var region: LevelNavigation = LevelNavigation.find(navigation_agent)
	_parameters.map = region.get_navigation_map()
	_parameters.start_position = enemy.global_position
	_parameters.target_position = target
	_parameters.navigation_layers = layers
	NavigationServer3D.query_path(_parameters, _result)
	var path: PackedVector3Array = _result.path
	if path.is_empty():
		return empty
	var end: Vector3 = path[path.size() - 1]
	if Vector2(end.x - target.x, end.z - target.z).length() > reach_tolerance:
		return empty
	var types: PackedInt32Array = _result.path_types
	var rids: Array[RID] = _result.path_rids
	for index: int in mini(mini(types.size(), rids.size()), path.size() - 1):
		if types[index] != NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
			continue
		var link: LevelNavigation.PassageLink = region.get_passage_link(rids[index])
		if link:
			links[index] = link
	return path


## Devuelve [code]true[/code] si lleva [code]stuck_time[/code] sin avanzar.
func _is_stuck(delta: float) -> bool:
	if get_flat_distance_to(_stuck_origin) > stuck_distance:
		_reset_stuck()
		return false
	_stuck_left -= delta
	return _stuck_left <= 0.0


## Reinicia la cuenta de atasco desde la posición actual.
func _reset_stuck() -> void:
	_stuck_left = stuck_time
	_stuck_origin = enemy.global_position
