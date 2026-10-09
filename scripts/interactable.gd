class_name Interactable
extends Area3D

## Cualquier cosa del mundo con la que un jugador puede interactuar. La interacción es
## autoritativa del servidor: [InteractionComponent] la pide y el servidor llama a
## [code]perform()[/code]. Las subclases que sobrescriban [code]_ready()[/code] deben llamar a
## [code]super()[/code], o pierden la capa de interacción y el rayo deja de detectarlas.

signal interacted(player: Player)

## Es una máscara: 4 = capa 3, la única que mira el rayo de [InteractionComponent].
const INTERACTION_LAYER: int = 4

@export var prompt: String = "Interactuar"
@export var enabled: bool = true
@export var is_local_only: bool = false


## Fuerza la capa de interacción y anula la máscara de colisión, sin fiarse de la escena.
func _ready() -> void:
	collision_layer = INTERACTION_LAYER
	collision_mask = 0


## Comprueba si [param player] puede interactuar ahora. Se evalúa en el cliente antes de
## pedirlo y otra vez en el servidor; las subclases añaden sus condiciones a las de
## [code]super()[/code].
## Devuelve: [code]true[/code] si está habilitado y [param player] no es [code]null[/code].
func can_interact(player: Player) -> bool:
	return enabled and player != null


## Ejecuta la interacción. Solo lo llama el servidor tras validar al emisor y
## [code]can_interact()[/code]; las subclases lo sobrescriben. La base emite
## [code]interacted[/code].
## Recibe: [param player] — quien interactúa.
func perform(player: Player) -> void:
	interacted.emit(player)
