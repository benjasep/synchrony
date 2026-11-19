class_name EnemySenses
extends Node

## Lo que percibe un enemigo por el oído, la vista y el tacto.

signal stimulus_perceived(stimulus: Stimulus)
signal player_spotted(player: Player)
signal player_lost(player: Player)
signal perception_updated

const SIGHT_COLLISION_MASK: int = 1

@export var enemy: Enemy

@export_group("Oído")
## Clases de estímulo que oye.
@export var perceived_kinds: Array[Statics.StimulusKind] = [Statics.StimulusKind.NOISE]

@export_group("Vista")
## Metros de alcance de la vista.
@export var sight_range: float = 12.0
## Grados de apertura total del cono de vista, en planta.
@export_range(0.0, 360.0, 1.0) var sight_fov_degrees: float = 120.0
## Metros de altura de los ojos sobre el origen del enemigo.
@export var eye_height: float = 1.4
## Eje local hacia el que mira el modelo.
@export var forward: Vector3 = Vector3.FORWARD

@export_group("Tacto")
## Metros de alcance del tacto.
@export var touch_radius: float = 1.5

@export_group("Ritmo")
## Segundos entre evaluaciones de vista y tacto.
@export_range(0.05, 1.0, 0.05) var check_interval: float = 0.2

var _visible: Array[Player] = []
var _touching: Array[Player] = []
var _perceived: Array[Player] = []
var _check_left: float = 0.0
var _bus: StimulusBus = null


## Se desconecta del canal de estímulos.
func _exit_tree() -> void:
	_bind_bus(null)


## Se conecta al canal de estímulos y evalúa vista y tacto cada [code]check_interval[/code].
func _physics_process(delta: float) -> void:
	if not enemy or not _is_server():
		return
	_bind_bus(StimulusBus.instance)
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = check_interval
	refresh()


## Evalúa ahora la vista y el tacto y emite los cambios de lo percibido.
func refresh() -> void:
	var seen: Array[Player] = []
	var touched: Array[Player] = []
	if enemy and not enemy.is_retreated:
		for player: Player in _get_living_players():
			if is_within_touch(player):
				touched.append(player)
			if check_sight(player):
				seen.append(player)
	var perceived: Array[Player] = seen.duplicate()
	for player: Player in touched:
		if not perceived.has(player):
			perceived.append(player)
	var previous: Array[Player] = _perceived
	_visible = seen
	_touching = touched
	_perceived = perceived
	for player: Player in previous:
		if not perceived.has(player) and is_instance_valid(player):
			player_lost.emit(player)
	for player: Player in perceived:
		if not previous.has(player):
			player_spotted.emit(player)
	perception_updated.emit()


## Devuelve [code]true[/code] si en la última evaluación veía a [param player].
func can_see(player: Player) -> bool:
	return player != null and _visible.has(player)


## Devuelve [code]true[/code] si en la última evaluación tocaba a [param player].
func is_touching(player: Player) -> bool:
	return player != null and _touching.has(player)


## Devuelve [code]true[/code] si en la última evaluación percibía a [param player].
func can_perceive(player: Player) -> bool:
	return player != null and _perceived.has(player)


## Devuelve los jugadores que veía en la última evaluación.
func get_visible_players() -> Array[Player]:
	return _prune(_visible)


## Devuelve los jugadores que percibía en la última evaluación.
func get_perceived_players() -> Array[Player]:
	return _prune(_perceived)


## Devuelve [code]true[/code] si [param stimulus] le llega.
func can_hear(stimulus: Stimulus) -> bool:
	if not enemy or enemy.is_retreated or not stimulus:
		return false
	return perceived_kinds.has(stimulus.kind) and stimulus.reaches(enemy.global_position)


## Devuelve la posición global de sus ojos.
func get_eye_position() -> Vector3:
	return enemy.global_position + Vector3.UP * eye_height


## Devuelve hacia dónde mira el modelo, en planta y normalizado.
func get_facing() -> Vector3:
	var facing: Vector3 = enemy.global_basis * forward
	facing.y = 0.0
	return facing.normalized()


## Devuelve [code]true[/code] si ve ahora a [param player].
func check_sight(player: Player) -> bool:
	if not enemy or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var eye: Vector3 = get_eye_position()
	var target: Vector3 = _get_sight_point(player)
	var to_target: Vector3 = target - eye
	if to_target.length() > sight_range:
		return false
	var flat: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() > 0.0001:
		var half_fov: float = deg_to_rad(sight_fov_degrees) * 0.5
		if get_facing().angle_to(flat.normalized()) > half_fov:
			return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		eye, target, SIGHT_COLLISION_MASK, [enemy.get_rid()])
	return enemy.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Devuelve [code]true[/code] si [param player] está al alcance del tacto.
func is_within_touch(player: Player) -> bool:
	if not enemy or touch_radius <= 0.0 or not is_instance_valid(player):
		return false
	return enemy.global_position.distance_to(player.global_position) <= touch_radius


## Emite [code]stimulus_perceived[/code] si el estímulo le llega.
func _on_stimulus_emitted(stimulus: Stimulus) -> void:
	if can_hear(stimulus):
		stimulus_perceived.emit(stimulus)


## Se conecta a [param bus] y se desconecta del anterior.
func _bind_bus(bus: StimulusBus) -> void:
	if bus == _bus:
		return
	if is_instance_valid(_bus) and _bus.stimulus_emitted.is_connected(_on_stimulus_emitted):
		_bus.stimulus_emitted.disconnect(_on_stimulus_emitted)
	_bus = bus
	if _bus:
		_bus.stimulus_emitted.connect(_on_stimulus_emitted)


## Devuelve el punto de [param player] al que apunta la vista.
func _get_sight_point(player: Player) -> Vector3:
	if player.head:
		return player.head.global_position
	return player.global_position + Vector3.UP * 0.5


## Devuelve los jugadores vivos.
func _get_living_players() -> Array[Player]:
	var found: Array[Player] = []
	if not PlayerSpawner.instance:
		return found
	for value: Variant in PlayerSpawner.instance.players.values():
		if not is_instance_valid(value):
			continue
		var player: Player = value as Player
		if player and player.is_inside_tree() and player.health and not player.health.is_dead:
			found.append(player)
	return found


## Devuelve una copia de [param players] sin los ya liberados.
func _prune(players: Array[Player]) -> Array[Player]:
	var alive: Array[Player] = []
	for player: Player in players:
		if is_instance_valid(player):
			alive.append(player)
	return alive


## Devuelve [code]true[/code] en el servidor o sin peer.
func _is_server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
