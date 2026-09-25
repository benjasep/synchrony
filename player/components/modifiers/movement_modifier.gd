class_name MovementModifier
extends Resource

## Alteración temporal del movimiento, aportada por un item equipado, un estado
## o una habilidad.
##
## Este es el seam para debuffs que todavía no están definidos: cuando aparezca
## "con el arma prestada caminas más lento", se añade un @export aquí y se lee
## en MovementComponent, sin tocar la API de Player ni de los items.

@export var speed_multiplier: float = 1.0
@export var acceleration_multiplier: float = 1.0
@export var jump_multiplier: float = 1.0
## Si es false, bloquea el esprint mientras esté activo.
@export var allows_sprint: bool = true
