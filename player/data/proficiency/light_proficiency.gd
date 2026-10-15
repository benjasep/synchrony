class_name LightProficiency
extends ProficiencyProfile

## Manejo de fuentes de luz. El técnico lo tiene neutro (multiplicadores a 1.0, sin
## parpadeo); los demás la sostienen peor. [code]flicker_chance[/code] es una probabilidad
## por segundo. Las duraciones de los cortes se expresan en segundos.

@export var range_multiplier: float = 1.0

@export var energy_multiplier: float = 1.0

@export var flicker_chance: float = 0.0

@export_range(0.0, 5.0, 0.05) var flicker_duration_min: float = 0.05

@export_range(0.0, 5.0, 0.05) var flicker_duration_max: float = 0.15

## Titileos breves independientes de los apagones. Intervalo máximo 0 = desactivados.
@export_range(0.0, 5.0, 0.01) var rapid_flicker_interval_min: float = 0.0

@export_range(0.0, 5.0, 0.01) var rapid_flicker_interval_max: float = 0.0

@export_range(0.0, 1.0, 0.01) var rapid_flicker_duration_min: float = 0.04

@export_range(0.0, 1.0, 0.01) var rapid_flicker_duration_max: float = 0.1

@export_range(1, 3, 1) var flicker_burst_limit: int = 3

## Pausa encendida garantizada entre ráfagas, sin titileos ni apagones largos.
@export_range(0.0, 10.0, 0.1) var steady_duration_min: float = 2.0

@export_range(0.0, 10.0, 0.1) var steady_duration_max: float = 4.0

@export var drain_multiplier: float = 1.0
