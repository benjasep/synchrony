class_name HeardStimulusCondition
extends EnemyCondition

## Percibió un estímulo nuevo desde que entró al estado actual.


## Devuelve [code]true[/code] si la memoria guardó un estímulo después de entrar al estado actual.
func is_met(brain: EnemyBrain) -> bool:
	if not brain.memory or not brain.current_state:
		return false
	return brain.memory.last_stimulus_usec > brain.current_state.entered_usec
