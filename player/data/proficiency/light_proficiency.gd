class_name LightProficiency
extends ProficiencyProfile

## Manejo de fuentes de luz. El técnico la mantiene estable; los demás la
## sostienen peor y le sacan menos rendimiento a la batería.

## Multiplicador del alcance del haz.
@export var range_multiplier: float = 1.0

## Multiplicador de la intensidad del haz.
@export var energy_multiplier: float = 1.0

## Probabilidad por segundo de que la luz parpadee. 0.0 = nunca.
@export var flicker_chance: float = 0.0

## Multiplicador del consumo de batería.
@export var drain_multiplier: float = 1.0
