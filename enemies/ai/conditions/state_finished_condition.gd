class_name StateFinishedCondition
extends EnemyCondition

## El estado actual se declaró terminado.


## Devuelve [code]true[/code] si el estado actual llamó a [code]finish()[/code].
func is_met(brain: EnemyBrain) -> bool:
	return brain.current_state != null and brain.current_state.is_finished
