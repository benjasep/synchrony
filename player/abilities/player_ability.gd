class_name PlayerAbility
extends Node

## Capacidad innata de un rol.
##
## Frontera de diseño deliberada: el EQUIPAMIENTO se transfiere, las HABILIDADES
## no. La visión de eco del vidente es una habilidad porque nadie debe poder
## heredarla recogiendo un objeto; la linterna es equipamiento porque sí.
##
## Se instancia desde RoleProfile.ability_scene, así que añadir un rol con una
## habilidad nueva no toca ni Player ni los componentes.

signal activated
signal deactivated

@export var cooldown: float = 0.0
@export var duration: float = 0.0

var player: Player
var is_active: bool = false

var _cooldown_left: float = 0.0
var _duration_left: float = 0.0


func setup(owner_player: Player) -> void:
	player = owner_player
	set_process(player.is_multiplayer_authority())
	_on_setup()


func can_activate() -> bool:
	return player != null and not is_active and _cooldown_left <= 0.0


func activate() -> void:
	if not can_activate():
		return
	is_active = true
	_duration_left = duration
	_cooldown_left = cooldown
	_on_activated()
	activated.emit()


func deactivate() -> void:
	if not is_active:
		return
	is_active = false
	_duration_left = 0.0
	_on_deactivated()
	deactivated.emit()


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if is_active and duration > 0.0:
		_duration_left -= delta
		if _duration_left <= 0.0:
			deactivate()
	if Input.is_action_just_pressed(&"use_ability"):
		if is_active:
			deactivate()
		else:
			activate()


## Puntos de extensión para las subclases.
func _on_setup() -> void:
	pass


func _on_activated() -> void:
	pass


func _on_deactivated() -> void:
	pass
