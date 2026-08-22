class_name PlayerSpawner
extends Node3D

## Pega la capa de jugadores con la sesión del lobby. Es el nodo que un nivel
## instancia; no es un nivel en sí.
##
## Lee Game.instance.players (que el lobby ya dejó replicado y ordenado por
## index) y crea un Player por entrada. También posee el contenedor de items
## tirados, porque soltar y recoger es estado del mundo y necesita un spawner.
##
## Sigue el patrón `static var instance` de Game y Lobby: acceso tipado y sin
## warnings de unsafe_property_access.

signal player_spawned(player: Player)
signal all_players_spawned

static var instance: PlayerSpawner

@export var player_scene: PackedScene
@export var pickup_scene: PackedScene

@export_group("Nodos")
@export var players_container: Node3D
@export var players_spawner: MultiplayerSpawner
@export var pickups_container: Node3D
@export var pickups_spawner: MultiplayerSpawner

## Puntos de aparición. Se asignan por índice de jugador; si faltan, se reparten
## en círculo alrededor del origen del spawner.
@export var spawn_points: Array[Node3D] = []
@export var fallback_spawn_radius: float = 2.0

@export_group("Depuración")
## Permite ejecutar un nivel directamente (F6) sin pasar por el lobby: si no hay
## jugadores en la sesión, aparece uno local con debug_role.
@export var spawn_local_player_without_lobby: bool = true
@export var debug_role: Statics.Role = Statics.Role.TECHNICIAN

var players: Dictionary[int, Player] = {}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	players_spawner.spawn_function = _spawn_player
	pickups_spawner.spawn_function = _spawn_pickup
	# Al ejecutar el nivel suelto no hay peer todavía y is_server() fallaría.
	if not multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if multiplayer.is_server():
		spawn_all_players()


## Solo servidor. El MultiplayerSpawner replica cada instancia a los clientes.
func spawn_all_players() -> void:
	if not multiplayer.is_server():
		return
	for player_data: Statics.PlayerData in _get_roster():
		players_spawner.spawn(player_data.to_dict())
	all_players_spawned.emit()


func _get_roster() -> Array[Statics.PlayerData]:
	if not Game.instance.players.is_empty():
		return Game.instance.players
	var roster: Array[Statics.PlayerData] = []
	if spawn_local_player_without_lobby:
		roster.append(Statics.PlayerData.new(
			multiplayer.get_unique_id(), "Local", 0, debug_role))
	return roster


## Solo servidor. Lo llama InventoryComponent al soltar un item.
func spawn_pickup(scene_path: String, state: Dictionary, drop_transform: Transform3D) -> void:
	if not multiplayer.is_server() or scene_path.is_empty():
		return
	pickups_spawner.spawn({
		"scene_path": scene_path,
		"state": state,
		"transform": drop_transform,
	})


func get_player(peer_id: int) -> Player:
	return players.get(peer_id)


func _spawn_player(spawn_data: Variant) -> Node:
	var dict: Dictionary = spawn_data
	var player_data: Statics.PlayerData = Statics.PlayerData.from_dict(dict)

	var player: Player = player_scene.instantiate() as Player
	if not player:
		push_error("player_scene no es un Player")
		return null

	# El nombre del nodo debe coincidir en todos los peers para que los RPC
	# dirigidos a sus componentes resuelvan la misma ruta.
	player.name = str(player_data.id)
	player.transform = _get_spawn_transform(player_data.index)
	player.setup(player_data)

	players[player_data.id] = player
	player_spawned.emit(player)
	return player


func _spawn_pickup(spawn_data: Variant) -> Node:
	var dict: Dictionary = spawn_data
	var pickup: EquipmentPickup = pickup_scene.instantiate() as EquipmentPickup
	if not pickup:
		push_error("pickup_scene no es un EquipmentPickup")
		return null
	pickup.setup(dict.get("scene_path", ""), dict.get("state", {}))
	pickup.transform = dict.get("transform", Transform3D.IDENTITY)
	return pickup


func _get_spawn_transform(index: int) -> Transform3D:
	if index >= 0 and index < spawn_points.size() and spawn_points[index]:
		return spawn_points[index].transform

	var count: int = maxi(Game.instance.players.size(), 1)
	var angle: float = TAU * (float(maxi(index, 0)) / float(count))
	var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * fallback_spawn_radius
	return Transform3D(Basis.IDENTITY, offset)
