class_name CardDeck
extends Equipment

## Mazo del vidente: da el pulso de eco a quien lo empuña.

const PULSE_SCENE: PackedScene = preload("res://player/abilities/seer_echo_ability.tscn")

## Metros de alcance base del estímulo del pulso.
@export var pulse_stimulus_radius: float = 40.0

var _echo_mode: VisionMode
var _pulse: SeerEchoAbility


## Devuelve el pulso de eco del mazo.
func get_ability() -> PlayerAbility:
	return _pulse


## Crea el pulso de eco del portador local y le pasa a la visión de eco.
func _on_equipped() -> void:
	if not wielder.is_local_player() or not wielder.perception:
		return
	var handling: CardDeckProficiency = proficiency as CardDeckProficiency
	if not handling or not handling.echo_vision:
		return
	if not _pulse:
		_echo_mode = handling.echo_vision.duplicate() as VisionMode
		_echo_mode.perception_radius *= handling.radius_multiplier
		_pulse = PULSE_SCENE.instantiate() as SeerEchoAbility
		_pulse.echo_mode = _echo_mode
		_pulse.pulse_radius *= handling.radius_multiplier
		_pulse.pulse_speed *= handling.radius_multiplier
		add_child(_pulse)
		_pulse.setup(wielder)
		_pulse.activated.connect(_on_pulse_activated)
	_pulse.set_equipped(true)
	wielder.perception.transition_vision_mode(_echo_mode, handling.transition_duration)


## Desactiva el pulso y devuelve al portador su visión normal.
func _on_unequipped() -> void:
	if not _pulse:
		return
	_pulse.set_equipped(false)
	var handling: CardDeckProficiency = proficiency as CardDeckProficiency
	wielder.perception.transition_vision_mode(wielder.profile.vision_mode, handling.transition_duration)


## Avisa al servidor de que se lanzó el pulso.
func _on_pulse_activated() -> void:
	_announce_pulse.rpc_id(Statics.SERVER_ID)


## Emite en el servidor el estímulo del pulso desde la posición del portador.
@rpc("any_peer", "call_local", "reliable")
func _announce_pulse() -> void:
	if not multiplayer.is_server() or not wielder:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != wielder.data.id:
		return
	StimulusBus.broadcast(Statics.StimulusKind.PULSE, Stimulus.CAUSE_PULSE,
		wielder.global_position, get_pulse_stimulus_radius(), wielder)


## Devuelve el alcance del estímulo del pulso para el portador actual.
func get_pulse_stimulus_radius() -> float:
	var handling: CardDeckProficiency = proficiency as CardDeckProficiency
	if not handling:
		return pulse_stimulus_radius
	return pulse_stimulus_radius * handling.radius_multiplier
