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
## Cuántos jugadores aparecen al probar el nivel en solitario. El primero eres
## tú; el resto son maniquíes inertes para ver la escena poblada y comprobar
## puntos de aparición, colisiones y siluetas. Nadie los controla: su id es
## negativo, así que ningún peer puede ser su autoridad.
@export_range(1, 8) var debug_player_count: int = 1

var players: Dictionary[int, Player] = {}

## Cuántos jugadores generó este spawner. Solo lo usa el reparto en círculo
## cuando no hay sesión de lobby de la que sacar el total.
var _roster_size: int = 0


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
	var roster: Array[Statics.PlayerData] = _get_roster()
	_roster_size = roster.size()
	for player_data: Statics.PlayerData in roster:
		players_spawner.spawn(player_data.to_dict())
	all_players_spawned.emit()


func _get_roster() -> Array[Statics.PlayerData]:
	if not Game.instance.players.is_empty():
		return Game.instance.players
	var roster: Array[Statics.PlayerData] = []
	if not spawn_local_player_without_lobby:
		return roster

	roster.append(Statics.PlayerData.new(
		multiplayer.get_unique_id(), "Local", 0, debug_role))

	# Maniquíes de relleno. Reparten los demás roles para que se vea el equipo
	# completo, y llevan id negativo: is_multiplayer_authority() nunca es cierto
	# para ellos, así que quedan quietos en vez de responder a tu teclado.
	var roles: Array[Statics.Role] = RoleDatabase.get_selectable_roles()
	roles.erase(debug_role)
	for i: int in range(1, debug_player_count):
		var role: Statics.Role = debug_role
		if not roles.is_empty():
			role = roles[(i - 1) % roles.size()]
		roster.append(Statics.PlayerData.new(-i, "Maniquí %d" % i, i, role))
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
		# global_transform y no transform: el jugador se cuelga de
		# players_container, así que un punto de aparición anidado bajo
		# cualquier nodo desplazado aterrizaría en el sitio equivocado si se
		# copiase su transform local tal cual.
		var point: Transform3D = spawn_points[index].global_transform
		if players_container and players_container.is_inside_tree():
			return players_container.global_transform.affine_inverse() * point
		return point

	# Sin puntos declarados se reparten en círculo. El total sale de la sesión;
	# al probar en solitario no hay sesión, así que vale el del último spawn.
	var count: int = maxi(maxi(Game.instance.players.size(), _roster_size), 1)
	var angle: float = TAU * (float(maxi(index, 0)) / float(count))
	var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * fallback_spawn_radius
	return Transform3D(Basis.IDENTITY, offset)
