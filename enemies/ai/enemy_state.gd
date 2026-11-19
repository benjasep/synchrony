class_name EnemyState
extends Node

## Un estado del [EnemyBrain]: qué hace el enemigo mientras está en él.

var brain: EnemyBrain = null
var time_in_state: float = 0.0
var entered_usec: int = 0
var entry_roll: float = 0.0
var is_finished: bool = false

var enemy: Enemy:
	get:
		return brain.enemy if brain else null
var senses: EnemySenses:
	get:
		return brain.senses if brain else null
var memory: EnemyMemory:
	get:
		return brain.memory if brain else null
var locomotion: EnemyLocomotion:
	get:
		return brain.locomotion if brain else null
var combat: EnemyCombat:
	get:
		return brain.combat if brain else null


## Se llama al entrar en este estado.
func enter() -> void:
	pass


## Se llama al salir de este estado.
func exit() -> void:
	pass


## Avanza un frame de física del estado.
func tick(_delta: float) -> void:
	pass


## Marca el estado como terminado.
func finish() -> void:
	is_finished = true


## Reinicia el tiempo, sortea [code]entry_roll[/code] y borra la marca de terminado.
func reset_for_entry() -> void:
	time_in_state = 0.0
	entered_usec = Time.get_ticks_usec()
	entry_roll = randf()
	is_finished = false
