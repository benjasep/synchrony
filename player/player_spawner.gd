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

@export_group("Sincronización de carga")
## Cada cuánto reintenta un cliente avisar de que ya tiene el nivel cargado.
## Se reintenta porque si el nivel del cliente carga ANTES que el del servidor,
## el aviso viaja a una ruta que todavía no existe allí y se pierde en silencio.
@export var ready_report_interval: float = 0.25
## Red de seguridad: si alguien no avisa nunca (se cayó justo al cambiar de
## escena), el nivel arranca igual en vez de quedarse esperando para siempre.
@export var spawn_ready_timeout: float = 10.0

var players: Dictionary[int, Player] = {}

## Peers que ya tienen el nivel en el árbol. Solo lo usa el servidor.
var _peers_with_level: Dictionary[int, bool] = {}
var _has_spawned: bool = false
var _level_ready_acknowledged: bool = false

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
		_peers_with_level[Statics.SERVER_ID] = true
		# Sin clientes conectados (nivel suelto con F6) esto genera ya, dentro
		# del propio _ready(): las pruebas cuentan con que al frame siguiente
		# los jugadores ya existan.
		spawn_all_players()
		_spawn_when_timeout_expires()
	else:
		_report_level_ready_until_acknowledged()


## Solo servidor. Espera a que todos los peers tengan el nivel cargado; si el
## servidor generase antes, los paquetes de spawn llegarían a un cliente cuyo
## PlayerSpawner aún no existe y ese cliente se quedaría sin jugadores en el
## mapa ("Node not found: .../PlayersSpawner"). Cuando todos están listos, el
## MultiplayerSpawner replica cada instancia.
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


func _is_everyone_ready() -> bool:
	# multiplayer.get_peers() y no la lista del lobby: si alguien se desconecta
	# mientras se carga el nivel, desaparece de aquí y dejamos de esperarle.
	for id: int in multiplayer.get_peers():
		if not _peers_with_level.get(id, false):
			return false
	return true


## Solo cliente. Reintenta hasta que el servidor confirme, porque el aviso se
## pierde si su PlayerSpawner todavía no está en el árbol cuando llega.
func _report_level_ready_until_acknowledged() -> void:
	while is_inside_tree() and not _level_ready_acknowledged:
		_report_level_ready.rpc_id(Statics.SERVER_ID)
		await get_tree().create_timer(ready_report_interval).timeout


func _spawn_when_timeout_expires() -> void:
	if _has_spawned or spawn_ready_timeout <= 0.0:
		return
	await get_tree().create_timer(spawn_ready_timeout).timeout
	if _has_spawned or not is_inside_tree():
		return
	push_warning("PlayerSpawner: alguien no avisó de tener el nivel cargado en %.1f s; se genera igualmente." % spawn_ready_timeout)
	spawn_all_players(true)


## call_local por la regla del proyecto para todo rpc_id(SERVER_ID, …): el host
## se lo enviaría a sí mismo y sin él Godot lo rechaza. get_remote_sender_id()
## devuelve 0 en esa llamada local.
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


@rpc("authority", "reliable")
func _acknowledge_level_ready() -> void:
	_level_ready_acknowledged = true


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
