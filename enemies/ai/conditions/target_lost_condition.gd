class_name TargetLostCondition
extends EnemyCondition

## Perdió a su presa: la tiene, pero hace al menos [code]seconds[/code] que no la percibe.

## Segundos sin percibir a la presa.
@export var seconds: float = 3.0


## Devuelve [code]true[/code] si tiene presa y hace [code]seconds[/code] o más que no la percibe.
func is_met(brain: EnemyBrain) -> bool:
	if not brain.memory or not brain.senses or not brain.memory.has_target():
		return false
	if brain.senses.can_perceive(brain.memory.get_target()):
		return false
	return brain.memory.get_seconds_since_seen() >= seconds
