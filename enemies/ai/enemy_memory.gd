class_name EnemyMemory
extends Node

## Lo que sabe un enemigo: su presa, sus creencias, los golpes que recibió y contadores de eventos.

signal belief_updated(belief: EnemyBelief)
signal belief_forgotten(topic: StringName)
signal event_counted(event: StringName, count: int)
signal target_changed(target: Player)

const EVENT_DRIVEN_OFF: StringName = &"ahuyentada"
const EVENT_VOLUNTARY_RETREAT: StringName = &"retirada_voluntaria"
const EVENT_WEAK_SPOT_HIT: StringName = &"golpe_punto_debil"
const EVENT_CHARGE_CUT: StringName = &"carga_cortada"
const EVENT_HIT_LANDED: StringName = &"golpe_conectado"
const EVENT_PREY_KILLED: StringName = &"presa_muerta"
const EVENT_ESCAPED_THROUGH_PASSAGE: StringName = &"escapada_por_hueco"

const BELIEF_TRAIL: StringName = &"rastro"
const BELIEF_NOISE: StringName = &"ruido"
const TRAIL_COLLISION_MASK: int = 1
const MIN_SAMPLE_INTERVAL: float = 0.05
const MIN_HEARING_INTERVAL: float = 0.25
const MIN_PREDICTION_SPEED: float = 0.2
const PASSAGE_VERTICAL_MARGIN: float = 1.0

@export var enemy: Enemy
@export var senses: EnemySenses
@export var combat: EnemyCombat
@export var locomotion: EnemyLocomotion

@export_group("Creencias")
## Segundos que tarda en agotarse la certeza del rastro sin percibir a la presa.
@export var trail_lifetime: float = 10.0
## Segundos que tarda en agotarse la certeza de un ruido sin dueño.
@export var noise_lifetime: float = 10.0
## Certeza, de 0 a 1, que da oír algo.
@export_range(0.0, 1.0, 0.01) var hearing_certainty: float = 1.0
## Velocidad máxima que le supone a una presa, en m/s.
@export var prey_max_speed: float = 3.0
## Segundos: constante de tiempo del suavizado de la velocidad estimada.
@export var velocity_smoothing: float = 0.3
## Segundos hacia delante que predice dónde estará la presa.
@export var prediction_horizon: float = 2.0
## Metros que, como mucho, adelanta la predicción sobre la última posición.
@export var max_prediction_distance: float = 6.0
## Segundos durante los que un cruce de hueco observado sigue diciendo por dónde se fue.
@export var crossing_memory: float = 3.0
## Metros de margen a cada lado de un hueco para contar que un tramo pasó por él.
@export var passage_aim_margin: float = 0.5
## Metros al otro lado de un hueco a los que apunta la predicción cuando no hay enlace.
@export var passage_clearance: float = 3.5
## Metros sobre el suelo a los que van los rayos del rastro.
@export var trail_ray_height: float = 0.3
## Metros antes de una pared en los que se detiene la predicción.
@export var wall_margin: float = 0.5
## Segundos entre consultas de la barrera de una creencia sin evidencia nueva.
@export var barrier_refresh: float = 0.5
## Metros de margen al decidir si un ruido pudo ser de la presa.
@export var noise_match_margin: float = 2.0
## Segundos de margen sobre la edad del rastro al decidir si un ruido pudo ser de la presa.
@export var noise_match_time_margin: float = 0.5
## Segundos tras verla o tocarla durante los que un ruido suyo no mueve el rastro.
@export var sight_over_hearing: float = 0.5

var last_stimulus: Stimulus = null
var last_stimulus_usec: int = 0
var last_seen_position: Vector3 = Vector3.ZERO
var last_seen_usec: int = 0
var events: Dictionary[StringName, int] = {}
var damage_by_player: Dictionary[int, float] = {}

var _target: Player = null
var _last_hit_usec: Dictionary[int, int] = {}
var _seconds_since_seen: float = INF

var _beliefs: Dictionary[StringName, EnemyBelief] = {}
var _caches: Dictionary[StringName, BeliefCache] = {}
var _time: float = 0.0
var _trail_velocity_known: bool = false
var _escape_passage: Passage = null
var _holds: Dictionary[StringName, int] = {}


## Predicción, hueco, barrera y destino calculados para una creencia.
class BeliefCache:
	extends RefCounted
	var prediction_dirty: bool = true
	var prediction: Vector3 = Vector3.ZERO
	var passage: Passage = null
	var side: float = 0.0
	var barrier_dirty: bool = true
	var barrier_at: float = 0.0
	var barrier: EnemyLocomotion.Barrier = null
	var goal: Vector3 = Vector3.ZERO


## Un tramo que pasa por un [Passage].
class PassageCrossing:
	extends RefCounted
	var passage: Passage
	var side: float = 0.0
	var fraction: float = 0.0


## Conecta los sentidos, la salud, la retirada y los ataques del enemigo.
func _ready() -> void:
	if senses:
		senses.stimulus_perceived.connect(_on_stimulus_perceived)
		senses.perception_updated.connect(_on_perception_updated)
	if enemy:
		enemy.retreated.connect(_on_enemy_retreated)
		if enemy.health:
			enemy.health.damaged.connect(_on_enemy_damaged)
	if combat:
		if combat.melee:
			combat.melee.strike_resolved.connect(_on_strike_resolved)
		if combat.grab:
			combat.grab.victim_released.connect(_on_victim_released)


## Cuenta el tiempo sin percibir a la presa y envejece las creencias.
func _physics_process(delta: float) -> void:
	if last_seen_usec > 0:
		_seconds_since_seen += delta
	if not _is_server():
		return
	_time += delta
	_age_beliefs(delta)


## Suma [param amount] al contador [param event] y devuelve el nuevo valor.
func bump(event: StringName, amount: int = 1) -> int:
	var value: int = events.get(event, 0) + amount
	events[event] = value
	event_counted.emit(event, value)
	return value


## Devuelve cuántas veces ha pasado [param event].
func count(event: StringName) -> int:
	return events.get(event, 0)


## Devuelve [code]true[/code] si tiene una presa válida y viva.
func has_target() -> bool:
	return is_instance_valid(_target) and _target.is_inside_tree() and _target.health != null \
		and not _target.health.is_dead


## Devuelve la presa si es válida, o [code]null[/code].
func get_target() -> Player:
	return _target if has_target() else null


## Fija la presa y, si la percibe ahora, le abre el rastro.
func set_target(player: Player) -> void:
	if not is_instance_valid(player):
		player = null
	var changed: bool = player != _target
	_target = player
	if changed:
		forget(BELIEF_TRAIL)
	if _target and senses and senses.can_perceive(_target):
		_record_sighting()
		_observe_prey()
	if changed:
		target_changed.emit(_target)


## Suelta la presa.
func clear_target() -> void:
	set_target(null)


## Devuelve los segundos desde que percibió a su presa por última vez.
func get_seconds_since_seen() -> float:
	return _seconds_since_seen if last_seen_usec > 0 else INF


## Devuelve el daño total que le hizo [param player].
func get_damage_from(player: Player) -> float:
	if not is_instance_valid(player) or not player.data:
		return 0.0
	return damage_by_player.get(player.data.id, 0.0)


## Devuelve el instante, en microsegundos, del último daño en [param zone].
func get_last_hit_usec(zone: Statics.HitZone) -> int:
	return _last_hit_usec.get(zone, 0)


## Devuelve [code]true[/code] si oyó algo o percibió a una presa.
func has_point_of_interest() -> bool:
	return get_point_of_interest_usec() > 0


## Devuelve el último sitio que conoce: el del último estímulo o el de la presa.
func get_point_of_interest() -> Vector3:
	if last_stimulus and last_stimulus_usec >= last_seen_usec:
		return last_stimulus.position
	return last_seen_position


## Devuelve el instante, en microsegundos, del punto de interés.
func get_point_of_interest_usec() -> int:
	var stimulus_usec: int = last_stimulus_usec if last_stimulus else 0
	return maxi(stimulus_usec, last_seen_usec)


## Devuelve la creencia sobre [param topic], o [code]null[/code].
func get_belief(topic: StringName) -> EnemyBelief:
	return _beliefs.get(topic, null)


## Devuelve todas sus creencias en una lista nueva.
func get_beliefs() -> Array[EnemyBelief]:
	var list: Array[EnemyBelief] = []
	list.assign(_beliefs.values())
	return list


## Sostiene este frame la creencia sobre [param topic] para que no pierda certeza.
func hold(topic: StringName) -> void:
	if _beliefs.has(topic):
		_holds[topic] = Engine.get_physics_frames()


## Devuelve [code]true[/code] si la creencia sobre [param topic] está sostenida.
func is_held(topic: StringName) -> bool:
	return _beliefs.has(topic) and _holds.get(topic, -2) >= Engine.get_physics_frames() - 1


## Devuelve la certeza de la creencia sobre [param topic].
func get_certainty(topic: StringName) -> float:
	var belief: EnemyBelief = get_belief(topic)
	return belief.certainty if belief else 0.0


## Crea o reemplaza la creencia sobre [param topic].
func remember(topic: StringName, position: Vector3, source: EnemyBelief.Source,
		certainty: float, lifetime: float, subject: Node3D = null) -> EnemyBelief:
	var belief: EnemyBelief = EnemyBelief.new()
	belief.topic = topic
	belief.position = position
	belief.source = source
	belief.certainty = clampf(certainty, 0.0, 1.0)
	belief.lifetime = lifetime
	belief.updated_usec = Time.get_ticks_usec()
	belief.subject = subject
	_beliefs[topic] = belief
	_caches[topic] = BeliefCache.new()
	_holds.erase(topic)
	if topic == BELIEF_TRAIL:
		_trail_velocity_known = false
		_escape_passage = null
	belief_updated.emit(belief)
	return belief


## Sube la certeza de la creencia sobre [param topic] y le renueva la vida.
func reinforce(topic: StringName, to_certainty: float) -> void:
	var belief: EnemyBelief = get_belief(topic)
	if not belief:
		return
	belief.reinforce(to_certainty)
	belief.lifetime = _get_lifetime(topic, belief.lifetime)
	belief_updated.emit(belief)


## Baja la certeza de la creencia sobre [param topic] en [param amount].
func contradict(topic: StringName, amount: float) -> void:
	var belief: EnemyBelief = get_belief(topic)
	if not belief:
		return
	belief.contradict(amount)
	if belief.is_exhausted():
		forget(topic)
		return
	belief_updated.emit(belief)


## Olvida la creencia sobre [param topic].
func forget(topic: StringName) -> void:
	if not _beliefs.has(topic):
		return
	_beliefs.erase(topic)
	_caches.erase(topic)
	_holds.erase(topic)
	if topic == BELIEF_TRAIL:
		_trail_velocity_known = false
		_escape_passage = null
	belief_forgotten.emit(topic)


## Olvida todas sus creencias.
func forget_all_beliefs() -> void:
	for topic: StringName in _beliefs.keys():
		forget(topic)


## Devuelve el rastro de su presa, o [code]null[/code].
func get_trail() -> EnemyBelief:
	return get_belief(BELIEF_TRAIL)


## Devuelve [code]true[/code] si tiene rastro de su presa.
func has_trail() -> bool:
	return _beliefs.has(BELIEF_TRAIL)


## Devuelve dónde cree que está ahora su presa.
func predict_trail() -> Vector3:
	return predict_belief(get_trail())


## Devuelve el hueco por el que cree que se fue su presa, o [code]null[/code].
func get_trail_passage() -> Passage:
	return get_belief_passage(get_trail())


## Devuelve hacia qué lado del hueco del rastro se fue: +1 o -1 en su Z local.
func get_trail_passage_side() -> float:
	return get_belief_passage_side(get_trail())


## Devuelve la barrera entre el enemigo y la predicción del rastro, o [code]null[/code].
func get_trail_barrier() -> EnemyLocomotion.Barrier:
	return get_belief_barrier(get_trail())


## Devuelve adónde ir para seguir el rastro.
func get_trail_goal() -> Vector3:
	return get_belief_goal(get_trail())


## Devuelve dónde cree que está ahora lo que describe [param belief].
func predict_belief(belief: EnemyBelief) -> Vector3:
	if not belief:
		return enemy.global_position if enemy else Vector3.ZERO
	return _predicted_cache(belief).prediction


## Devuelve el hueco por el que cree que se fue lo que describe [param belief].
func get_belief_passage(belief: EnemyBelief) -> Passage:
	if not belief:
		return null
	var passage: Passage = _predicted_cache(belief).passage
	return passage if is_instance_valid(passage) else null


## Devuelve hacia qué lado del hueco de [param belief] se fue: +1 o -1 en su Z local.
func get_belief_passage_side(belief: EnemyBelief) -> float:
	if not belief:
		return 0.0
	var cache: BeliefCache = _predicted_cache(belief)
	return cache.side if is_instance_valid(cache.passage) else 0.0


## Devuelve la barrera entre el enemigo y la predicción de [param belief], o [code]null[/code].
func get_belief_barrier(belief: EnemyBelief) -> EnemyLocomotion.Barrier:
	if not belief or not locomotion:
		return null
	return _refresh_route(belief).barrier


## Devuelve adónde ir para seguir [param belief].
func get_belief_goal(belief: EnemyBelief) -> Vector3:
	if not belief:
		return enemy.global_position if enemy else Vector3.ZERO
	if not locomotion:
		return predict_belief(belief)
	return _refresh_route(belief).goal


## Apunta que la presa escapó por [param passage] y cuenta la escapada.
func note_escape(passage: Passage) -> bool:
	if not _is_server() or not is_instance_valid(passage) or not has_trail():
		return false
	if passage == _escape_passage:
		return false
	_escape_passage = passage
	bump(EVENT_ESCAPED_THROUGH_PASSAGE)
	return true


## Devuelve el hueco por el que ya contó una escapada, o [code]null[/code].
func get_escape_passage() -> Passage:
	return _escape_passage if is_instance_valid(_escape_passage) else null


## Guarda el estímulo percibido y, en el servidor, lo atribuye.
func _on_stimulus_perceived(stimulus: Stimulus) -> void:
	last_stimulus = stimulus
	last_stimulus_usec = Time.get_ticks_usec()
	if stimulus and _is_server():
		_hear(stimulus)


## Actualiza la última posición y el rastro si percibe a su presa.
func _on_perception_updated() -> void:
	if has_target() and senses.can_perceive(_target):
		_record_sighting()
		_observe_prey()


## Guarda la posición actual de la presa como la última vista.
func _record_sighting() -> void:
	last_seen_position = _target.global_position
	last_seen_usec = Time.get_ticks_usec()
	_seconds_since_seen = 0.0


## Lleva el rastro a la posición actual de la presa y estima su velocidad.
func _observe_prey() -> void:
	if not _is_server() or not has_target():
		return
	var source: EnemyBelief.Source = EnemyBelief.Source.SIGHT if senses.can_see(_target) \
		else EnemyBelief.Source.TOUCH
	var current: Vector3 = _target.global_position
	var trail: EnemyBelief = get_trail()
	if not trail or trail.subject != _target:
		remember(BELIEF_TRAIL, current, source, 1.0, trail_lifetime, _target)
		return
	var interval: float = trail.age
	if interval < MIN_SAMPLE_INTERVAL:
		trail.source = source
		trail.reinforce(1.0)
		trail.lifetime = trail_lifetime
		return
	var step: Vector3 = _flatten(current - trail.position)
	var instant: Vector3 = step / interval
	if instant.length() > 2.0 * prey_max_speed:
		trail.velocity = Vector3.ZERO
		_trail_velocity_known = false
	else:
		if _trail_velocity_known:
			var blend: float = 1.0 - exp(-interval / maxf(velocity_smoothing, 0.001))
			trail.velocity = trail.velocity.lerp(instant, blend)
		else:
			trail.velocity = instant
			_trail_velocity_known = true
		_note_crossing(trail, trail.position, current, interval)
	_apply_evidence(trail, current, source, 1.0)


## Atribuye un ruido al rastro o a la creencia de ruido, o abre una nueva.
func _hear(stimulus: Stimulus) -> void:
	var trail: EnemyBelief = get_trail()
	if trail and _is_plausible(trail, stimulus.position):
		var sensed: bool = trail.source == EnemyBelief.Source.SIGHT \
			or trail.source == EnemyBelief.Source.TOUCH
		if (sensed and trail.age < sight_over_hearing) or _is_perceiving(trail.subject):
			reinforce(BELIEF_TRAIL, hearing_certainty)
			return
		var interval: float = maxf(trail.age, MIN_HEARING_INTERVAL)
		var step: Vector3 = _flatten(stimulus.position - trail.position)
		trail.velocity = (step / interval).limit_length(prey_max_speed)
		_trail_velocity_known = true
		_note_crossing(trail, trail.position, stimulus.position, interval)
		_apply_evidence(trail, stimulus.position, EnemyBelief.Source.HEARING, hearing_certainty)
		return
	var noise: EnemyBelief = get_belief(BELIEF_NOISE)
	if noise and _is_plausible(noise, stimulus.position):
		var interval: float = maxf(noise.age, MIN_HEARING_INTERVAL)
		var step: Vector3 = _flatten(stimulus.position - noise.position)
		noise.velocity = (step / interval).limit_length(prey_max_speed)
		_note_crossing(noise, noise.position, stimulus.position, interval)
		_apply_evidence(noise, stimulus.position, EnemyBelief.Source.HEARING, hearing_certainty)
		return
	remember(BELIEF_NOISE, stimulus.position, EnemyBelief.Source.HEARING, hearing_certainty,
		noise_lifetime)


## Devuelve [code]true[/code] si lo que describe [param belief] pudo llegar a [param point].
func _is_plausible(belief: EnemyBelief, point: Vector3) -> bool:
	var reach: float = prey_max_speed * (belief.age + noise_match_time_margin) + noise_match_margin
	return _flatten(point - belief.position).length() <= reach


## Da a [param belief] evidencia nueva: posición, fuente y certeza.
func _apply_evidence(belief: EnemyBelief, position: Vector3, source: EnemyBelief.Source,
		certainty: float) -> void:
	belief.position = position
	belief.source = source
	belief.reinforce(certainty)
	belief.lifetime = _get_lifetime(belief.topic, belief.lifetime)
	belief.age = 0.0
	belief.updated_usec = Time.get_ticks_usec()
	if belief.has_passage() and belief.passage_age > crossing_memory:
		belief.clear_passage()
	_invalidate(belief.topic)
	belief_updated.emit(belief)


## Apunta en [param belief] el hueco por el que pasa el tramo de [param from] a [param to].
func _note_crossing(belief: EnemyBelief, from: Vector3, to: Vector3, interval: float) -> void:
	var crossing: PassageCrossing = _find_crossing(from, to)
	if not crossing:
		return
	belief.passage = crossing.passage
	belief.passage_side = crossing.side
	belief.passage_age = interval * (1.0 - crossing.fraction)


## Devuelve el primer [Passage] por el que pasa el tramo de [param from] a [param to].
func _find_crossing(from: Vector3, to: Vector3) -> PassageCrossing:
	if not is_inside_tree() or _flatten(to - from).length_squared() < 0.000001:
		return null
	var best: PassageCrossing = null
	for node: Node in get_tree().get_nodes_in_group(Passage.GROUP):
		var passage: Passage = node as Passage
		if not passage or not passage.is_inside_tree():
			continue
		var axis: Vector3 = passage.get_axis()
		var start: float = (from - passage.global_position).dot(axis)
		var end: float = (to - passage.global_position).dot(axis)
		if start * end > 0.0 or is_equal_approx(start, end):
			continue
		var fraction: float = start / (start - end)
		var offset: Vector3 = from.lerp(to, fraction) - passage.global_position
		if absf(offset.dot(Vector3.UP.cross(axis))) > passage.size.x * 0.5 + passage_aim_margin:
			continue
		if offset.y < -PASSAGE_VERTICAL_MARGIN \
				or offset.y > passage.size.y + PASSAGE_VERTICAL_MARGIN:
			continue
		if best and best.fraction <= fraction:
			continue
		best = PassageCrossing.new()
		best.passage = passage
		best.side = signf(end - start)
		best.fraction = fraction
	return best


## Calcula la predicción de [param belief] y la guarda en [param cache].
func _compute_prediction(belief: EnemyBelief, cache: BeliefCache) -> void:
	cache.prediction_dirty = false
	cache.passage = null
	cache.side = 0.0
	var origin: Vector3 = belief.position
	var raw: Vector3 = origin
	var speed: float = belief.get_speed()
	if speed >= MIN_PREDICTION_SPEED:
		raw = origin + belief.get_direction() \
			* minf(speed * prediction_horizon, max_prediction_distance)
	var crossing: PassageCrossing = _find_crossing(origin, raw)
	if crossing:
		cache.passage = crossing.passage
		cache.side = crossing.side
	elif belief.has_passage() and belief.passage_age - belief.age <= crossing_memory:
		cache.passage = belief.passage
		cache.side = belief.passage_side
	var point: Vector3 = _beyond_passage(raw, cache.passage, cache.side) if cache.passage \
		else _cut_at_wall(origin, raw)
	cache.prediction = _snap_to_mesh(point)


## Rehace, si toca, la barrera y el destino de [param belief].
func _refresh_route(belief: EnemyBelief) -> BeliefCache:
	var cache: BeliefCache = _predicted_cache(belief)
	if not cache.barrier_dirty and _time - cache.barrier_at < barrier_refresh:
		return cache
	var predicted: Vector3 = cache.prediction
	cache.barrier_dirty = false
	cache.barrier_at = _time
	cache.barrier = locomotion.find_barrier(predicted)
	if cache.barrier:
		cache.goal = cache.barrier.mouth
	elif locomotion.can_reach(predicted):
		cache.goal = predicted
	else:
		cache.goal = locomotion.get_closest_reachable_point(predicted)
	return cache


## Devuelve la caché de [param belief] con la predicción al día.
func _predicted_cache(belief: EnemyBelief) -> BeliefCache:
	var cache: BeliefCache = null
	if _beliefs.get(belief.topic, null) == belief:
		cache = _caches.get(belief.topic, null)
		if not cache:
			cache = BeliefCache.new()
			_caches[belief.topic] = cache
	else:
		cache = BeliefCache.new()
	if cache.prediction_dirty:
		_compute_prediction(belief, cache)
	return cache


## Devuelve el punto al otro lado de [param passage] al que apunta la predicción.
func _beyond_passage(raw: Vector3, passage: Passage, side: float) -> Vector3:
	var minimum: float = passage_clearance
	var exit: Vector3 = passage.get_axis_point(side * passage_clearance)
	var link: LevelNavigation.PassageLink = locomotion.get_passage_link(passage) \
		if locomotion else null
	if link and link.reach.size() == 2 and link.ends.size() == 2:
		var index: int = 1 if side > 0.0 else 0
		minimum = link.reach[index]
		exit = link.ends[index]
	var along: float = (raw - passage.global_position).dot(passage.get_axis()) * side
	if along < minimum:
		return exit
	return _cut_at_wall(exit, raw)


## Devuelve [param to], o el punto antes de la pared que haya entre [param from] y él.
func _cut_at_wall(from: Vector3, to: Vector3) -> Vector3:
	var lift: Vector3 = Vector3.UP * trail_ray_height
	var hit: Dictionary = _cast_trail_ray(from + lift, to + lift)
	if hit.is_empty():
		return to
	var hit_point: Vector3 = (hit["position"] as Vector3) - lift
	var direction: Vector3 = _flatten(to - from).normalized()
	var back: float = minf(wall_margin, _flatten(hit_point - from).length())
	return hit_point - direction * back


## Devuelve el punto de la malla del enemigo más cercano a [param point].
func _snap_to_mesh(point: Vector3) -> Vector3:
	if not locomotion:
		return point
	var snapped: Vector3 = locomotion.get_nearest_reachable_point(point)
	var lift: Vector3 = Vector3.UP * trail_ray_height
	if not _cast_trail_ray(point + lift, snapped + lift).is_empty():
		return point
	return snapped


## Lanza un rayo contra el mundo de [param from] a [param to].
func _cast_trail_ray(from: Vector3, to: Vector3) -> Dictionary:
	if not enemy or not enemy.is_inside_tree() or from.is_equal_approx(to):
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to,
		TRAIL_COLLISION_MASK)
	return enemy.get_world_3d().direct_space_state.intersect_ray(query)


## Envejece las creencias [param delta] segundos y olvida las agotadas.
func _age_beliefs(delta: float) -> void:
	var spent: Array[StringName] = []
	for topic: StringName in _beliefs.keys():
		var belief: EnemyBelief = _beliefs[topic]
		if topic == BELIEF_TRAIL:
			if not _is_alive(belief.subject):
				spent.append(topic)
				continue
			if _is_perceiving(belief.subject):
				belief.grow_older(delta)
				continue
		if is_held(topic):
			belief.grow_older(delta)
			continue
		belief.decay(delta)
		if belief.is_exhausted():
			spent.append(topic)
	for topic: StringName in spent:
		forget(topic)


## Marca para rehacer la predicción y la barrera de la creencia sobre [param topic].
func _invalidate(topic: StringName) -> void:
	var cache: BeliefCache = _caches.get(topic, null)
	if cache:
		cache.prediction_dirty = true
		cache.barrier_dirty = true


## Devuelve la vida que corresponde a una creencia sobre [param topic].
func _get_lifetime(topic: StringName, fallback: float) -> float:
	if topic == BELIEF_TRAIL:
		return trail_lifetime
	if topic == BELIEF_NOISE:
		return noise_lifetime
	return fallback


## Devuelve [code]true[/code] si sus sentidos perciben ahora a [param subject].
func _is_perceiving(subject: Node3D) -> bool:
	if not senses or not is_instance_valid(subject):
		return false
	var player: Player = subject as Player
	return player != null and senses.can_perceive(player)


## Devuelve [code]true[/code] si [param subject] sigue en el árbol y vivo.
func _is_alive(subject: Node3D) -> bool:
	if not is_instance_valid(subject) or not subject.is_inside_tree():
		return false
	var player: Player = subject as Player
	return not player or (player.health != null and not player.health.is_dead)


## Devuelve [param vector] sin componente vertical.
static func _flatten(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


## Cuenta la retirada, suelta la presa y olvida sus creencias.
func _on_enemy_retreated() -> void:
	if not _is_server():
		return
	var driven_off: bool = enemy.health != null and enemy.health.is_dead
	bump(EVENT_DRIVEN_OFF if driven_off else EVENT_VOLUNTARY_RETREAT)
	clear_target()
	forget_all_beliefs()


## Apunta el golpe recibido: zona, momento y daño de quien fue.
func _on_enemy_damaged(amount: float, zone: Statics.HitZone, source: Node) -> void:
	_last_hit_usec[zone] = Time.get_ticks_usec()
	if zone == Statics.HitZone.PUNTO_DEBIL:
		bump(EVENT_WEAK_SPOT_HIT)
	var player: Player = source as Player
	if player and player.data:
		damage_by_player[player.data.id] = damage_by_player.get(player.data.id, 0.0) + amount


## Cuenta los golpes que conecta y las presas que mata.
func _on_strike_resolved(target: Player, hit: bool) -> void:
	if not hit:
		return
	bump(EVENT_HIT_LANDED)
	if is_instance_valid(target) and target.health and target.health.is_dead:
		bump(EVENT_PREY_KILLED)


## Cuenta la presa muerta si soltó a la víctima sin vida.
func _on_victim_released(_victim: Player, alive: bool) -> void:
	if not alive and _is_server():
		bump(EVENT_PREY_KILLED)


## Devuelve [code]true[/code] en el servidor o sin peer.
func _is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
