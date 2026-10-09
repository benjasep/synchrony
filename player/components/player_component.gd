class_name PlayerComponent
extends Node

## Base de los componentes de [Player]. Reciben al jugador por [code]@export[/code], nunca
## con [code]get_parent()[/code] (dispararía warnings de acceso inseguro), y no se buscan
## entre sí: emiten señales y [Player] las cablea.

@export var player: Player


## Activa el procesado (process, physics y unhandled input) solo en el peer dueño del
## jugador. La llama [Player] al configurarse, con el rol ya conocido; las subclases que la
## sobrescriben deben llamar a [code]super()[/code] para conservar ese filtro de autoridad.
## Recibe: [param profile] — perfil del rol (la base no lo usa).
func configure(profile: RoleProfile) -> void:
	var is_owner: bool = player != null and player.is_multiplayer_authority()
	set_process(is_owner)
	set_physics_process(is_owner)
	set_process_unhandled_input(is_owner)


## Devuelve [code]true[/code] si este peer es la autoridad del [Player], no del componente.
func is_owner() -> bool:
	return player != null and player.is_multiplayer_authority()
