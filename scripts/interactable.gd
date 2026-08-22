class_name Interactable
extends Area3D

## Cualquier cosa del mundo con la que un jugador puede interactuar: un item en
## el suelo, una puerta, un informe, un altar de ritual.
##
## Vive en scripts/ y no en player/ porque el jugador solo consume esta
## interfaz; quien la implemente es cosa del nivel.
##
## La interacción es autoritativa del servidor: InteractionComponent envía la
## petición y el servidor decide. Las subclases sobrescriben _perform().

signal interacted(player: Player)

## Capa 3. Es la que enmascara el RayCast3D de InteractionComponent; si un
## Interactable acaba en otra capa, deja de poder señalarse.
const INTERACTION_LAYER: int = 4

@export var prompt: String = "Interactuar"
@export var enabled: bool = true
## Si es true, solo el jugador que la pidió ve el resultado (leer una nota).
@export var is_local_only: bool = false


func _ready() -> void:
	collision_layer = INTERACTION_LAYER
	collision_mask = 0


func can_interact(player: Player) -> bool:
	return enabled and player != null


## Llamado en el servidor tras validar. Sobrescribir en las subclases.
func perform(player: Player) -> void:
	interacted.emit(player)
