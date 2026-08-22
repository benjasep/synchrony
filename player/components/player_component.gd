class_name PlayerComponent
extends Node

## Base de los componentes que cuelgan de Player.
##
## La referencia al Player se asigna por @export en la escena, NO con
## get_parent(): así queda tipada y no dispara los warnings de
## unsafe_property_access / unsafe_method_access del proyecto.
##
## Los componentes no se buscan entre sí. Emiten señales propias y es Player
## quien las cablea, para que sigan siendo reutilizables.

@export var player: Player


## Llamado por Player.setup() una vez que el rol es conocido.
## Las subclases deben llamar a super() para heredar el gating de autoridad.
func configure(profile: RoleProfile) -> void:
	var is_owner: bool = player != null and player.is_multiplayer_authority()
	set_process(is_owner)
	set_physics_process(is_owner)
	set_process_unhandled_input(is_owner)


func is_owner() -> bool:
	return player != null and player.is_multiplayer_authority()
