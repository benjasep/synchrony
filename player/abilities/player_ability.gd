class_name PlayerAbility
extends Node

## Capacidad innata de un rol, instanciada desde [code]RoleProfile.ability_scene[/code]. A
## diferencia del [Equipment], no se transfiere: nadie puede heredarla recogiendo un objeto.

signal activated
signal deactivated

@export var cooldown: float = 0.0
@export var duration: float = 0.0

var player: Player
var is_active: bool = false

var _cooldown_left: float = 0.0
var _duration_left: float = 0.0


## Vincula la habilidad a su jugador, deja el procesado (tiempos e input) activo solo en el
## peer dueño y llama a [code]_on_setup()[/code].
## Recibe: [param owner_player] — el [Player] al que pertenece.
func setup(owner_player: Player) -> void:
	player = owner_player
	set_process(player.is_multiplayer_authority())
	_on_setup()


## Devuelve [code]true[/code] si tiene jugador, no está activa y el enfriamiento terminó.
func can_activate() -> bool:
	return player != null and not is_active and _cooldown_left <= 0.0


## Activa la habilidad si se puede: arranca la duración y el enfriamiento, llama a
## [code]_on_activated()[/code] y emite [code]activated[/code].
func activate() -> void:
	if not can_activate():
		return
	is_active = true
	_duration_left = duration
	_cooldown_left = cooldown
	_on_activated()
	activated.emit()


## Desactiva la habilidad si estaba activa, llama a [code]_on_deactivated()[/code] y emite
## [code]deactivated[/code]. El enfriamiento sigue corriendo desde la activación.
func deactivate() -> void:
	if not is_active:
		return
	is_active = false
	_duration_left = 0.0
	_on_deactivated()
	deactivated.emit()


## Descuenta enfriamiento y duración (con [code]duration = 0[/code] dura hasta desactivarla)
## y alterna la habilidad con la acción [code]use_ability[/code]. Solo corre en el dueño.
## Recibe: [param delta] — segundos del frame.
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


## Punto de extensión: se llama al final de [code]setup()[/code], con el jugador asignado.
func _on_setup() -> void:
	pass


## Punto de extensión: se llama al activarse, antes de emitir [code]activated[/code].
func _on_activated() -> void:
	pass


## Punto de extensión: se llama al desactivarse, antes de emitir [code]deactivated[/code].
func _on_deactivated() -> void:
	pass
