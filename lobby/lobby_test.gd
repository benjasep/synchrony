extends Node

## Arnés de multijugador local (con [code]Game.multiplayer_test[/code]): la primera instancia
## hospeda y las demás se unen a localhost, los jugadores salen de
## [code]Game.test_players[/code] y se salta directamente a [code]main_scene[/code].

var player_index: int = 1

@onready var start_game_timer: Timer = $StartGameTimer

## Crea los jugadores a partir de [code]Game.test_players[/code] (el primero es el servidor,
## id 1), escucha las conexiones e intenta hospedar; si no puede, se une. Después desactiva
## [code]multiplayer_test[/code] para que el menú principal vuelva a ser accesible.
func _ready() -> void:
	for i: int in Game.instance.test_players.size():
		var test_player: PlayerDataResource = Game.instance.test_players[i]
		var player: Statics.PlayerData = Statics.PlayerData.new(
			0,
			test_player.name,
			i,
			test_player.role
		)
		Game.instance.players.push_back(player)
	
	if Game.instance.players.size() > 0:
		Game.instance.players[0].id = 1
	
	if is_multiplayer_authority():
		multiplayer.peer_connected.connect(_on_peer_connected)
	
	if not _try_host():
		_try_join()
	
	# disable in order to be able to reach main menu again
	Game.instance.multiplayer_test = false


## Intenta crear el servidor; si lo consigue, marca la ventana como Server, la coloca en la
## primera celda y conecta el temporizador de arranque.
## Devuelve: [code]true[/code] si se creó el servidor (el puerto estaba libre).
func _try_host() -> bool:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(Statics.PORT, Statics.MAX_CLIENTS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		Debug.add_to_window_title("Server")
		Game.instance.update_player_id()
		_update_window_placement(0)
		start_game_timer.timeout.connect(_on_start_game_timeout)
	return err == OK


## Crea un cliente hacia localhost.
## Devuelve: [code]true[/code] si se creó el peer; si llega a conectar se sabe después.
func _try_join() -> bool:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client("localhost", Statics.PORT)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err == OK


## En el servidor, asigna el id del peer nuevo al siguiente jugador de prueba, reenvía todos los
## ids a los clientes y reinicia el temporizador de arranque: la partida empieza cuando dejan
## de llegar conexiones.
## Recibe: [param id] — id de peer del que se conectó.
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		Game.instance.players[player_index].id = id
		for i: int in Game.instance.players.size():
			_send_player_data_id.rpc(i, Game.instance.players[i].id)
		player_index += 1
		start_game_timer.start()


## Registra el id de peer de un jugador de prueba. Si es el propio y aún no lo tenía, marca la
## ventana como Client N y la coloca en su celda. La envía el servidor y se ejecuta solo en
## los clientes.
## Recibe: [param index] — posición del jugador en la lista; [param id] — su id de peer.
@rpc("reliable")
func _send_player_data_id(index: int, id: int) -> void:
	if multiplayer.get_unique_id() == id and not Game.instance.players[index].id:
		Debug.add_to_window_title("Client %d" % index)
		Debug.index = index
		_update_window_placement(index)
	Game.instance.players[index].id = id


## Al vencer el temporizador, el servidor arranca la partida en todos los peers.
func _on_start_game_timeout() -> void:
	_start_game.rpc()


## Cambia a [code]Game.main_scene[/code]. RPC del servidor que se ejecuta en todos los peers,
## él incluido.
@rpc("reliable", "call_local")
func _start_game() -> void:
	get_tree().change_scene_to_packed(Game.instance.main_scene)


## Si [code]Game.fill_screen[/code] está activo, reparte la pantalla en una cuadrícula casi
## cuadrada, una celda por jugador, y coloca y dimensiona la ventana en la suya descontando la
## barra de título.
## Recibe: [param index] — posición del jugador (0 = servidor).
func _update_window_placement(index: int) -> void:
	if not Game.instance.fill_screen:
		return
	var columns: int = ceil(sqrt(Game.instance.players.size()))
	var rows: int = ceil(1.0 * Game.instance.players.size() / columns)
	var x: int = index % columns
	@warning_ignore("integer_division")
	var y: int = index / columns
	
	var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect()
	@warning_ignore("integer_division")
	var window_size: Vector2i = screen_rect.size / Vector2i(columns, rows)
	var title_size: Vector2i = DisplayServer.window_get_title_size(get_window().title)
	var title_size_offset: Vector2i = Vector2i(0, title_size.y)
	
	get_window().position = Vector2i(x, y) * window_size + title_size_offset + screen_rect.position
	get_window().size = window_size - title_size_offset
