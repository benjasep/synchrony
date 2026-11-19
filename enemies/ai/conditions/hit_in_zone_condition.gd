class_name HitInZoneCondition
extends EnemyCondition

## Recibió daño en alguna de [code]zones[/code] desde que entró al estado actual.

## Zonas de impacto que cuenta.
@export var zones: Array[Statics.HitZone] = [Statics.HitZone.PUNTO_DEBIL]


## Devuelve [code]true[/code] si recibió daño en alguna de [code]zones[/code] en este estado.
func is_met(brain: EnemyBrain) -> bool:
	if not brain.memory or not brain.current_state:
		return false
	for zone: Statics.HitZone in zones:
		if brain.memory.get_last_hit_usec(zone) > brain.current_state.entered_usec:
			return true
	return false
