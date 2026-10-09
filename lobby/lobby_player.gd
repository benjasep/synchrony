class_name LobbyPlayer
extends HBoxContainer

## Fila de la sala de espera con el nombre, el rol y el estado de listo de otro jugador; se
## refresca sola con [code]Game.player_updated[/code].

var player: Statics.PlayerData

@onready var name_label: Label = %NameLabel
@onready var role_label: Label = %RoleLabel
@onready var ready_icon: TextureRect = %ReadyIcon


## Muestra la etiqueta de rol solo si se usan roles, escucha los cambios de jugadores y pinta
## la fila.
func _ready() -> void:
	role_label.visible = Game.instance.use_roles
	Game.instance.player_updated.connect(_handle_player_updated)
	update()


## Asigna el jugador que representa la fila y la refresca si el nodo ya está listo (si no, lo
## hará [code]_ready()[/code]).
## Recibe: [param value] — datos del jugador.
func set_player(value: Statics.PlayerData) -> void:
	player = value
	if is_node_ready():
		update()


## Pinta nombre, rol e icono de listo (verde si ha votado). No hace nada sin jugador asignado.
func update() -> void:
	if not player:
		return
	name_label.text = player.name
	role_label.text = RoleDatabase.get_role_name(player.role)
	ready_icon.modulate = Color.GREEN if player.vote else Color.WHITE


## Refresca la fila si el jugador que cambió es el suyo.
## Recibe: [param id] — id de peer del jugador que cambió.
func _handle_player_updated(id: int) -> void:
	if player and player.id == id:
		update()
