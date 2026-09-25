class_name FirearmProficiency
extends ProficiencyProfile

## Manejo de armas de fuego. El militar tiene todo neutro (0.0 de temblor,
## multiplicadores en 1.0); los demás heredan el default "sin entrenamiento".

## Amplitud del temblor de vista al apuntar, en radianes. 0.0 = pulso firme.
@export var sway_amplitude: float = 0.0

## Velocidad del temblor, en ciclos por segundo.
@export var sway_frequency: float = 1.0

## Multiplicador de la dispersión base del arma.
@export var spread_multiplier: float = 1.0

## Multiplicador del retroceso por disparo.
@export var recoil_multiplier: float = 1.0

## Multiplicador del tiempo de recarga.
@export var reload_time_multiplier: float = 1.0
