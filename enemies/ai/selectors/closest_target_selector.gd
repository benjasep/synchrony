class_name ClosestTargetSelector
extends TargetSelector

## Elige como presa al candidato válido más cercano al enemigo.


## Devuelve el candidato válido más cercano al enemigo, o [code]null[/code].
func choose(brain: EnemyBrain, candidates: Array[Player]) -> Player:
	if not brain.enemy:
		return null
	var origin: Vector3 = brain.enemy.global_position
	var best: Player = null
	var best_distance: float = INF
	for candidate: Player in candidates:
		if not is_valid_prey(candidate):
			continue
		var distance: float = origin.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best
