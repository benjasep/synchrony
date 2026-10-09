class_name LocomotionAnimator
extends Node

## Pasa al [AnimationTree] de un modelo la velocidad horizontal a la que se desplaza, en m/s.
## La MIDE por cambio de posición y no lee [code]velocity[/code]: en un peer remoto vale
## siempre cero, porque el sincronizador solo replica posición y rotación.

@export var tree: AnimationTree
@export var tracked: Node3D
@export var blend_parameter: StringName = &"parameters/locomotion/blend_position"
@export var smoothing_time: float = 0.12
@export var max_plausible_speed: float = 25.0

var speed: float = 0.0

var _last_position: Vector3 = Vector3.ZERO
var _has_last_position: bool = false


## Mide la velocidad horizontal por el desplazamiento de [code]tracked[/code] desde el frame
## anterior, la suaviza y la escribe en [code]blend_parameter[/code]. Descarta las medidas por
## encima de [code]max_plausible_speed[/code] (teletransportes) y, mientras el modelo está
## oculto, apaga el árbol y olvida la última posición.
## Recibe: [param delta] — segundos del frame de física.
func _physics_process(delta: float) -> void:
	if not tree or not tracked or delta <= 0.0:
		return
	# Al dueño el cuerpo se le oculta (primera persona) pero sigue procesando:
	# no tiene sentido mezclar animaciones que nadie va a ver.
	var visible: bool = tracked.is_visible_in_tree()
	tree.active = visible
	if not visible:
		_has_last_position = false
		return

	var current: Vector3 = tracked.global_position
	if not _has_last_position:
		_last_position = current
		_has_last_position = true
		return
	var offset: Vector3 = current - _last_position
	_last_position = current
	offset.y = 0.0
	var raw_speed: float = offset.length() / delta
	if raw_speed > max_plausible_speed:
		return

	var weight: float = 1.0 - exp(-delta / maxf(smoothing_time, 0.001))
	speed = lerpf(speed, raw_speed, weight)
	if speed < 0.01:
		speed = 0.0
	tree.set(blend_parameter, speed)
