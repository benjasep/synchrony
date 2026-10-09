class_name Lobby
extends Node

## Autoload (se accede por [code]Lobby.instance[/code]) que atiende todas las señales de
## [code]multiplayer[/code], muestra el aviso de caída del servidor y hace todas las
## transiciones entre pantallas del lobby.

static var instance: Lobby

@export var return_to_lobby_on_player_disconnect : bool = true
@export var debug : bool = false

var _skip_server_disconnect_action: bool = false

@onready var player_disconnected: MarginContainer = %PlayerDisconnected
@onready var server_disconnected: MarginContainer = %ServerDisconnected
@onready var message_container: Panel = %MessageContainer


## Publica esta instancia en [code]Lobby.instance[/code].
func _enter_tree() -> void:
	instance = self


## Se conecta a las señales de conexión de [code]multiplayer[/code] y oculta los avisos.
func _ready() -> void:
	multiplayer.connected_to_server.connect(_handle_connected_to_server)
	multiplayer.connection_failed.connect(_handle_connection_failed)
	multiplayer.peer_connected.connect(_handle_peer_connected)
	multiplayer.peer_disconnected.connect(_handle_peer_disconnected)
	multiplayer.server_disconnected.connect(_handle_server_disconnected)

	message_container.hide()
	player_disconnected.hide()
	server_disconnected.hide()


## En el cliente, al conectar con el servidor: lo registra si [code]debug[/code] está activo y
## muestra el id de peer local.
func _handle_connected_to_server() -> void:
	if debug:
		Debug.log("Connected to server")
	Game.instance.update_player_id()


## Solo registra el fallo si [code]debug[/code] está activo; el aviso al usuario lo muestra
## [LobbyJoinScreen].
func _handle_connection_failed() -> void:
	if debug:
		Debug.log("Connection Failed")


## Al conectarse otro peer, le envía los datos del jugador local con [code]send_data[/code] si
## el nuevo es el servidor o si este peer ya tiene índice: así el servidor recibe al recién
## llegado y el recién llegado recibe a todos. No hace nada si el jugador local aún no está en
## la lista (caso de lobby_test).
## Recibe: [param id] — id de peer del que se conectó.
func _handle_peer_connected(id: int) -> void:
	if debug:
		Debug.log("Peer connected %d" % id)
	
	if not Game.instance.get_current_player():
		# exception for lobby test
		return
	
	# If it's server or I already have an index assigned
	if id == 1 or Game.instance.get_current_player().index != -1:
		send_data.rpc_id(id, Game.instance.get_current_player().to_dict())


## Al desconectarse un cliente, vuelve a la sala de espera (si está activado y no se está ya
## en ella) y lo quita de [code]Game[/code]. La caída del servidor la gestiona
## [code]_handle_server_disconnected()[/code].
## Recibe: [param id] — id de peer del que se desconectó.
func _handle_peer_disconnected(id: int) -> void:
	if debug:
		Debug.log("Peer disconnected %d" % id)
		
	if id == 1:
		# server disconnect will handle it
		return
	
	if return_to_lobby_on_player_disconnect and \
		get_tree().current_scene is not LobbyWaitingScreen:
		go_to_lobby()
	
	Game.instance.remove_player(id)


## Al perder el servidor: pausa el juego, muestra el aviso 2,5 s y vuelve al menú. Se salta una
## vez si [code]go_to_host()[/code] activó [code]_skip_server_disconnect_action[/code].
func _handle_server_disconnected() -> void:
	if debug:
		Debug.log("Server disconnected")
	
	if _skip_server_disconnect_action:
		_skip_server_disconnect_action = false
		return
	
	get_tree().paused = true
	message_container.show()
	server_disconnected.show()
	await get_tree().create_timer(2.5).timeout
	server_disconnected.hide()
	message_container.hide()
	go_to_menu()
	get_tree().paused = false


## Cambia a la sala de espera. Es RPC de cualquier peer y se ejecuta también en el emisor; hoy
## solo se llama en local, desde [code]_handle_peer_disconnected()[/code].
@rpc("any_peer", "call_local", "reliable")
func go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://lobby/waiting_screen.tscn")


## Vuelve al menú principal y descarta la sesión de red con [code]reset()[/code].
func go_to_menu() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	multiplayer.multiplayer_peer.close()
	reset()


## Vuelve a la pantalla de host y descarta la sesión de red. Activa
## [code]_skip_server_disconnect_action[/code] para que cerrar el propio servidor no muestre el
## aviso de desconexión.
func go_to_host() -> void:
	get_tree().change_scene_to_file("res://lobby/host_screen.tscn")
	_skip_server_disconnect_action = true
	reset()


## Vuelve a la pantalla de unirse y descarta la sesión de red con [code]reset()[/code].
func go_to_join() -> void:
	get_tree().change_scene_to_file("res://lobby/join_screen.tscn")
	reset()


## Recibe los datos de un jugador y lo añade (o actualiza) en [code]Game[/code]. Si llega al
## servidor, viene de un recién llegado: le asigna el siguiente índice y lo reenvía a todos los
## clientes, así el índice es autoritativo del servidor. Si los datos son del jugador local,
## actualiza el índice y el título de ventana de [code]Debug[/code]. No es
## [code]call_local[/code]: el servidor no se la reenvía a sí mismo.
## Recibe: [param data] — [code]PlayerData.to_dict()[/code] del jugador.
@rpc("any_peer", "reliable")
func send_data(data: Dictionary) -> void:
	if multiplayer.is_server():
		# A new player sent its data to the server, assing an index
		data.index = Game.instance.players.size()
		send_data.rpc(data)
	if debug:
		Debug.log("Player data from %s received" % data.name)
	Game.instance.add_player(Statics.PlayerData.from_dict(data))
	if data.id == multiplayer.get_unique_id():
		Debug.index = data.index
		Debug.add_to_window_title("Client %d" % data.index)


## Cierra la conexión, vuelve a [OfflineMultiplayerPeer], vacía la lista de jugadores y
## restaura el título de la ventana y la etiqueta del id de peer.
func reset() -> void:
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Game.instance.players = []
	Debug.reset_window_title()
	Game.instance.update_player_id()
