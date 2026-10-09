class_name LobbyWaitingScreen
extends Control

@onready var player_texture: TextureRect = %PlayerTexture
@onready var player_name: Label = %PlayerName
@onready var role_button: Button = %RoleButton
@onready var ready_button: Button = %ReadyButton
@onready var player_list: VBoxContainer = %PlayerList
@onready var waiting_label: Label = %WaitingLabel
@onready var back_button: Button = %BackButton
@onready var role_container: PanelContainer = %RoleContainer
@onready var role_list: VBoxContainer = %RoleList
@onready var start_timer: Timer = $StartTimer
@onready var game_start_container: PanelContainer = %GameStartContainer
@onready var game_start_counter: Label = %GameStartCounter



var LOBBY_PLAYER_SCENE: PackedScene = preload("res://lobby/lobby_player.tscn")


## Muestra el nombre propio, conecta los botones y las señales de [code]Game[/code] (en el
## servidor, también el fin de la cuenta atrás), construye la lista de jugadores y, si se usan
## roles, rellena el selector y muestra el rol actual o «Role?».
func _ready() -> void:
	player_name.text = Game.instance.get_current_player().name
	ready_button.pressed.connect(_toggle_ready)
	Game.instance.players_updated.connect(_handle_players_updated)
	Game.instance.player_updated.connect(func(_id: int) -> void: _update_ready_button())
	Game.instance.vote_updated.connect(func(_id: int) -> void: _handle_vote_updated())
	if multiplayer.is_server():
		start_timer.timeout.connect(func() -> void: _start_game.rpc())
	_handle_players_updated()
	role_button.visible = Game.instance.use_roles
	back_button.pressed.connect(_handle_back_pressed)
	role_button.pressed.connect(_handle_role_pressed)
	role_container.hide()
	game_start_container.hide()
	
	_update_ready_button()
	
	if Game.instance.use_roles:
		_fill_role_container()
		var role: Statics.Role = Game.instance.get_current_player().role
		role_button.text = RoleDatabase.get_role_name(role)
		if role == Statics.Role.NONE:
			role_button.text = "Role?"


## Actualiza la cuenta atrás con los segundos restantes, redondeados hacia arriba.
func _process(_delta: float) -> void:
	game_start_counter.text = str(int(ceil(start_timer.time_left)))


## Alterna el estado de listo del jugador local en todos los peers.
func _toggle_ready() -> void:
	Game.instance.set_current_player_vote(not Game.instance.get_current_player().vote)
	_update_player()


## Pinta el avatar propio de verde si está listo (blanco si no) y cierra el selector de rol.
func _update_player() -> void:
	var player_ready: bool = Game.instance.get_current_player().vote
	player_texture.modulate = Color.GREEN if player_ready else Color.WHITE
	role_container.hide()


## Reconstruye la lista con un [LobbyPlayer] por cada otro jugador, muestra el aviso de espera
## si se está solo y actualiza el botón de listo. En el servidor, además, quita el «listo» a
## todos: que alguien entre o salga lo anula.
func _handle_players_updated() -> void:
	for child: Node in player_list.get_children():
		child.queue_free()
	waiting_label.visible = Game.instance.players.size() == 1
	for player: Statics.PlayerData in Game.instance.players:
		if player.id != multiplayer.get_unique_id():
			var lobby_player_inst: LobbyPlayer = LOBBY_PLAYER_SCENE.instantiate()
			lobby_player_inst.set_player(player)
			player_list.add_child(lobby_player_inst)
	_update_ready_button()
	if multiplayer.is_server():
		Game.instance.reset_votes()


## Sale de la sala y cierra la sesión: el servidor vuelve a la pantalla de host y un cliente a
## la de unirse.
func _handle_back_pressed() -> void:
	if multiplayer.is_server():
		Lobby.instance.go_to_host()
	else:
		Lobby.instance.go_to_join()


## Abre o cierra el selector de rol.
func _handle_role_pressed() -> void:
	role_container.visible = not role_container.visible


## Crea un botón por cada rol seleccionable de [RoleDatabase].
func _fill_role_container() -> void:
	# Los roles salen de RoleDatabase, no del orden del enum: añadir un rol es
	# registrar un .tres, sin tocar esta UI.
	for role: Statics.Role in RoleDatabase.get_selectable_roles():
		var button: Button = Button.new()
		button.text = RoleDatabase.get_role_name(role)
		button.pressed.connect(func() -> void: _update_role(role))
		role_list.add_child(button)


## Cambia el rol del jugador local en todos los peers, lo muestra en el botón y cierra el
## selector.
## Recibe: [param role] — rol elegido.
func _update_role(role: Statics.Role) -> void:
	Game.instance.set_current_player_role(role)
	role_button.text = RoleDatabase.get_role_name(role)
	role_container.hide()


## Responde a [code]Game.vote_updated[/code]: refresca el estado propio y, en el servidor,
## lanza la cuenta atrás en todos los peers si todos están listos y se cumplen las condiciones
## de inicio, o la cancela si estaba en marcha.
func _handle_vote_updated() -> void:
	_update_player()
	if multiplayer and multiplayer.is_server():
		var all_voted: bool = true
		for player: Statics.PlayerData in Game.instance.players:
			all_voted = all_voted and player.vote
		if all_voted and _can_start_game():
			_start_timer.rpc()
		elif not start_timer.is_stopped():
			_stop_timer.rpc()

## Arranca la cuenta atrás, la muestra y bloquea el cambio de rol. RPC del servidor que se
## ejecuta en todos los peers.
@rpc("reliable", "call_local")
func _start_timer() -> void:
	start_timer.start()
	game_start_container.show()
	role_button.disabled = true


## Cancela la cuenta atrás, la oculta y vuelve a permitir el cambio de rol. RPC del servidor
## que se ejecuta en todos los peers.
@rpc("reliable", "call_local")
func _stop_timer() -> void:
	start_timer.stop()
	game_start_container.hide()
	role_button.disabled = false
	


## Al acabar la cuenta atrás, quita el «listo» propio y cambia a [code]Game.main_scene[/code].
## RPC del servidor que se ejecuta en todos los peers.
@rpc("reliable", "call_local")
func _start_game() -> void:
	Game.instance.set_current_player_vote(false)
	get_tree().change_scene_to_packed(Game.instance.main_scene)


## Comprueba las condiciones de inicio de [code]Game[/code]: mínimo de jugadores y, si se usan
## roles, que todos tengan uno, que estén todos cubiertos ([code]all_roles[/code]) y que no se
## repitan ([code]unique_roles[/code]).
## Devuelve: [code]true[/code] si la partida puede empezar.
func _can_start_game() -> bool:
	var quantity: bool = Game.instance.players.size() >= Game.instance.min_players
	var completion: bool = not Game.instance.use_roles or not Game.instance.all_roles or _are_all_roles_selected()
	var uniqueness: bool = not Game.instance.use_roles or not Game.instance.unique_roles or _are_all_roles_unique()
	var fullness: bool = not Game.instance.use_roles or _all_players_selected_role()
	return quantity and completion and uniqueness and fullness


## Deshabilita el botón de listo mientras no se cumplan las condiciones de inicio.
func _update_ready_button() -> void:
	ready_button.disabled = not _can_start_game()


## Devuelve [code]true[/code] si cada rol seleccionable lo tiene al menos un jugador.
func _are_all_roles_selected() -> bool:
	var roles: Array[Statics.Role] = RoleDatabase.get_selectable_roles()
	for player: Statics.PlayerData in Game.instance.players:
		roles.erase(player.role)
	return roles.is_empty()


## Devuelve [code]true[/code] si ningún rol se repite; también da [code]false[/code] si algún
## jugador tiene un rol no seleccionable, como [code]NONE[/code].
func _are_all_roles_unique() -> bool:
	var roles: Array[Statics.Role] = RoleDatabase.get_selectable_roles()
	for player: Statics.PlayerData in Game.instance.players:
		if roles.has(player.role):
			roles.erase(player.role)
		else:
			return false
	return true

## Devuelve [code]true[/code] si ningún jugador tiene el rol [code]NONE[/code].
func _all_players_selected_role() -> bool:
	for player: Statics.PlayerData in Game.instance.players:
		if player.role == Statics.Role.NONE:
			return false
	return true
