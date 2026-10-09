class_name LobbyJoinScreen
extends Control


@onready var player_name: LineEdit = %PlayerName
@onready var ip: LineEdit = %IP
@onready var join_button: Button = %JoinButton
@onready var back_button: Button = %BackButton
@onready var error_label: Label = %ErrorLabel
@onready var error_timer: Timer = $ErrorTimer
@onready var message_container: Panel = %MessageContainer
@onready var joining_server: MarginContainer = %JoiningServer
@onready var connection_failed: MarginContainer = %ConnectionFailed
@onready var cancel_button: Button = %CancelButton


## Rellena el nombre con el usuario del sistema (más un número aleatorio al ejecutar desde el
## editor), conecta los botones y las señales de conexión y oculta los avisos.
func _ready() -> void:
	player_name.text = OS.get_environment("USERNAME") + (str(randi() % 1000) if OS.has_feature("editor")
 else "")
	join_button.pressed.connect(_join)
	error_timer.timeout.connect(func() -> void: error_label.hide())
	error_label.hide()
	back_button.pressed.connect(func() -> void: Lobby.instance.go_to_menu())
	multiplayer.connected_to_server.connect(_handle_connected_to_server)
	multiplayer.connection_failed.connect(_handle_connection_failed)
	
	message_container.hide()
	joining_server.hide()
	connection_failed.hide()
	
	cancel_button.pressed.connect(_handle_cancel_pressed)

## Crea el cliente ENet hacia la IP escrita ([code]localhost[/code] si está vacía), pausa el
## juego y muestra el aviso de conexión en curso con el botón de cancelar. El resultado llega
## por [code]connected_to_server[/code] o [code]connection_failed[/code]. Si ni siquiera puede
## crear el cliente, muestra el error unos segundos.
func _join() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip.text if ip.text else "localhost", Statics.PORT)
	if err != OK:
		error_label.show()
		error_timer.stop()
		error_timer.start()
		return
	
	multiplayer.multiplayer_peer = peer
	
	get_tree().paused = true
	message_container.show()
	joining_server.show()
	cancel_button.grab_focus()


## Al conectar, reanuda, se añade como jugador sin índice (lo asigna el servidor al recibir sus
## datos) y pasa a la sala de espera.
func _handle_connected_to_server() -> void:
	get_tree().paused = false
	Game.instance.add_player(Statics.PlayerData.new(multiplayer.get_unique_id(), player_name.text))
	get_tree().change_scene_to_file("res://lobby/waiting_screen.tscn")


## Si falla la conexión, reanuda y cambia el aviso a «conexión fallida» durante 2,5 s.
func _handle_connection_failed() -> void:
	get_tree().paused = false
	joining_server.hide()
	connection_failed.show()
	await get_tree().create_timer(2.5).timeout
	message_container.hide()
	connection_failed.hide()


## Cancela el intento de conexión: reanuda, oculta los avisos y descarta el peer con
## [code]Lobby.instance.reset()[/code].
func _handle_cancel_pressed() -> void:
	get_tree().paused = false
	joining_server.hide()
	message_container.hide()
	connection_failed.hide()
	Lobby.instance.reset()
