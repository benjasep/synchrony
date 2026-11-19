class_name TargetReachableCondition
extends EnemyCondition

## La locomoción llega hasta su presa, colándose solo si [code]allow_squeeze[/code].

## Si vale llegar colándose por huecos.
@export var allow_squeeze: bool = false


## Devuelve [code]true[/code] si la locomoción llega hasta su presa o hasta su rastro.
func is_met(brain: EnemyBrain) -> bool:
	if not brain.memory or not brain.locomotion or not brain.memory.has_target():
		return false
	var target: Player = brain.memory.get_target()
	var point: Vector3 = Vector3.ZERO
	if brain.senses and brain.senses.can_perceive(target):
		point = target.global_position
	elif brain.memory.has_trail():
		point = brain.memory.get_trail().position
	else:
		return false
	return brain.locomotion.can_reach(point, allow_squeeze)
