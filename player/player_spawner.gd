class_name PlayerSpawner
extends Node3D

## Une la sesión del lobby con el nivel: un nivel lo instancia (no es un nivel en sí), crea
## un [Player] por entrada de [code]Game.instance.players[/code] y replica los items
## soltados. Se accede como [code]PlayerSpawner.instance[/code], igual que [Game] y [Lobby].

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

@export var spawn_points: Array[Node3D] = []
@export var fallback_spawn_radius: float = 2.0

@export_group("Depuración")
@export var spawn_local_player_without_lobby: bool = true
@export var debug_role: Statics.Role = Statics.Role.SEER
@export_range(1, 8) var debug_player_count: int = 1

@export_group("Sincronización de carga")
@export var ready_report_interval: float = 0.25
@export var spawn_ready_timeout: float = 10.0

var players: Dictionary[int, Player] = {}

var _peers_with_level: Dictionary[int, bool] = {}
var _has_spawned: bool = false
var _level_ready_acknowledged: bool = false

var _roster_size: int = 0


## Se registra como [code]PlayerSpawner.instance[/code].
func _enter_tree() -> void:
	instance = self


## Limpia [code]PlayerSpawner.instance[/code] si todavía apunta a este nodo.
func _exit_tree() -> void:
	if instance == self:
		instance = null


## Instala las funciones de spawn de ambos [MultiplayerSpawner] y crea un
## [OfflineMultiplayerPeer] si no hay peer (nivel ejecutado suelto). El servidor se marca
## como listo, intenta generar ya y arma el temporizador de seguridad; un cliente empieza a
## avisar al servidor de que tiene el nivel cargado.
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


## Solo servidor, y una sola vez: genera un [Player] por entrada del roster a través de
## [code]players_spawner[/code] y emite [code]all_players_spawned[/code]. Espera a que todos
## los peers tengan el nivel cargado: si generase antes, el spawn llegaría a un cliente sin
## [PlayerSpawner] y ese cliente se quedaría sin jugadores.
## Recibe: [param force] — genera aunque falte algún peer por avisar (lo usa el timeout).
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


## Devuelve [code]true[/code] si todos los peers conectados han avisado de tener el nivel.
func _is_everyone_ready() -> bool:
	# multiplayer.get_peers() y no la lista del lobby: si alguien se desconecta
	# mientras se carga el nivel, desaparece de aquí y dejamos de esperarle.
	for id: int in multiplayer.get_peers():
		if not _peers_with_level.get(id, false):
			return false
	return true


## Solo cliente. Avisa al servidor de que tiene el nivel cada
## [code]ready_report_interval[/code] segundos hasta que lo confirme o este nodo salga del
## árbol: si el aviso llega antes de que exista el [PlayerSpawner] del servidor, se pierde.
func _report_level_ready_until_acknowledged() -> void:
	while is_inside_tree() and not _level_ready_acknowledged:
		_report_level_ready.rpc_id(Statics.SERVER_ID)
		await get_tree().create_timer(ready_report_interval).timeout


## Red de seguridad del servidor: si tras [code]spawn_ready_timeout[/code] segundos aún no
## se ha generado (alguien nunca avisó), lo advierte y fuerza la generación. No hace nada si
## el timeout es [code]<= 0[/code] o ya se generó.
func _spawn_when_timeout_expires() -> void:
	if _has_spawned or spawn_ready_timeout <= 0.0:
		return
	await get_tree().create_timer(spawn_ready_timeout).timeout
	if _has_spawned or not is_inside_tree():
		return
	push_warning("PlayerSpawner: alguien no avisó de tener el nivel cargado en %.1f s; se genera igualmente." % spawn_ready_timeout)
	spawn_all_players(true)


## En el servidor, marca al emisor como listo, le confirma el aviso si es un cliente e
## intenta generar. [code]call_local[/code] es obligatorio: el host se lo enviaría a sí
## mismo y sin él Godot lo rechaza; esa llamada local llega con remitente [code]0[/code],
## que se trata como el servidor.
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


## El servidor confirma a un cliente que recibió su aviso, lo que detiene sus reintentos.
@rpc("authority", "reliable")
func _acknowledge_level_ready() -> void:
	_level_ready_acknowledged = true


## Devuelve los jugadores a generar: los de la sesión del lobby o, si no hay sesión y
## [code]spawn_local_player_without_lobby[/code] está activo, uno local con
## [code]debug_role[/code] más [code]debug_player_count - 1[/code] maniquíes con id
## negativo, que ningún peer controla. Vacío si no hay sesión ni modo sin lobby.
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


## Solo servidor. Replica en todos los peers un [EquipmentPickup] con el item soltado; lo
## llama [InventoryComponent] al soltar un item.
## Recibe: [param scene_path] — escena del [Equipment] (vacía = no hace nada);
## [param state] — estado del item según su [code]get_state()[/code];
## [param drop_transform] — dónde aparece.
func spawn_pickup(scene_path: String, state: Dictionary, drop_transform: Transform3D) -> void:
	if not multiplayer.is_server() or scene_path.is_empty():
		return
	pickups_spawner.spawn({
		"scene_path": scene_path,
		"state": state,
		"transform": drop_transform,
	})


## Devuelve el [Player] del peer [param peer_id], o [code]null[/code] si no existe.
func get_player(peer_id: int) -> Player:
	return players.get(peer_id)


## Función de spawn de [code]players_spawner[/code]; se ejecuta en todos los peers. Crea el
## [Player], lo nombra con su id de peer, lo coloca y lo configura, lo registra en
## [code]players[/code] y emite [code]player_spawned[/code].
## Recibe: [param spawn_data] — el [code]PlayerData.to_dict()[/code] que envió el servidor.
## Devuelve: el [Player], o [code]null[/code] si la escena no lo es.
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


## Función de spawn de [code]pickups_spawner[/code]; se ejecuta en todos los peers. Crea el
## [EquipmentPickup] con la escena y el estado del item y lo coloca.
## Recibe: [param spawn_data] — diccionario con [code]scene_path[/code], [code]state[/code]
## y [code]transform[/code].
## Devuelve: el [EquipmentPickup], o [code]null[/code] si la escena no lo es.
func _spawn_pickup(spawn_data: Variant) -> Node:
	var dict: Dictionary = spawn_data
	var pickup: EquipmentPickup = pickup_scene.instantiate() as EquipmentPickup
	if not pickup:
		push_error("pickup_scene no es un EquipmentPickup")
		return null
	pickup.setup(dict.get("scene_path", ""), dict.get("state", {}))
	pickup.transform = dict.get("transform", Transform3D.IDENTITY)
	return pickup


## Calcula dónde aparece un jugador: su punto de [code]spawn_points[/code] o, en su defecto,
## un hueco en un círculo de radio [code]fallback_spawn_radius[/code] repartido entre todos.
## Recibe: [param index] — índice del jugador en la sesión.
## Devuelve: el transform local respecto a [code]players_container[/code] (el global del
## punto si el contenedor aún no está en el árbol).
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
