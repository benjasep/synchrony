class_name ViewModifier
extends Resource

## Alteración de la cámara aportada por un item o estado.
##
## El temblor al apuntar de un jugador sin entrenamiento entra por aquí: el arma
## no toca la cámara directamente, registra un ViewModifier y ViewComponent lo
## agrega junto a los demás.

## Amplitud del temblor en radianes. Los modificadores activos se suman.
@export var sway_amplitude: float = 0.0
## Frecuencia del temblor en ciclos por segundo. Se toma la mayor.
@export var sway_frequency: float = 1.0
## Multiplicador de la sensibilidad del ratón.
@export var sensitivity_multiplier: float = 1.0
