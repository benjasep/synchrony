class_name EnemyCondition
extends Resource

## Una pregunta sobre lo que el enemigo percibe, recuerda o hace, para una [EnemyTransition].


## Devuelve [code]true[/code] si la condición se cumple ahora; lo implementa la subclase.
func is_met(_brain: EnemyBrain) -> bool:
	return false
