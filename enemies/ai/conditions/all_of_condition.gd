class_name AllOfCondition
extends EnemyCondition

## Se cumplen todas sus condiciones.

## Condiciones que combina.
@export var conditions: Array[EnemyCondition] = []


## Devuelve [code]true[/code] si ninguna de sus condiciones falla.
func is_met(brain: EnemyBrain) -> bool:
	for condition: EnemyCondition in conditions:
		if condition and not condition.is_met(brain):
			return false
	return true
