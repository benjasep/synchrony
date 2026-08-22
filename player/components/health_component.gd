class_name HealthComponent
extends Node

## Salud y estado de derribo.
##
## A diferencia del resto, NO extiende PlayerComponent: es genérico a propósito
## para poder reutilizarlo en enemigos y objetos destructibles. Por eso no
## conoce a Player ni a RoleProfile más allá de configure().
##
## Autoridad del servidor: el daño se aplica solo en el servidor y se replica.

signal health_changed(current: float, maximum: float)
signal downed
signal died
signal revived

@export var max_health: float = 100.0
## Si es true, al llegar a 0 queda derribado (reanimable) en vez de morir.
@export var can_be_downed: bool = true
@export var downed_health: float = 25.0

var current_health: float = 100.0
var is_downed: bool = false
var is_dead: bool = false


func configure(profile: RoleProfile) -> void:
	if profile:
		max_health = profile.max_health
	current_health = max_health
	is_downed = false
	is_dead = false
	health_changed.emit(current_health, max_health)


## Solo tiene efecto en el servidor.
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


func heal(amount: float) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	_set_health.rpc(minf(current_health + amount, max_health))


## Reanima a un jugador derribado. Solo servidor.
func revive() -> void:
	if not multiplayer.is_server() or not is_downed or is_dead:
		return
	_set_downed.rpc(false)
	_set_health.rpc(downed_health)


@rpc("authority", "call_local", "reliable")
func _set_health(value: float) -> void:
	current_health = value
	health_changed.emit(current_health, max_health)


@rpc("authority", "call_local", "reliable")
func _set_downed(value: bool) -> void:
	is_downed = value
	if is_downed:
		downed.emit()
	else:
		revived.emit()


@rpc("authority", "call_local", "reliable")
func _set_dead() -> void:
	is_dead = true
	is_downed = false
	died.emit()
