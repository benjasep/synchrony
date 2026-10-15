class_name HealthComponent
extends Node

## Salud de un jugador o un enemigo: solo vivo o muerto, sin estados intermedios. No extiende
## [PlayerComponent] a propósito, para poder reutilizarlo en enemigos. Todo cambio lo decide el
## servidor y se replica por RPC.

signal health_changed(current: float, maximum: float)
## Solo se emite en el servidor, una vez por impacto que quita vida, con la zona donde entró:
## las reglas de punto débil lo escuchan a él y no a [code]health_changed[/code], que no sabe
## dónde entró el tiro.
signal damaged(amount: float, zone: Statics.HitZone, source: Node)
signal died
signal revived

@export var max_health: float = 100.0

var current_health: float = 100.0
var is_dead: bool = false


## Toma la vida máxima del perfil y deja la salud llena y viva; emite
## [code]health_changed[/code]. Es local: cada peer lo ejecuta al configurar el [Player], y
## [Enemy] en su [code]_ready()[/code].
## Recibe: [param profile] — perfil del rol; con [code]null[/code] se conserva
## [code]max_health[/code].
func configure(profile: RoleProfile) -> void:
	if profile:
		max_health = profile.max_health
	current_health = max_health
	is_dead = false
	health_changed.emit(current_health, max_health)


## Resta vida, la replica y emite [code]damaged[/code]; al llegar a 0, muere. Solo actúa en el
## servidor e ignora daños no positivos o a objetivos muertos.
## Recibe: [param amount] — daño a restar; [param source] — causante del daño (puede ser
## [code]null[/code]); [param zone] — zona donde entró el impacto.
func apply_damage(amount: float, source: Node = null, zone: Statics.HitZone = Statics.HitZone.CUERPO) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	_set_health.rpc(maxf(current_health - amount, 0.0))
	# Antes de morir, para que quien escuche la zona vea el impacto que mató.
	damaged.emit(amount, zone, source)
	if current_health <= 0.0:
		_set_dead.rpc()


## Mata en el acto, sin pasar por [code]damaged[/code]: deja la vida a 0 y replica la muerte.
## Solo actúa en el servidor y si no estaba muerto ya.
## Recibe: [param _source] — causante de la muerte (aún sin usar).
func kill(_source: Node = null) -> void:
	if not multiplayer.is_server() or is_dead:
		return
	if current_health > 0.0:
		_set_health.rpc(0.0)
	_set_dead.rpc()


## Suma vida sin pasar de [code]max_health[/code] y la replica. Solo actúa en el servidor e
## ignora cantidades no positivas u objetivos muertos: a un muerto se le devuelve con
## [code]revive()[/code].
## Recibe: [param amount] — vida a recuperar.
func heal(amount: float) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	_set_health.rpc(minf(current_health + amount, max_health))


## Devuelve a la vida a un muerto, con la vida indicada, y emite [code]revived[/code] en todos
## los peers. Solo actúa en el servidor y solo si está muerto.
## Recibe: [param health] — vida con la que vuelve, acotada a [code]max_health[/code];
## [code]<= 0[/code] = vida llena.
func revive(health: float = 0.0) -> void:
	if not multiplayer.is_server() or not is_dead:
		return
	_set_revived.rpc(max_health if health <= 0.0 else minf(health, max_health))


## Fija la salud en todos los peers y emite [code]health_changed[/code]. Lo envía el servidor.
## Recibe: [param value] — salud nueva, ya acotada por quien llama.
@rpc("authority", "call_local", "reliable")
func _set_health(value: float) -> void:
	current_health = value
	health_changed.emit(current_health, max_health)


## Marca la muerte en todos los peers y emite [code]died[/code]. Lo envía el servidor.
@rpc("authority", "call_local", "reliable")
func _set_dead() -> void:
	is_dead = true
	died.emit()


## Devuelve a la vida en todos los peers con [param value] de salud; emite
## [code]health_changed[/code] y después [code]revived[/code], para que quien reaccione vea ya la
## vida nueva. Lo envía el servidor.
## Recibe: [param value] — salud con la que vuelve, ya acotada por quien llama.
@rpc("authority", "call_local", "reliable")
func _set_revived(value: float) -> void:
	is_dead = false
	current_health = value
	health_changed.emit(current_health, max_health)
	revived.emit()
