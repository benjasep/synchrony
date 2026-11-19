class_name RetreatState
extends EnemyState

## Retirada: mientras el enemigo está retirado no hace nada.


## Se detiene en el acto y retira al enemigo si sigue presente.
func enter() -> void:
	locomotion.halt()
	if not enemy.is_retreated:
		enemy.retreat()
