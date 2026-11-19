class_name TimeInStateCondition
extends EnemyCondition

## Lleva en el estado actual un tiempo sorteado entre dos límites.

## Segundos mínimos en el estado.
@export var min_seconds: float = 3.0
## Segundos máximos en el estado.
@export var max_seconds: float = 6.0


## Devuelve [code]true[/code] si el estado actual ya duró su umbral sorteado.
func is_met(brain: EnemyBrain) -> bool:
	var state: EnemyState = brain.current_state
	if not state:
		return false
	return state.time_in_state >= get_threshold(state)


## Devuelve los segundos que tiene que durar [param state] en esta entrada.
func get_threshold(state: EnemyState) -> float:
	return lerpf(min_seconds, maxf(min_seconds, max_seconds), state.entry_roll)
