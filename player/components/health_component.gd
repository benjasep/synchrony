class_name HealthComponent
extends Node

## Salud y estado de derribo. No extiende [PlayerComponent] a propósito, para poder
## reutilizarlo en enemigos. El daño solo se aplica en el servidor y se replica por RPC.

signal health_changed(current: float, maximum: float)
signal downed
signal died
signal revived

@export var max_health: float = 100.0
@export var can_be_downed: bool = true
@export var downed_health: float = 25.0

var current_health: float = 100.0
var is_downed: bool = false
var is_dead: bool = false


## Toma la vida máxima del perfil y deja la salud llena, sin derribo ni muerte; emite
## [code]health_changed[/code]. Es local: cada peer lo ejecuta al configurar el [Player].
## Recibe: [param profile] — perfil del rol; con [code]null[/code] se conserva
## [code]max_health[/code].
func configure(profile: RoleProfile) -> void:
	if profile:
		max_health = profile.max_health
	current_health = max_health
	is_downed = false
	is_dead = false
	health_changed.emit(current_health, max_health)


## Resta vida y la replica. Al llegar a 0 derriba al jugador si [code]can_be_downed[/code] y no
## lo estaba ya; si no, lo mata. Solo actúa en el servidor e ignora daños no positivos o
## a objetivos muertos.
## Recibe: [param amount] — daño a restar; [param _source] — causante del daño (aún sin usar).
func apply_damage(amount: float, _source: Node = null) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	_set_health.rpc(maxf(current_health - amount, 0.0))
	if current_health > 0.0:
		return
	if can_be_downed and not is_downed:
		_set_downed.rpc(true)
	else:
		_set_dead.rpc()


## Suma vida sin pasar de [code]max_health[/code] y la replica. Solo actúa en el servidor e
## ignora cantidades no positivas u objetivos muertos. No quita el derribo.
## Recibe: [param amount] — vida a recuperar.
func heal(amount: float) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	_set_health.rpc(minf(current_health + amount, max_health))


## Levanta a un jugador derribado con [code]downed_health[/code] de vida. Solo actúa en el
## servidor y solo si está derribado y no muerto.
func revive() -> void:
	if not multiplayer.is_server() or not is_downed or is_dead:
		return
	_set_downed.rpc(false)
	_set_health.rpc(downed_health)


## Fija la salud en todos los peers y emite [code]health_changed[/code]. Lo envía el servidor.
## Recibe: [param value] — salud nueva, ya acotada por quien llama.
@rpc("authority", "call_local", "reliable")
func _set_health(value: float) -> void:
	current_health = value
	health_changed.emit(current_health, max_health)


## Pone o quita el derribo en todos los peers y emite [code]downed[/code] o [code]revived[/code].
## Lo envía el servidor.
## Recibe: [param value] — [code]true[/code] al derribar, [code]false[/code] al reanimar.
@rpc("authority", "call_local", "reliable")
func _set_downed(value: bool) -> void:
	is_downed = value
	if is_downed:
		downed.emit()
	else:
		revived.emit()


## Marca la muerte en todos los peers, quita el derribo y emite [code]died[/code]. Lo envía el
## servidor.
@rpc("authority", "call_local", "reliable")
func _set_dead() -> void:
	is_dead = true
	is_downed = false
	died.emit()
