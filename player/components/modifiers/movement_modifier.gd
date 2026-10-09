class_name MovementModifier
extends Resource

## Alteración del movimiento que aporta un item, un estado o una habilidad. Se registra por
## fuente en [MovementComponent], que combina todos los activos; un debuff nuevo es un
## [code]@export[/code] más aquí, sin tocar la API de [Player] ni de los items.

@export var speed_multiplier: float = 1.0
@export var acceleration_multiplier: float = 1.0
@export var jump_multiplier: float = 1.0
@export var allows_sprint: bool = true
