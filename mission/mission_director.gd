class_name MissionDirector
extends Node

## Árbitro de la partida. Solo decide el servidor: reparte los objetos de [code]mission[/code]
## entre las [ObjectiveZone] del mapa, elige la [ExtractionZone] final y vigila la victoria y la
## derrota; los demás peers reciben por RPC la zona elegida y el resultado. Victoria: todos los
## jugadores vivos (al menos uno) dentro de la zona final y, entre sus inventarios, todos los
## objetos colocados. Derrota: todos muertos. A propósito no hay contador ni HUD de progreso:
## descubrir cuántos objetos hay puede ser parte del juego. Se accede como
## [code]MissionDirector.instance[/code], igual que [PlayerSpawner].

signal match_ended(won: bool)

const VICTORY_TEXT: String = "VICTORIA"
const DEFEAT_TEXT: String = "DERROTA"

static var instance: MissionDirector

## Qué objetos hay que encontrar; sin misión basta con llegar a la zona final.
@export var mission: MissionDefinition
## Semilla del sorteo (reparto y zona final); 0 = distinta en cada partida.
@export var rng_seed: int = 0
## Segundos entre comprobaciones de victoria y derrota.
@export var check_interval: float = 0.2
## Segundos que se ve la pantalla de fin antes de salir de la partida.
@export var end_screen_seconds: float = 6.0
## Al acabar, vuelve a la sala de espera (con lobby) o recarga el nivel (sin lobby).
@export var return_after_end: bool = true

@export_group("Nodos")
@export var end_screen: CanvasLayer
@export var end_label: Label

## Solo servidor: los objetos que se colocaron y dónde.
var placements: Array[Placement] = []
## Zona final de esta partida, en todos los peers; [code]null[/code] hasta que se elige.
var extraction_zone: ExtractionZone = null
var is_running: bool = false
var has_ended: bool = false
var won: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Solo servidor: escena de cada objeto colocado → cuántas copias hay que llevar.
var _required: Dictionary[String, int] = {}
var _check_left: float = 0.0


## Se registra como [code]MissionDirector.instance[/code].
func _enter_tree() -> void:
	instance = self


## Limpia [code]MissionDirector.instance[/code] si todavía apunta a este nodo.
func _exit_tree() -> void:
	if instance == self:
		instance = null


## Oculta la pantalla de fin y se engancha al [PlayerSpawner] para arrancar en cuanto haya
## jugadores. No depende del orden de los nodos: sin lobby el spawner genera dentro de su propio
## [code]_ready()[/code], así que si ya generó se arranca igual. Siempre en diferido, para que
## el resto del nivel termine su [code]_ready()[/code] antes del sorteo. Solo el servidor
## genera jugadores, así que en un cliente nunca arranca.
func _ready() -> void:
	set_physics_process(false)
	if end_screen:
		end_screen.hide()
	var spawner: PlayerSpawner = PlayerSpawner.instance
	if not spawner:
		push_warning("MissionDirector: no hay PlayerSpawner en el nivel; la partida no arranca.")
		return
	if spawner.has_spawned_players():
		_start.call_deferred()
	else:
		spawner.all_players_spawned.connect(_start, CONNECT_DEFERRED | CONNECT_ONE_SHOT)


## Cuenta el tiempo hasta la próxima comprobación y, al vencer, evalúa la partida. Solo corre
## en el servidor, desde que arranca hasta que termina.
## Recibe: [param delta] — segundos del frame de física.
func _physics_process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = check_interval
	_evaluate()


## Sortea dónde cae cada objeto de [code]mission[/code], sin crear nada. Expande cada objetivo
## en [code]count[/code] copias y coloca primero los más restringidos (los que tienen tags, y
## antes los de menos tags). Cada copia va a una zona válida al azar que no supere
## [code]max_per_zone[/code] y a un sitio libre al azar de esa zona. Si no cabe, relaja primero
## [code]max_per_zone[/code] y después los tags, con un aviso; si no queda ningún sitio libre,
## registra un error y la salta. Nunca bloquea la partida.
## Recibe: [param zones] — zonas candidatas, en un orden estable (el del árbol).
## Devuelve: un [MissionDirector.Placement] por objeto colocado, en orden de colocación.
func plan_placements(zones: Array[ObjectiveZone]) -> Array[Placement]:
	var result: Array[Placement] = []
	if not mission:
		return result
	var used_sites: Dictionary[Marker3D, bool] = {}
	var per_zone: Dictionary[ObjectiveZone, int] = {}
	for objective: MissionObjective in _expand_objectives():
		var placement: Placement = _place(objective, zones, used_sites, per_zone)
		if not placement:
			push_error("MissionDirector: no queda ningún sitio libre para %s; no aparecerá."
				% _describe(objective))
			continue
		used_sites[placement.site] = true
		var placed: int = per_zone.get(placement.zone, 0)
		per_zone[placement.zone] = placed + 1
		result.append(placement)
	return result


## Solo servidor, una sola vez. Sortea la partida, crea un pickup por objeto colocado a través
## de [PlayerSpawner], elige la zona final y empieza a vigilar. Solo exige lo que llegó a
## colocarse: un objeto sin sitio no puede impedir la victoria.
func _start() -> void:
	if is_running or has_ended or not multiplayer.is_server() or not PlayerSpawner.instance:
		return
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	if not mission:
		push_warning("MissionDirector: sin MissionDefinition; basta con llegar a la zona final.")

	placements = plan_placements(_find_objective_zones())
	_required.clear()
	for placement: Placement in placements:
		var scene_path: String = placement.objective.item_scene.resource_path
		PlayerSpawner.instance.spawn_pickup(scene_path, {}, placement.site.global_transform)
		var required: int = _required.get(scene_path, 0)
		_required[scene_path] = required + 1

	_choose_extraction_zone()
	is_running = true
	_check_left = check_interval
	set_physics_process(true)


## Solo servidor. Elige al azar una [ExtractionZone] del mapa y la activa en todos los peers.
## Sin ninguna avisa: la partida solo podrá acabar en derrota.
func _choose_extraction_zone() -> void:
	var zones: Array[ExtractionZone] = _find_extraction_zones()
	if zones.is_empty():
		push_warning("MissionDirector: el mapa no tiene ninguna ExtractionZone; no se puede ganar.")
		return
	var chosen: ExtractionZone = zones[_rng.randi_range(0, zones.size() - 1)]
	_activate_extraction_zone.rpc(chosen.get_path())


## Marca como zona final la de [param zone_path] y desactiva las demás. La difunde el servidor
## a todos los peers, él incluido.
## Recibe: [param zone_path] — ruta absoluta de la [ExtractionZone] elegida.
@rpc("authority", "call_local", "reliable")
func _activate_extraction_zone(zone_path: NodePath) -> void:
	extraction_zone = get_node_or_null(zone_path) as ExtractionZone
	for zone: ExtractionZone in _find_extraction_zones():
		zone.set_active(zone == extraction_zone)


## Solo servidor. Aplica las reglas: todos muertos es derrota; todos los vivos dentro de la zona
## final, llevando entre todos los objetos colocados, es victoria. Sin jugadores no decide nada.
func _evaluate() -> void:
	var players: Array[Player] = _get_players()
	if players.is_empty():
		return
	var alive: Array[Player] = []
	for player: Player in players:
		if not _is_dead(player):
			alive.append(player)
	if alive.is_empty():
		_end_match.rpc(false)
	elif _are_inside_extraction(alive) and _carry_all_objectives(alive):
		_end_match.rpc(true)


## Cierra la partida en todos los peers, él incluido; la difunde el servidor y solo cuenta la
## primera vez. Muestra VICTORIA o DERROTA, libera el ratón, congela al jugador local, emite
## [code]match_ended[/code] y, con [code]return_after_end[/code], programa la salida.
## Recibe: [param victory] — [code]true[/code] si se ganó.
@rpc("authority", "call_local", "reliable")
func _end_match(victory: bool) -> void:
	if has_ended:
		return
	has_ended = true
	is_running = false
	won = victory
	set_physics_process(false)
	if end_label:
		end_label.text = VICTORY_TEXT if victory else DEFEAT_TEXT
	if end_screen:
		end_screen.show()
	_freeze_local_player()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match_ended.emit(victory)
	if return_after_end:
		# Conectado al nodo y no con await: si el nivel se libera antes, la conexión
		# muere con él en vez de reanudar una corrutina sin instancia.
		get_tree().create_timer(end_screen_seconds).timeout.connect(_leave_match)


## Congela al jugador de este peer para la pantalla de fin: sin movimiento ni interacción, como
## hace [Player] al morir pero sin tocar su script, y sin input de items ni de mirada, para que
## un clic no dispare ni Esc vuelva a capturar el ratón.
func _freeze_local_player() -> void:
	for player: Player in _get_players():
		if not player.is_local_player():
			continue
		if player.movement:
			player.movement.set_physics_process(false)
		if player.interaction:
			player.interaction.set_physics_process(false)
		if player.inventory:
			player.inventory.set_process_unhandled_input(false)
		if player.view:
			player.view.set_process_unhandled_input(false)


## Sale de la partida terminada. Con sesión de lobby manda el servidor y lleva a todos a la sala
## de espera; sin lobby (nivel suelto con F6) recarga la escena actual.
func _leave_match() -> void:
	if not is_inside_tree():
		return
	if not Game.instance.players.is_empty():
		if multiplayer.is_server():
			Lobby.instance.go_to_lobby.rpc()
	else:
		get_tree().reload_current_scene()


## Devuelve los objetivos válidos de la misión, una entrada por copia y en orden de colocación:
## primero los de menos tags, al final los que valen en cualquier zona y, entre iguales, el
## orden de la misión. Salta con un aviso los objetivos sin escena guardada en disco.
func _expand_objectives() -> Array[MissionObjective]:
	var valid: Array[MissionObjective] = []
	var most_tags: int = 0
	for objective: MissionObjective in mission.objectives:
		if not objective or not objective.item_scene or objective.item_scene.resource_path.is_empty():
			push_warning("MissionDirector: hay un objetivo sin item_scene en disco; se ignora.")
			continue
		valid.append(objective)
		most_tags = maxi(most_tags, objective.allowed_tags.size())

	# Por cubetas y no con sort_custom, que no es estable: así entre objetivos igual de
	# restringidos manda el orden en que los puso quien diseñó la misión.
	var ordered: Array[MissionObjective] = []
	for tag_count: int in range(1, most_tags + 1):
		for objective: MissionObjective in valid:
			if objective.allowed_tags.size() == tag_count:
				_append_copies(ordered, objective)
	for objective: MissionObjective in valid:
		if objective.allowed_tags.is_empty():
			_append_copies(ordered, objective)
	return ordered


## Añade a [param list] tantas entradas de [param objective] como su [code]count[/code].
func _append_copies(list: Array[MissionObjective], objective: MissionObjective) -> void:
	for _copy: int in maxi(objective.count, 0):
		list.append(objective)


## Busca sitio para una copia relajando las restricciones por pasos: tags y límite por zona;
## solo tags; solo límite; ninguna. Avisa en cuanto tiene que saltarse alguna.
## Recibe: [param objective] — lo que hay que colocar; [param zones] — zonas candidatas;
## [param used_sites] — sitios ya ocupados; [param per_zone] — objetos ya puestos en cada zona.
## Devuelve: el [MissionDirector.Placement] sorteado, o [code]null[/code] si no queda ningún
## sitio libre.
func _place(objective: MissionObjective, zones: Array[ObjectiveZone],
		used_sites: Dictionary[Marker3D, bool], per_zone: Dictionary[ObjectiveZone, int]) -> Placement:
	for respect_tags: bool in [true, false]:
		# Sin tags, ignorarlos no cambia nada: esos dos intentos ya se hicieron.
		if not respect_tags and objective.allowed_tags.is_empty():
			break
		for respect_limit: bool in [true, false]:
			var candidates: Array[ObjectiveZone] = []
			for zone: ObjectiveZone in zones:
				if respect_tags and not objective.allowed_tags.is_empty() \
						and not objective.allowed_tags.has(zone.tag):
					continue
				var placed: int = per_zone.get(zone, 0)
				if respect_limit and mission.max_per_zone > 0 and placed >= mission.max_per_zone:
					continue
				if not _get_free_sites(zone, used_sites).is_empty():
					candidates.append(zone)
			if candidates.is_empty():
				continue
			if not respect_tags:
				push_warning("MissionDirector: %s no cabe en ninguna zona %s; va a otra."
					% [_describe(objective), objective.allowed_tags])
			elif not respect_limit:
				push_warning("MissionDirector: %s no cabe sin pasar de %d por zona; se supera."
					% [_describe(objective), mission.max_per_zone])
			var chosen_zone: ObjectiveZone = candidates[_rng.randi_range(0, candidates.size() - 1)]
			var free_sites: Array[Marker3D] = _get_free_sites(chosen_zone, used_sites)
			var site: Marker3D = free_sites[_rng.randi_range(0, free_sites.size() - 1)]
			return Placement.new(objective, chosen_zone, site)
	return null


## Devuelve los sitios de [param zone] que no están en [param used_sites].
func _get_free_sites(zone: ObjectiveZone, used_sites: Dictionary[Marker3D, bool]) -> Array[Marker3D]:
	var free_sites: Array[Marker3D] = []
	for site: Marker3D in zone.get_sites():
		if not used_sites.has(site):
			free_sites.append(site)
	return free_sites


## Devuelve el nombre de archivo de la escena de [param objective], para los avisos.
func _describe(objective: MissionObjective) -> String:
	return objective.item_scene.resource_path.get_file()


## Devuelve las [ObjectiveZone] del árbol, en el orden del árbol.
func _find_objective_zones() -> Array[ObjectiveZone]:
	var zones: Array[ObjectiveZone] = []
	for node: Node in get_tree().get_nodes_in_group(ObjectiveZone.GROUP):
		var zone: ObjectiveZone = node as ObjectiveZone
		if zone:
			zones.append(zone)
	return zones


## Devuelve las [ExtractionZone] del árbol, en el orden del árbol.
func _find_extraction_zones() -> Array[ExtractionZone]:
	var zones: Array[ExtractionZone] = []
	for node: Node in get_tree().get_nodes_in_group(ExtractionZone.GROUP):
		var zone: ExtractionZone = node as ExtractionZone
		if zone:
			zones.append(zone)
	return zones


## Devuelve los [Player] de [code]PlayerSpawner.instance.players[/code] que aún existen;
## vacío si no hay spawner.
func _get_players() -> Array[Player]:
	var players: Array[Player] = []
	if not PlayerSpawner.instance:
		return players
	for value: Variant in PlayerSpawner.instance.players.values():
		# Comprobado antes de tiparlo: asignar una instancia liberada a una variable
		# Player es un error en tiempo de ejecución.
		if is_instance_valid(value):
			var player: Player = value as Player
			if player:
				players.append(player)
	return players


## Devuelve [code]true[/code] si [param player] está muerto; sin [HealthComponent] cuenta como
## vivo.
func _is_dead(player: Player) -> bool:
	return player.health != null and player.health.is_dead


## Devuelve [code]true[/code] si hay zona final y todos los de [param alive] están dentro.
func _are_inside_extraction(alive: Array[Player]) -> bool:
	if not extraction_zone:
		return false
	for player: Player in alive:
		if not extraction_zone.contains(player):
			return false
	return true


## Cuenta, por [code]scene_file_path[/code] y con repeticiones, los items que llevan entre
## todos los de [param alive] y los compara con lo que se colocó.
## Devuelve: [code]true[/code] si llevan al menos tantas copias de cada objeto como se colocaron.
func _carry_all_objectives(alive: Array[Player]) -> bool:
	var carried: Dictionary[String, int] = {}
	for player: Player in alive:
		if not player.inventory:
			continue
		for item: Equipment in player.inventory.items:
			var copies: int = carried.get(item.scene_file_path, 0)
			carried[item.scene_file_path] = copies + 1
	for scene_path: String in _required:
		var carried_copies: int = carried.get(scene_path, 0)
		if carried_copies < _required[scene_path]:
			return false
	return true


## Un objeto ya sorteado: qué objetivo, en qué zona y en qué sitio de ella.
class Placement:
	var objective: MissionObjective
	var zone: ObjectiveZone
	var site: Marker3D

	## Recibe: [param new_objective] — el objetivo; [param new_zone] — la zona elegida;
	## [param new_site] — el sitio de esa zona.
	func _init(new_objective: MissionObjective, new_zone: ObjectiveZone, new_site: Marker3D) -> void:
		objective = new_objective
		zone = new_zone
		site = new_site
