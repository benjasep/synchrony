class_name LightProficiency
extends ProficiencyProfile

## Manejo de fuentes de luz. El técnico lo tiene neutro (multiplicadores a 1.0, sin
## parpadeo); los demás la sostienen peor. [code]flicker_chance[/code] es una probabilidad
## por segundo.

@export var range_multiplier: float = 1.0

@export var energy_multiplier: float = 1.0

@export var flicker_chance: float = 0.0

@export var drain_multiplier: float = 1.0
