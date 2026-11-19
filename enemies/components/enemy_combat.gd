class_name EnemyCombat
extends Node

## API de ataque de un enemigo: dice si puede atacar a un jugador y lanza el ataque que toca.

@export var enemy: Enemy
@export var melee: MeleeAttack
@export var grab: GrabAttack
## Vida por encima del daño del golpe con la que aún agarra en vez de golpear.
@export var finisher_margin: float = 0.0


## Devuelve [code]true[/code] si alguno de sus ataques está en curso.
func is_busy() -> bool:
	return (melee != null and melee.is_busy()) or (grab != null and grab.is_busy())


## Devuelve [code]true[/code] si a [param target] le toca un agarre en vez de un golpe.
func wants_grab(target: Player) -> bool:
	if not grab or not is_instance_valid(target) or not target.health:
		return false
	if not melee:
		return true
	return target.health.current_health <= melee.damage + finisher_margin


## Devuelve [code]true[/code] si ahora puede lanzar contra [param target] el ataque que le toca.
func can_attack(target: Player) -> bool:
	if is_busy() or not is_instance_valid(target):
		return false
	if enemy and enemy.is_squeezing:
		return false
	if wants_grab(target):
		return grab.can_start(target)
	return melee != null and melee.can_start(target)


## Lanza contra [param target] el ataque que le toca; solo en el servidor.
func attack(target: Player) -> bool:
	if not multiplayer.is_server() or not can_attack(target):
		return false
	if wants_grab(target):
		return grab.start(target)
	return melee.start(target)
