class_name RetreatedCondition
extends EnemyCondition

## El enemigo está retirado, o presente si [code]retreated[/code] es [code]false[/code].

## Si se cumple mientras está retirado o mientras está presente.
@export var retreated: bool = true


## Devuelve [code]true[/code] si el enemigo está retirado o presente según [code]retreated[/code].
func is_met(brain: EnemyBrain) -> bool:
	if not brain.enemy:
		return false
	return brain.enemy.is_retreated == retreated
