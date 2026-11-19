class_name AIDebugOverlay
extends Node3D

## Vista de depuración de la IA (F10): sentidos, camino, creencias y búsqueda de cada enemigo.

const VISUAL_LAYER: int = Statics.BODY_VISUAL_LAYER
const RESCAN_SECONDS: float = 1.0
const STIMULUS_FADE_SECONDS: float = 1.5
const CIRCLE_SEGMENTS: int = 48
const LABEL_HEIGHT: float = 2.4
const BAR_LENGTH: int = 10
const GROUND_LIFT: float = 0.05
const POST_HEIGHT: float = 1.2
const LINES_PRIORITY: int = 3
const LABEL_FONT_SIZE: int = 30
const ESCAPE_NOTICE_SECONDS: float = 3.0

const SIGHT_COLOR: Color = Color(0.3, 1.0, 0.4)
const TOUCH_COLOR: Color = Color(0.2, 0.9, 1.0)
const HEARING_COLOR: Color = Color(1.0, 0.9, 0.2)
const HINT_COLOR: Color = Color(0.75, 0.45, 1.0)
const PREDICTION_COLOR: Color = Color(1.0, 1.0, 1.0)
const PASSAGE_COLOR: Color = Color(1.0, 0.3, 0.9)
const BARRIER_COLOR: Color = Color(1.0, 0.15, 0.1)
const LAST_SEEN_COLOR: Color = Color(0.6, 0.6, 0.6, 0.35)
const NOISE_BELIEF_COLOR: Color = Color(1.0, 0.55, 0.1)
const SENSES_IDLE_COLOR: Color = Color(0.7, 0.7, 0.7, 0.5)
const SENSES_ALERT_COLOR: Color = Color(1.0, 0.25, 0.2, 0.9)
const PATH_COLOR: Color = Color(0.4, 0.75, 1.0)
const LABEL_COLOR: Color = Color(1.0, 1.0, 1.0)
const NOISE_STIMULUS_COLOR: Color = Color(1.0, 0.6, 0.2)
const PULSE_STIMULUS_COLOR: Color = Color(0.4, 0.6, 1.0)
const LIGHT_STIMULUS_COLOR: Color = Color(1.0, 1.0, 0.7)
const GOAL_COLOR: Color = Color(0.55, 1.0, 0.8)
const SEARCH_COLOR: Color = Color(0.3, 0.95, 1.0)
const VISITED_COLOR: Color = Color(0.3, 0.95, 1.0, 0.45)
const CANDIDATE_COLOR: Color = Color(1.0, 1.0, 1.0)
const UNREACHABLE_COLOR: Color = Color(1.0, 0.3, 0.25)

var _enemy_ids: Array[int] = []
var _rescan_left: float = 0.0
var _stimuli: Array[StimulusFlash] = []
var _bus: StimulusBus = null
var _warned_client: bool = false
var _lines: MeshInstance3D = null
var _mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
var _labels: Array[Label3D] = []
var _labels_used: int = 0
var _points: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _vertex_count: int = 0
var _escapes_seen: Dictionary[int, int] = {}
var _escape_notice: Dictionary[int, float] = {}


## Un estímulo que se está desvaneciendo.
class StimulusFlash:
	extends RefCounted
	var position: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	var kind: Statics.StimulusKind = Statics.StimulusKind.NOISE
	var cause: StringName = &""
	var age: float = 0.0


## Monta la malla de líneas y busca a los enemigos.
func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_material = CombatDebugOverlay.make_flat_material(Color.WHITE, LINES_PRIORITY)
	_material.vertex_color_use_as_albedo = true
	_lines = MeshInstance3D.new()
	_lines.name = "Lines"
	_lines.mesh = _mesh
	_lines.top_level = true
	CombatDebugOverlay.prepare_geometry(_lines)
	add_child(_lines)
	_rescan()


## Se desconecta del canal de estímulos.
func _exit_tree() -> void:
	_bind_bus(null)


## Rehace las líneas y las etiquetas del frame.
func _physics_process(delta: float) -> void:
	_points.clear()
	_colors.clear()
	_labels_used = 0
	_rescan_left -= delta
	if _rescan_left <= 0.0:
		_rescan()
	if _is_server():
		_bind_bus(StimulusBus.instance)
		for id: int in _enemy_ids:
			var enemy: Enemy = instance_from_id(id) as Enemy
			if enemy and enemy.is_inside_tree():
				_track_escapes(enemy, delta)
				_draw_enemy(enemy)
		_draw_stimuli(delta)
	elif not _warned_client:
		_warned_client = true
		Debug.log("Debug de IA: la IA solo existe en el servidor; en un cliente no se ve (F10)")
	_flush()


## Devuelve cuántos vértices de línea dibujó en el último frame.
func get_line_vertex_count() -> int:
	return _vertex_count


## Devuelve las etiquetas visibles del último frame.
func get_visible_labels() -> Array[Label3D]:
	var visible_labels: Array[Label3D] = []
	for i: int in mini(_labels_used, _labels.size()):
		visible_labels.append(_labels[i])
	return visible_labels


## Devuelve los enemigos con cerebro que está dibujando.
func get_enemies() -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	for id: int in _enemy_ids:
		var enemy: Enemy = instance_from_id(id) as Enemy
		if enemy and enemy.is_inside_tree():
			enemies.append(enemy)
	return enemies


## Devuelve el color de una fuente de creencia.
static func get_source_color(source: EnemyBelief.Source) -> Color:
	match source:
		EnemyBelief.Source.SIGHT:
			return SIGHT_COLOR
		EnemyBelief.Source.TOUCH:
			return TOUCH_COLOR
		EnemyBelief.Source.HEARING:
			return HEARING_COLOR
	return HINT_COLOR


## Devuelve el color de una clase de estímulo.
static func get_stimulus_color(kind: Statics.StimulusKind) -> Color:
	match kind:
		Statics.StimulusKind.PULSE:
			return PULSE_STIMULUS_COLOR
		Statics.StimulusKind.UNSTABLE_LIGHT:
			return LIGHT_STIMULUS_COLOR
	return NOISE_STIMULUS_COLOR


## Devuelve una barra de texto para [param value], de 0 a 1.
static func make_bar(value: float) -> String:
	var filled: int = clampi(roundi(value * BAR_LENGTH), 0, BAR_LENGTH)
	return "[%s%s]" % ["#".repeat(filled), "-".repeat(BAR_LENGTH - filled)]


## Busca en el árbol los [Enemy] con cerebro.
func _rescan() -> void:
	_rescan_left = RESCAN_SECONDS
	_enemy_ids.clear()
	if is_inside_tree():
		_collect_enemies(get_tree().root)


## Apunta los enemigos con cerebro que cuelgan de [param node], él incluido.
func _collect_enemies(node: Node) -> void:
	var enemy: Enemy = node as Enemy
	if enemy and enemy.get_node_or_null(^"Brain") is EnemyBrain:
		_enemy_ids.append(enemy.get_instance_id())
		return
	for child: Node in node.get_children():
		_collect_enemies(child)


## Devuelve [code]true[/code] si la etiqueta de [param enemy] avisa de una escapada por un hueco.
func is_escape_notice_visible(enemy: Enemy) -> bool:
	return enemy != null and _escape_notice.get(enemy.get_instance_id(), 0.0) > 0.0


## Enciende el aviso de escapada de [param enemy] cuando su memoria cuenta una, y lo va apagando.
func _track_escapes(enemy: Enemy, delta: float) -> void:
	var brain: EnemyBrain = enemy.get_node_or_null(^"Brain") as EnemyBrain
	if not brain or not brain.memory:
		return
	var id: int = enemy.get_instance_id()
	var count: int = brain.memory.count(EnemyMemory.EVENT_ESCAPED_THROUGH_PASSAGE)
	if _escapes_seen.has(id) and count > _escapes_seen[id]:
		_escape_notice[id] = ESCAPE_NOTICE_SECONDS
	elif _escape_notice.has(id):
		_escape_notice[id] = maxf(_escape_notice[id] - delta, 0.0)
	_escapes_seen[id] = count


## Dibuja todo lo de un enemigo: etiqueta, sentidos, camino, memoria y búsqueda.
func _draw_enemy(enemy: Enemy) -> void:
	var brain: EnemyBrain = enemy.get_node_or_null(^"Brain") as EnemyBrain
	if not brain:
		return
	if not enemy.is_retreated:
		if brain.senses:
			_draw_senses(brain.senses)
		if brain.locomotion:
			_draw_path(brain.locomotion)
	if brain.memory:
		_draw_memory(brain.memory)
	var investigate: InvestigateState = brain.current_state as InvestigateState
	if investigate:
		_draw_search(investigate)
	_add_label(_describe(enemy, brain), enemy.global_position + Vector3.UP * LABEL_HEIGHT,
		LABEL_COLOR, LABEL_FONT_SIZE)


## Devuelve el texto de la etiqueta de un enemigo.
func _describe(enemy: Enemy, brain: EnemyBrain) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(enemy.name))
	if not brain.active:
		lines.append("cerebro apagado")
	elif brain.current_state:
		lines.append("%s  %.1f s" % [brain.get_state_name(), brain.current_state.time_in_state])
	var focus: StringName = &""
	var investigate: InvestigateState = brain.current_state as InvestigateState
	if brain.active and investigate:
		focus = investigate.get_focus_topic()
		lines.append("fase: %s%s" % [investigate.get_phase_name(),
			" · umbral" if investigate.is_on_threshold() else ""])
	var memory: EnemyMemory = brain.memory
	if memory:
		var target: Player = memory.get_target()
		if target:
			var perceived: bool = brain.senses != null and brain.senses.can_perceive(target)
			lines.append("presa: %s · %s" % [_player_name(target),
				"la percibe" if perceived else "no la percibe"])
		else:
			lines.append("sin presa")
		for belief: EnemyBelief in memory.get_beliefs():
			lines.append("%s%s %s %.2f %s %.1f s%s" % ["» " if belief.topic == focus else "",
				belief.topic, make_bar(belief.certainty), belief.certainty,
				_source_name(belief.source), belief.age,
				" ⏸ en camino" if memory.is_held(belief.topic) else ""])
		if is_escape_notice_visible(enemy):
			lines.append("¡ESCAPADA POR HUECO! (%d)"
				% memory.count(EnemyMemory.EVENT_ESCAPED_THROUGH_PASSAGE))
	var walker: NavLocomotion = brain.locomotion as NavLocomotion
	if walker:
		var phase: String = ""
		match walker.get_crossing_phase():
			NavLocomotion.CrossingPhase.ALIGNING:
				phase = "cruce: se coloca · "
			NavLocomotion.CrossingPhase.CROSSING:
				phase = "cruce: cruza · "
		lines.append("%scolarse: %s" % [phase, "sí" if walker.can_squeeze else "no"])
	if enemy.is_retreated:
		lines.append("RETIRADA")
	return "\n".join(lines)


## Dibuja el cono de vista, el círculo del tacto y una línea a cada jugador percibido.
func _draw_senses(senses: EnemySenses) -> void:
	var perceived: Array[Player] = senses.get_perceived_players()
	var color: Color = SENSES_ALERT_COLOR if not perceived.is_empty() else SENSES_IDLE_COLOR
	var eye: Vector3 = senses.get_eye_position()
	var facing: Vector3 = senses.get_facing()
	if facing.length_squared() > 0.0001 and senses.sight_range > 0.0:
		if senses.sight_fov_degrees >= 359.0:
			_add_circle(eye, senses.sight_range, color)
		else:
			var half: float = deg_to_rad(senses.sight_fov_degrees) * 0.5
			var left: Vector3 = facing.rotated(Vector3.UP, half) * senses.sight_range
			var right: Vector3 = facing.rotated(Vector3.UP, -half) * senses.sight_range
			_add_line(eye, eye + left, color)
			_add_line(eye, eye + right, color)
			_add_arc(eye, right, half * 2.0, color)
	if senses.touch_radius > 0.0 and senses.enemy:
		_add_circle(senses.enemy.global_position + Vector3.UP * GROUND_LIFT, senses.touch_radius,
			color)
	for player: Player in perceived:
		var head: Vector3 = player.head.global_position if player.head \
			else player.global_position + Vector3.UP * 0.5
		_add_line(eye, head, SENSES_ALERT_COLOR)


## Dibuja el camino en curso y su destino.
func _draw_path(locomotion: EnemyLocomotion) -> void:
	if not locomotion.enemy or not locomotion.is_moving:
		return
	var from: Vector3 = locomotion.enemy.global_position + Vector3.UP * GROUND_LIFT
	var walker: NavLocomotion = locomotion as NavLocomotion
	if walker:
		var path: PackedVector3Array = walker.get_path_points()
		var links: Dictionary[int, LevelNavigation.PassageLink] = walker.get_path_links()
		for index: int in range(walker.get_path_index(), path.size()):
			var to: Vector3 = path[index] + Vector3.UP * GROUND_LIFT
			var color: Color = PATH_COLOR
			var link: LevelNavigation.PassageLink = links.get(index - 1, null)
			if link and link.squeezes:
				color = PASSAGE_COLOR
			_add_line(from, to, color)
			from = to
	else:
		_add_line(from, locomotion.get_target() + Vector3.UP * GROUND_LIFT, PATH_COLOR)
	_add_cross(locomotion.get_target(), 0.4, PATH_COLOR)


## Dibuja el rastro, la creencia de ruido y la última posición vista.
func _draw_memory(memory: EnemyMemory) -> void:
	if memory.last_seen_usec > 0:
		_add_cross(memory.last_seen_position, 0.3, LAST_SEEN_COLOR)
	var noise: EnemyBelief = memory.get_belief(EnemyMemory.BELIEF_NOISE)
	if noise:
		var noise_color: Color = _faded(NOISE_BELIEF_COLOR, noise.certainty)
		_add_circle(noise.position + Vector3.UP * GROUND_LIFT, 0.6, noise_color)
		_add_line(noise.position, noise.position + Vector3.UP * POST_HEIGHT, noise_color)
		_draw_route(memory, noise, noise_color)
	var trail: EnemyBelief = memory.get_trail()
	if not trail:
		return
	var color: Color = _faded(get_source_color(trail.source), trail.certainty)
	_add_marker(trail.position, color)
	_draw_route(memory, trail, color)


## Dibuja la velocidad, la predicción, el hueco, la barrera y el destino de [param belief].
func _draw_route(memory: EnemyMemory, belief: EnemyBelief, color: Color) -> void:
	if belief.get_speed() > 0.05:
		_add_arrow(belief.position + Vector3.UP * 0.3,
			belief.position + Vector3.UP * 0.3 + belief.velocity, color)
	var predicted: Vector3 = memory.predict_belief(belief)
	_add_line(belief.position + Vector3.UP * GROUND_LIFT, predicted + Vector3.UP * GROUND_LIFT,
		PREDICTION_COLOR)
	_add_marker(predicted, PREDICTION_COLOR)
	var passage: Passage = memory.get_belief_passage(belief)
	if passage:
		_draw_passage(passage)
	var barrier: EnemyLocomotion.Barrier = memory.get_belief_barrier(belief)
	if barrier:
		var mouth: Vector3 = barrier.mouth + Vector3.UP * GROUND_LIFT
		_add_line(mouth + Vector3(-0.4, 0.0, -0.4), mouth + Vector3(0.4, 0.0, 0.4), BARRIER_COLOR)
		_add_line(mouth + Vector3(-0.4, 0.0, 0.4), mouth + Vector3(0.4, 0.0, -0.4), BARRIER_COLOR)
		_add_line(mouth, mouth + Vector3.UP * POST_HEIGHT, BARRIER_COLOR)
		if is_instance_valid(barrier.passage):
			_add_line(mouth, barrier.passage.global_position + Vector3.UP * GROUND_LIFT,
				BARRIER_COLOR)
		_add_label("barrera", barrier.mouth + Vector3.UP * POST_HEIGHT, BARRIER_COLOR,
			LABEL_FONT_SIZE)
	var goal: Vector3 = memory.get_belief_goal(belief)
	_add_circle(goal + Vector3.UP * GROUND_LIFT, 0.5, GOAL_COLOR)
	if goal.distance_to(predicted) > 0.1:
		_add_line(predicted + Vector3.UP * GROUND_LIFT, goal + Vector3.UP * GROUND_LIFT,
			GOAL_COLOR)


## Dibuja la búsqueda de Investigar: candidatos, puntos visitados y el punto hacia el que va.
func _draw_search(investigate: InvestigateState) -> void:
	var query: SpotQuery = investigate.get_last_query()
	if query:
		var best: float = 0.0
		var worst: float = INF
		var candidates: Array[SpotQuery.Candidate] = query.get_candidates()
		for candidate: SpotQuery.Candidate in candidates:
			best = maxf(best, candidate.score)
			worst = minf(worst, candidate.score)
		for candidate: SpotQuery.Candidate in candidates:
			var weight: float = 1.0
			if best - worst > 0.0001:
				weight = (candidate.score - worst) / (best - worst)
			var color: Color = UNREACHABLE_COLOR if candidate.checked and not candidate.reachable \
				else CANDIDATE_COLOR
			color.a = lerpf(0.12, 0.6, weight)
			_add_cross(candidate.position, lerpf(0.06, 0.22, weight), color)
	for point: Vector3 in investigate.get_visited_points():
		_add_cross(point, 0.25, VISITED_COLOR)
	if investigate.has_search_point():
		var point: Vector3 = investigate.get_search_point()
		var ground: Vector3 = point + Vector3.UP * GROUND_LIFT
		var size: float = 0.2
		var corners: Array[Vector3] = [ground + Vector3(size, 0.0, 0.0),
			ground + Vector3(0.0, 0.0, size), ground + Vector3(-size, 0.0, 0.0),
			ground + Vector3(0.0, 0.0, -size)]
		for i: int in corners.size():
			_add_line(corners[i], corners[(i + 1) % corners.size()], SEARCH_COLOR)
		_add_line(ground, ground + Vector3.UP * POST_HEIGHT * 0.5, SEARCH_COLOR)


## Dibuja el contorno de un hueco.
func _draw_passage(passage: Passage) -> void:
	var half: float = passage.size.x * 0.5
	var frame: Transform3D = passage.global_transform
	var corners: Array[Vector3] = [frame * Vector3(-half, 0.0, 0.0),
		frame * Vector3(half, 0.0, 0.0), frame * Vector3(half, passage.size.y, 0.0),
		frame * Vector3(-half, passage.size.y, 0.0)]
	for i: int in corners.size():
		_add_line(corners[i], corners[(i + 1) % corners.size()], PASSAGE_COLOR)
	_add_line(corners[0], corners[2], PASSAGE_COLOR)
	_add_line(corners[1], corners[3], PASSAGE_COLOR)


## Dibuja los estímulos que se están desvaneciendo y descarta los que ya se desvanecieron.
func _draw_stimuli(delta: float) -> void:
	var alive: Array[StimulusFlash] = []
	for flash: StimulusFlash in _stimuli:
		flash.age += delta
		if flash.age >= STIMULUS_FADE_SECONDS:
			continue
		alive.append(flash)
		var color: Color = get_stimulus_color(flash.kind)
		color.a = 1.0 - flash.age / STIMULUS_FADE_SECONDS
		_add_circle(flash.position + Vector3.UP * GROUND_LIFT, flash.radius, color)
		_add_line(flash.position, flash.position + Vector3.UP * POST_HEIGHT, color)
		_add_label(str(flash.cause), flash.position + Vector3.UP * POST_HEIGHT, color,
			LABEL_FONT_SIZE)
	_stimuli = alive


## Apunta un estímulo que acaba de emitir el canal.
func _on_stimulus_emitted(stimulus: Stimulus) -> void:
	if not stimulus:
		return
	var flash: StimulusFlash = StimulusFlash.new()
	flash.position = stimulus.position
	flash.radius = stimulus.radius
	flash.kind = stimulus.kind
	flash.cause = stimulus.cause
	_stimuli.append(flash)


## Se conecta a [param bus] y se desconecta del anterior.
func _bind_bus(bus: StimulusBus) -> void:
	if bus == _bus:
		return
	if is_instance_valid(_bus) and _bus.stimulus_emitted.is_connected(_on_stimulus_emitted):
		_bus.stimulus_emitted.disconnect(_on_stimulus_emitted)
	_bus = bus
	if _bus:
		_bus.stimulus_emitted.connect(_on_stimulus_emitted)


## Sube las líneas del frame a la malla y oculta las etiquetas que sobran.
func _flush() -> void:
	_mesh.clear_surfaces()
	_vertex_count = _points.size()
	if _vertex_count >= 2:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
		for i: int in _vertex_count:
			_mesh.surface_set_color(_colors[i])
			_mesh.surface_add_vertex(_points[i])
		_mesh.surface_end()
	for i: int in range(_labels_used, _labels.size()):
		_labels[i].hide()


## Añade una línea de [param from] a [param to].
func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	_points.append(from)
	_points.append(to)
	_colors.append(color)
	_colors.append(color)


## Añade un círculo horizontal de radio [param radius] alrededor de [param center].
func _add_circle(center: Vector3, radius: float, color: Color) -> void:
	_add_arc(center, Vector3(radius, 0.0, 0.0), TAU, color)


## Añade un arco horizontal de [param angle] radianes alrededor de [param center].
func _add_arc(center: Vector3, start: Vector3, angle: float, color: Color) -> void:
	var steps: int = maxi(ceili(CIRCLE_SEGMENTS * absf(angle) / TAU), 2)
	var previous: Vector3 = center + start
	for i: int in range(1, steps + 1):
		var point: Vector3 = center + start.rotated(Vector3.UP, angle * i / steps)
		_add_line(previous, point, color)
		previous = point


## Añade una cruz horizontal de medio lado [param size] en [param at].
func _add_cross(at: Vector3, size: float, color: Color) -> void:
	var ground: Vector3 = at + Vector3.UP * GROUND_LIFT
	_add_line(ground + Vector3(-size, 0.0, 0.0), ground + Vector3(size, 0.0, 0.0), color)
	_add_line(ground + Vector3(0.0, 0.0, -size), ground + Vector3(0.0, 0.0, size), color)


## Añade un marcador de punto: un rombo en el suelo y un poste.
func _add_marker(at: Vector3, color: Color) -> void:
	var ground: Vector3 = at + Vector3.UP * GROUND_LIFT
	var size: float = 0.35
	var corners: Array[Vector3] = [ground + Vector3(size, 0.0, 0.0),
		ground + Vector3(0.0, 0.0, size), ground + Vector3(-size, 0.0, 0.0),
		ground + Vector3(0.0, 0.0, -size)]
	for i: int in corners.size():
		_add_line(corners[i], corners[(i + 1) % corners.size()], color)
	_add_line(ground, ground + Vector3.UP * POST_HEIGHT, color)


## Añade una flecha de [param from] a [param to].
func _add_arrow(from: Vector3, to: Vector3, color: Color) -> void:
	_add_line(from, to, color)
	var back: Vector3 = from - to
	back.y = 0.0
	if back.length_squared() < 0.0001:
		return
	back = back.normalized() * minf(0.35, back.length() * 0.4)
	_add_line(to, to + back.rotated(Vector3.UP, 0.5), color)
	_add_line(to, to + back.rotated(Vector3.UP, -0.5), color)


## Añade una etiqueta del frame en [param at], reutilizando las que ya existen.
func _add_label(text: String, at: Vector3, color: Color, font_size: int) -> void:
	var label: Label3D = null
	if _labels_used < _labels.size():
		label = _labels[_labels_used]
	else:
		label = CombatDebugOverlay.make_label(text, color)
		label.name = "Label%d" % _labels.size()
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		add_child(label)
		_labels.append(label)
	_labels_used += 1
	label.text = text
	label.font_size = font_size
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, color.a)
	label.position = at
	label.show()


## Devuelve [param color] con la opacidad que corresponde a [param certainty].
func _faded(color: Color, certainty: float) -> Color:
	var faded: Color = color
	faded.a = lerpf(0.2, 1.0, clampf(certainty, 0.0, 1.0))
	return faded


## Devuelve el nombre corto de una fuente.
func _source_name(source: EnemyBelief.Source) -> String:
	match source:
		EnemyBelief.Source.SIGHT:
			return "vista"
		EnemyBelief.Source.TOUCH:
			return "tacto"
		EnemyBelief.Source.HEARING:
			return "oído"
	return "pista"


## Devuelve el nombre visible de [param player].
func _player_name(player: Player) -> String:
	if player.data and not player.data.name.is_empty():
		return player.data.name
	if player.data:
		return "jugador %d" % player.data.id
	return str(player.name)


## Devuelve [code]true[/code] en el servidor o sin peer.
func _is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
