class_name ViewModifier
extends Resource

## Alteración de la cámara que aporta un item o un estado, como el temblor de un arma en manos
## inexpertas. Se registra por fuente en [ViewComponent], que combina todos los activos.

@export var sway_amplitude: float = 0.0
@export var sway_frequency: float = 1.0
@export var sensitivity_multiplier: float = 1.0
