class_name FirearmProficiency
extends ProficiencyProfile

## Manejo de armas de fuego. El militar lo tiene neutro (sin temblor, multiplicadores a 1.0);
## los demás caen al default "sin entrenamiento". [code]sway_amplitude[/code] va en radianes
## y [code]sway_frequency[/code] en ciclos por segundo.

@export var sway_amplitude: float = 0.0

@export var sway_frequency: float = 1.0

@export var spread_multiplier: float = 1.0

@export var recoil_multiplier: float = 1.0

@export var reload_time_multiplier: float = 1.0
