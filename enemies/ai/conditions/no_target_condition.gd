class_name NoTargetCondition
extends EnemyCondition

## No tiene presa válida.


## Devuelve [code]true[/code] si no tiene presa válida.
func is_met(brain: EnemyBrain) -> bool:
	return not brain.memory or not brain.memory.has_target()
