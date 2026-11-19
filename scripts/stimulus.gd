class_name Stimulus
extends RefCounted

## Algo perceptible que acaba de pasar en el mundo: un disparo, una carrera, el pulso del vidente.

const CAUSE_SHOT: StringName = &"disparo"
const CAUSE_SPRINT: StringName = &"carrera"
const CAUSE_PULSE: StringName = &"pulso"

var kind: Statics.StimulusKind = Statics.StimulusKind.NOISE
var cause: StringName = &""
var position: Vector3 = Vector3.ZERO
var radius: float = 0.0
var source: Node3D = null
var time_msec: int = 0


## Devuelve [code]true[/code] si [param point] queda dentro del alcance del estímulo.
func reaches(point: Vector3) -> bool:
	return position.distance_squared_to(point) <= radius * radius
