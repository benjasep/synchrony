class_name TargetPerceivedCondition
extends EnemyCondition

## Tiene presa y la percibe ahora mismo.


## Devuelve [code]true[/code] si tiene presa y la percibe.
func is_met(brain: EnemyBrain) -> bool:
	if not brain.memory or not brain.senses or not brain.memory.has_target():
		return false
	return brain.senses.can_perceive(brain.memory.get_target())
