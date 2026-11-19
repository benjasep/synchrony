class_name AttackingCondition
extends EnemyCondition

## Tiene un ataque en curso.


## Devuelve [code]true[/code] si [EnemyCombat] tiene un ataque en curso.
func is_met(brain: EnemyBrain) -> bool:
	return brain.combat != null and brain.combat.is_busy()
