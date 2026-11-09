extends Equipment

const PULSE_SCENE: PackedScene = preload("res://player/abilities/seer_echo_ability.tscn")

var _echo_mode: VisionMode
var _pulse: SeerEchoAbility


func get_ability() -> PlayerAbility:
	return _pulse


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
	_pulse.set_equipped(true)
	wielder.perception.transition_vision_mode(_echo_mode, handling.transition_duration)


func _on_unequipped() -> void:
	if not _pulse:
		return
	_pulse.set_equipped(false)
	var handling: CardDeckProficiency = proficiency as CardDeckProficiency
	wielder.perception.transition_vision_mode(wielder.profile.vision_mode, handling.transition_duration)
