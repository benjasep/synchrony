class_name PlayerSpawner
extends Node3D

## Une la sesión del lobby con el nivel: crea un [Player] por jugador y replica los items soltados.

signal player_spawned(player: Player)
signal all_players_spawned

static var instance: PlayerSpawner

## Escena del jugador.
@export var player_scene: PackedScene
## Escena de los items soltados.
@export var pickup_scene: PackedScene

@export_group("Nodos")
@export var players_container: Node3D
@export var players_spawner: MultiplayerSpawner
@export var pickups_container: Node3D
@export var pickups_spawner: MultiplayerSpawner

@export var spawn_points: Array[Node3D] = []
## Metros de radio del círculo de aparición cuando faltan puntos de aparición.
@export var fallback_spawn_radius: float = 2.0

@export_group("Depuración")
## Si genera un jugador local cuando no hay sesión del lobby.
@export var spawn_local_player_without_lobby: bool = true
## Rol del jugador local sin lobby.
@export var debug_role: Statics.Role = Statics.Role.SOLDIER
## Jugadores sin lobby, contando el local; el resto son maniquíes.
@export_range(1, 8) var debug_player_count: int = 1

@export_group("Sincronización de carga")
## Segundos entre los avisos de nivel cargado de un cliente.
@export var ready_report_interval: float = 0.25
## Segundos tras los que el servidor genera a los jugadores aunque falte algún aviso.
@export var spawn_ready_timeout: float = 10.0

var players: Dictionary[int, Player] = {}

var _peers_with_level: Dictionary[int, bool] = {}
var _has_spawned: bool = false
var _level_ready_acknowledged: bool = false

var _roster_size: int = 0


## Se registra como [code]PlayerSpawner.instance[/code].
func _enter_tree() -> void:
	instance = self


## Limpia [code]PlayerSpawner.instance[/code] si aún apunta a este nodo.
func _exit_tree() -> void:
	if instance == self:
		instance = null


## Instala las funciones de spawn y arranca la sincronización de carga del nivel.
func _ready() -> void:
	players_spawner.spawn_function = _spawn_player
	pickups_spawner.spawn_function = _spawn_pickup
	if not multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if multiplayer.is_server():
		_peers_with_level[Statics.SERVER_ID] = true
		spawn_all_players()
		_spawn_when_timeout_expires()
	else:
		_report_level_ready_until_acknowledged()


## Genera un [Player] por entrada del roster, una sola vez y solo en el servidor.
func spawn_all_players(force: bool = false) -> void:
	if not multiplayer.is_server() or _has_spawned:
		return
	if not force and not _is_everyone_ready():
		return
	_has_spawned = true
	var roster: Array[Statics.PlayerData] = _get_roster()
	_roster_size = roster.size()
	for player_data: Statics.PlayerData in roster:
		players_spawner.spawn(player_data.to_dict())
	all_players_spawned.emit()


## Devuelve [code]true[/code] si ya generó a los jugadores.
func has_spawned_players() -> bool:
	return _has_spawned


## Devuelve [code]true[/code] si [param peer_id] ya avisó de tener el nivel cargado.
func has_peer_loaded_level(peer_id: int) -> bool:
	return _peers_with_level.get(peer_id, false)


## Devuelve [code]true[/code] si todos los peers conectados tienen el nivel cargado.
func _is_everyone_ready() -> bool:
	for id: int in multiplayer.get_peers():
		if not _peers_with_level.get(id, false):
			return false
	return true


## Avisa al servidor de tener el nivel cargado hasta que lo confirme.
func _report_level_ready_until_acknowledged() -> void:
	while is_inside_tree() and not _level_ready_acknowledged:
		_report_level_ready.rpc_id(Statics.SERVER_ID)
		await get_tree().create_timer(ready_report_interval).timeout


## Fuerza la generación si pasado [code]spawn_ready_timeout[/code] aún no se hizo.
func _spawn_when_timeout_expires() -> void:
	if _has_spawned or spawn_ready_timeout <= 0.0:
		return
	await get_tree().create_timer(spawn_ready_timeout).timeout
	if _has_spawned or not is_inside_tree():
		return
	push_warning("PlayerSpawner: alguien no avisó de tener el nivel cargado en %.1f s; se genera igualmente." % spawn_ready_timeout)
	spawn_all_players(true)


## Marca en el servidor al emisor como listo, se lo confirma e intenta generar.
@rpc("any_peer", "call_local", "reliable")
func _report_level_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = Statics.SERVER_ID
	_peers_with_level[sender_id] = true
	if sender_id != Statics.SERVER_ID:
		_acknowledge_level_ready.rpc_id(sender_id)
	spawn_all_players()


## Confirma al cliente que el servidor recibió su aviso.
@rpc("authority", "reliable")
func _acknowledge_level_ready() -> void:
	_level_ready_acknowledged = true


## Devuelve los jugadores a generar: los de la sesión o, sin ella, los de depuración.
func _get_roster() -> Array[Statics.PlayerData]:
	if not Game.instance.players.is_empty():
		return Game.instance.players
	var roster: Array[Statics.PlayerData] = []
	if not spawn_local_player_without_lobby:
		return roster

	roster.append(Statics.PlayerData.new(
		multiplayer.get_unique_id(), "Local", 0, debug_role))

	var roles: Array[Statics.Role] = RoleDatabase.get_selectable_roles()
	roles.erase(debug_role)
	for i: int in range(1, debug_player_count):
		var role: Statics.Role = debug_role
		if not roles.is_empty():
			role = roles[(i - 1) % roles.size()]
		roster.append(Statics.PlayerData.new(-i, "Maniquí %d" % i, i, role))
	return roster


## Genera en todos los peers un item soltado; solo en el servidor.
func spawn_pickup(scene_path: String, state: Dictionary, drop_transform: Transform3D) -> void:
	if not multiplayer.is_server() or scene_path.is_empty():
		return
	pickups_spawner.spawn({
		"scene_path": scene_path,
		"state": state,
		"transform": drop_transform,
	})


## Devuelve el [Player] de [param peer_id], o [code]null[/code].
func get_player(peer_id: int) -> Player:
	return players.get(peer_id)


## Crea y configura un [Player] a partir de [param spawn_data].
func _spawn_player(spawn_data: Variant) -> Node:
	var dict: Dictionary = spawn_data
	var player_data: Statics.PlayerData = Statics.PlayerData.from_dict(dict)

	var player: Player = player_scene.instantiate() as Player
	if not player:
		push_error("player_scene no es un Player")
		return null

	player.name = str(player_data.id)
	player.transform = _get_spawn_transform(player_data.index)
	player.setup(player_data)

	players[player_data.id] = player
	player_spawned.emit(player)
	return player


## Crea un [EquipmentPickup] a partir de [param spawn_data].
func _spawn_pickup(spawn_data: Variant) -> Node:
	var dict: Dictionary = spawn_data
	var pickup: EquipmentPickup = pickup_scene.instantiate() as EquipmentPickup
	if not pickup:
		push_error("pickup_scene no es un EquipmentPickup")
		return null
	pickup.setup(dict.get("scene_path", ""), dict.get("state", {}))
	pickup.transform = dict.get("transform", Transform3D.IDENTITY)
	return pickup


## Devuelve dónde aparece el jugador de índice [param index].
func _get_spawn_transform(index: int) -> Transform3D:
	if index >= 0 and index < spawn_points.size() and spawn_points[index]:
		var point: Transform3D = spawn_points[index].global_transform
		if players_container and players_container.is_inside_tree():
			return players_container.global_transform.affine_inverse() * point
		return point

	var count: int = maxi(maxi(Game.instance.players.size(), _roster_size), 1)
	var angle: float = TAU * (float(maxi(index, 0)) / float(count))
	var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * fallback_spawn_radius
	return Transform3D(Basis.IDENTITY, offset)
