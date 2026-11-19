class_name PlayerPerceivedCondition
extends EnemyCondition

## Percibe ahora a algún jugador que podría ser presa.


## Devuelve [code]true[/code] si alguno de los jugadores que percibe puede ser presa.
func is_met(brain: EnemyBrain) -> bool:
	if not brain.senses:
		return false
	for player: Player in brain.senses.get_perceived_players():
		if TargetSelector.is_valid_prey(player):
			return true
	return false
