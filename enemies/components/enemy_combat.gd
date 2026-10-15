class_name EnemyCombat
extends Node

## API de ataque de un enemigo para la futura IA, que correrá en el servidor: dice si puede
## atacar a un jugador y lanza el ataque que toca. Aplica la regla del remate: si el golpe lo
## dejaría a 0 o menos (con [code]finisher_margin[/code] de margen), en vez de golpear lo agarra,
## que es lo que mata. Sin [GrabAttack] el golpe letal mata sin más; sin [MeleeAttack] siempre
## agarra. No sabe ejecutar ataques: eso lo hacen sus componentes hermanos.

@export var enemy: Enemy
@export var melee: MeleeAttack
@export var grab: GrabAttack
## Vida por encima del daño del golpe con la que aún se agarra en vez de golpear. Con 0, solo
## si el golpe lo dejaría a 0 o menos.
@export var finisher_margin: float = 0.0


## Devuelve [code]true[/code] si alguno de sus ataques está en curso.
func is_busy() -> bool:
	return (melee != null and melee.is_busy()) or (grab != null and grab.is_busy())


## Aplica la regla del remate a la vida actual de [param target].
## Devuelve: [code]true[/code] si a [param target] le toca el agarre y no el golpe;
## [code]false[/code] si el enemigo no tiene agarre o el objetivo no es válido.
func wants_grab(target: Player) -> bool:
	if not grab or not is_instance_valid(target) or not target.health:
		return false
	if not melee:
		return true
	return target.health.current_health <= melee.damage + finisher_margin


## Devuelve [code]true[/code] si [code]attack()[/code] lanzaría ahora mismo un ataque contra
## [param target]: el que dicta la regla del remate, y solo ese. Vale en cualquier peer, pero
## solo el servidor puede atacar.
func can_attack(target: Player) -> bool:
	if is_busy() or not is_instance_valid(target):
		return false
	if wants_grab(target):
		return grab.can_start(target)
	return melee != null and melee.can_start(target)


## Solo servidor: lanza contra [param target] el ataque que dicta la regla del remate. Si le
## toca el agarre y no se puede (lejos, en enfriamiento), no ataca: golpear lo mataría sin
## agarre.
## Devuelve: [code]true[/code] si empezó un ataque.
func attack(target: Player) -> bool:
	if not multiplayer.is_server() or not can_attack(target):
		return false
	if wants_grab(target):
		return grab.start(target)
	return melee.start(target)
