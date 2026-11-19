class_name TargetSelector
extends Resource

## Estrategia para elegir presa entre los jugadores que percibe el enemigo.


## Elige presa entre los candidatos; lo implementa la subclase.
func choose(_brain: EnemyBrain, _candidates: Array[Player]) -> Player:
	return null


## Devuelve [code]true[/code] si [param player] puede ser presa: está en el árbol, vivo y libre.
static func is_valid_prey(player: Player) -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and player.health != null \
		and not player.health.is_dead and not player.is_captured()
