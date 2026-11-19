class_name HealthBelowCondition
extends EnemyCondition

## Al enemigo le queda menos de [code]ratio[/code] de su vida máxima, sin estar muerto.

## Fracción de la vida máxima, de 0 a 1.
@export_range(0.0, 1.0, 0.05) var ratio: float = 0.5


## Devuelve [code]true[/code] si está vivo y por debajo de [code]ratio[/code] de su vida máxima.
func is_met(brain: EnemyBrain) -> bool:
	if not brain.enemy or not brain.enemy.health or ratio <= 0.0:
		return false
	var health: HealthComponent = brain.enemy.health
	if health.is_dead or health.max_health <= 0.0:
		return false
	return health.current_health / health.max_health < ratio
