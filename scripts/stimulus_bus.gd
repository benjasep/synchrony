class_name StimulusBus
extends Node

## Canal de estímulos del nivel: quien hace algo perceptible lo emite y los enemigos lo escuchan.

signal stimulus_emitted(stimulus: Stimulus)

static var instance: StimulusBus


## Se registra como [code]StimulusBus.instance[/code].
func _enter_tree() -> void:
	instance = self


## Limpia [code]StimulusBus.instance[/code] si aún apunta a este nodo.
func _exit_tree() -> void:
	if instance == self:
		instance = null


## Emite un estímulo por el canal del nivel actual, si lo hay.
static func broadcast(kind: Statics.StimulusKind, cause: StringName, position: Vector3,
		radius: float, source: Node3D = null) -> Stimulus:
	if not instance:
		return null
	return instance.emit_stimulus(kind, cause, position, radius, source)


## Crea el estímulo y lo emite por [code]stimulus_emitted[/code], solo en el servidor.
func emit_stimulus(kind: Statics.StimulusKind, cause: StringName, position: Vector3,
		radius: float, source: Node3D = null) -> Stimulus:
	if not multiplayer.multiplayer_peer or not multiplayer.is_server() or radius <= 0.0:
		return null
	var stimulus: Stimulus = Stimulus.new()
	stimulus.kind = kind
	stimulus.cause = cause
	stimulus.position = position
	stimulus.radius = radius
	stimulus.source = source
	stimulus.time_msec = Time.get_ticks_msec()
	stimulus_emitted.emit(stimulus)
	return stimulus
