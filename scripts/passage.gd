class_name Passage
extends Node3D

## Un hueco de paso del mapa, como una puerta o un boquete, descrito por su abertura.

const GROUP: StringName = &"passage"

## Ancho y alto libres del hueco, en metros.
@export var size: Vector2 = Vector2(1.0, 2.0)
## Metros de grosor del muro que atraviesa.
@export var depth: float = 0.3


## Se añade al grupo de los huecos.
func _ready() -> void:
	add_to_group(GROUP)


## Devuelve el eje que atraviesa el muro, en global, horizontal y normalizado.
func get_axis() -> Vector3:
	var axis: Vector3 = global_basis.z
	axis.y = 0.0
	return axis.normalized()


## Devuelve el punto global de su eje a [param along] metros del plano del hueco.
func get_axis_point(along: float) -> Vector3:
	return global_position + get_axis() * along


## Devuelve, de 0 a 1, cuánto aprieta el hueco a un punto a [param along] metros de su plano.
func get_influence(along: float, core: float, fade: float) -> float:
	var inner: float = depth * 0.5 + maxf(core, 0.0)
	return 1.0 - smoothstep(inner, inner + maxf(fade, 0.001), absf(along))
