class_name NoneOfCondition
extends EnemyCondition

## No se cumple ninguna de sus condiciones.

## Condiciones que niega.
@export var conditions: Array[EnemyCondition] = []


## Devuelve [code]true[/code] si no se cumple ninguna de sus condiciones.
func is_met(brain: EnemyBrain) -> bool:
	for condition: EnemyCondition in conditions:
		if condition and condition.is_met(brain):
			return false
	return true
