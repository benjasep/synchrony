class_name Game
extends Node

## Autoload con la lista de jugadores, fuente de verdad de la sesión; se accede siempre por
## [code]Game.instance[/code]. La UI no muta jugadores: llama a los
## [code]set_current_player_*[/code], que replican por RPC, y reacciona a las señales.

signal players_updated
signal player_updated(id: int)
signal vote_updated(id: int)

static var instance: Game

@export var multiplayer_test: bool = false
@export var use_roles: bool = true
@export var unique_roles: bool = true # won't start with repeated roles
@export var all_roles: bool = true # won't start if all roles aren't selected
@export var min_players: int = 2 # won't start if there are at least these players
@export var fill_screen: bool = true
@export var test_players: Array[PlayerDataResource] = [] # first one is server
@export var main_scene: PackedScene

var players: Array[Statics.PlayerData] = []
var change_window_scale : bool = true :
	set(value):
		var last_value: bool = change_window_scale
		change_window_scale = value
		if not change_window_scale:
			reset_window_scale()
		elif last_value != value:
			_update_window_scale()


var _is_window_small: bool = false
var _initial_window_scale_mode: Window.ContentScaleMode
var _initial_window_scale_aspect: Window.ContentScaleAspect

@onready var player_id: Label = %PlayerId

## Publica esta instancia en [code]Game.instance[/code].
func _enter_tree() -> void:
	instance = self

## Guarda el escalado inicial de la ventana, se engancha a los cambios de tamaño y de escena y
## aplica el escalado. En builds de release desactiva [code]multiplayer_test[/code] y oculta
## la etiqueta con el id de peer.
func _ready() -> void:
	_initial_window_scale_mode = get_window().content_scale_mode
	_initial_window_scale_aspect = get_window().content_scale_aspect
	
	get_window().size_changed.connect(_handle_size_changed)
	_update_window_scale()
	get_tree().node_added.connect(_handle_node_added)
	
	if not OS.is_debug_build():
		multiplayer_test = false
		player_id.hide()


## Ordena [code]players[/code] por [code]index[/code] ascendente.
func sort_players() -> void:
	players.sort_custom(func(a: Statics.PlayerData, b: Statics.PlayerData) -> bool: return a.index < b.index)


## Añade un jugador o, si ya hay uno con el mismo id de peer, actualiza sus datos. Reordena la
## lista y emite [code]players_updated[/code].
## Recibe: [param player] — datos del jugador.
func add_player(player: Statics.PlayerData) -> void:
	var existing_player: Statics.PlayerData = null
	for data: Statics.PlayerData in players:
		if data.id == player.id:
			existing_player = data
			break
	if existing_player:
		existing_player.update(player)
	else:
		players.append(player)
	sort_players()
	players_updated.emit()


## Quita de la lista al jugador con ese id de peer. En el servidor, además, renumera los
## índices de forma consecutiva y los envía a los clientes con [code]update_indices[/code].
## Emite [code]players_updated[/code].
## Recibe: [param id] — id de peer del jugador que se fue.
func remove_player(id: int) -> void:
	for i: int in players.size():
		if players[i].id == id:
			players.remove_at(i)
			break
	
	if multiplayer.is_server():
		var player_indices: Dictionary = {}
		for i: int in players.size():
			players[i].index = i
			player_indices[players[i].id] = i
		update_indices.rpc(player_indices)
	players_updated.emit()


## Busca un jugador por id de peer.
## Devuelve: sus datos, o [code]null[/code] si no está en la lista.
func get_player(id: int) -> Statics.PlayerData:
	for player: Statics.PlayerData in players:
		if player.id == id:
			return player
	return null


## Devuelve los datos del jugador de este peer, o [code]null[/code] si aún no está en la lista.
func get_current_player() -> Statics.PlayerData:
	return get_player(multiplayer.get_unique_id())


## Aplica los índices que recalculó el servidor tras una desconexión y, para el jugador local,
## actualiza también el índice de [code]Debug[/code] y el título de la ventana. Reordena y
## emite [code]players_updated[/code]. La envía el servidor desde [code]remove_player()[/code]
## y se ejecuta solo en los clientes.
## Recibe: [param player_indices] — id de peer → nuevo índice.
@rpc("reliable")
func update_indices(player_indices: Dictionary) -> void:
	for player: Statics.PlayerData in Game.instance.players:
		if player.id in player_indices:
			player.index = player_indices[player.id]
			if player.id == multiplayer.get_unique_id():
				Debug.index = player.index
				Debug.add_to_window_title("Client %d" % player.index)
	sort_players()
	players_updated.emit()


## Asigna el rol a un jugador y emite [code]player_updated[/code]. RPC que cualquier peer envía
## a todos, incluido él mismo, a través de [code]set_current_player_role()[/code].
## Recibe: [param id] — id de peer del jugador; [param role] — rol elegido.
@rpc("any_peer", "reliable", "call_local")
func set_player_role(id: int, role: Statics.Role) -> void:
	var player: Statics.PlayerData = get_player(id)
	player.role = role
	player_updated.emit(id)


## Cambia el rol del jugador local en todos los peers.
## Recibe: [param role] — rol elegido.
func set_current_player_role(role: Statics.Role) -> void:
	set_player_role.rpc(multiplayer.get_unique_id(), role)


## Marca a un jugador como listo o no (el voto hace de «listo») y emite
## [code]player_updated[/code] y [code]vote_updated[/code]; ignora ids desconocidos. RPC que
## se envía a todos los peers, incluido el emisor.
## Recibe: [param id] — id de peer del jugador; [param vote] — [code]true[/code] si está listo.
@rpc("any_peer", "reliable", "call_local")
func set_player_vote(id: int, vote: bool) -> void:
	var player: Statics.PlayerData = get_player(id)
	if not player:
		return
	player.vote = vote
	player_updated.emit(id)
	vote_updated.emit(id)


## Marca al jugador local como listo o no en todos los peers.
## Recibe: [param vote] — [code]true[/code] si está listo.
func set_current_player_vote(vote: bool) -> void:
	set_player_vote.rpc(multiplayer.get_unique_id(), vote)


## Pone a [code]false[/code] el voto de todos los jugadores en todos los peers. La llama el
## servidor cuando cambia la lista de jugadores.
func reset_votes() -> void:
	for player: Statics.PlayerData in players:
		set_player_vote.rpc(player.id, false)


## Devuelve [code]true[/code] si hay un peer de red real (no [OfflineMultiplayerPeer]) que no
## está desconectado; a diferencia de [code]Debug.is_online()[/code], cuenta también el estado
## «conectando».
func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and \
		multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## Muestra el id de peer local en la etiqueta de depuración si hay sesión conectada, o la
## oculta si no. No hace nada en builds de release.
func update_player_id() -> void:
	if not OS.is_debug_build():
		return
	if Debug.is_online():
		player_id.show()
		player_id.text = str(multiplayer.get_unique_id())
	else:
		player_id.hide()


## Restaura el modo y el aspecto de escalado que tenía la ventana al arrancar.
func reset_window_scale() -> void:
	get_window().content_scale_mode = _initial_window_scale_mode
	get_window().content_scale_aspect = _initial_window_scale_aspect


## Al cambiar el tamaño de la ventana, reaplica el escalado solo si cruza el umbral de
## 1280×720. No hace nada mientras [code]change_window_scale[/code] esté desactivado.
func _handle_size_changed() -> void:
	if not change_window_scale:
		return
	
	var was_windows_small: bool = _is_window_small
	#get_window().min_size = Vector2i(1280, 720)
	_is_window_small =  get_window().size.x < 1280 or get_window().size.y < 720

	if was_windows_small == _is_window_small:
		return
	
	_update_window_scale()


## Con la ventana por debajo de 1280×720 escala el contenido para que quepa
## ([code]CANVAS_ITEMS[/code] + [code]EXPAND[/code]); si no, desactiva el escalado y mantiene
## el aspecto.
func _update_window_scale() -> void:
	if _is_window_small:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	else:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


## Detecta los cambios de escena (un nodo añadido directamente bajo la ventana) y activa el
## escalado adaptativo solo para las pantallas de menú; el resto vuelve al escalado inicial.
## Recibe: [param node] — nodo recién añadido al árbol.
func _handle_node_added(node: Node) -> void:
	if node.get_parent() == get_window():
		# Scene has been changed
		change_window_scale = node is MainMenu or node is LobbyHostScreen or \
			node is LobbyJoinScreen or node is LobbyWaitingScreen or node is Credits
