class_name StationaryAttack
extends Node

## Activa el combate contra el jugador atacable más cercano, sin perseguirlo ni
## desplazar al enemigo. Solo se añade a las instancias que deban atacar quietas.
## El servidor decide; MeleeAttack replica el golpe y HealthComponent replica el daño.
@export var combat: EnemyCombat
@export var player_spawner: PlayerSpawner
@export_range(0.05, 1.0, 0.05) var check_interval: float = 0.2

var _check_left: float = 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	_check_left = maxf(_check_left - delta, 0.0)
	if _check_left > 0.0:
		return
	_check_left = check_interval
	if not combat or not is_instance_valid(combat.enemy) or not is_instance_valid(player_spawner):
		return
	var enemy: Enemy = combat.enemy
	if enemy.is_retreated or not enemy.is_visible_in_tree() or combat.is_busy():
		return
	var nearest: Player = null
	var nearest_distance: float = INF
	for candidate: Player in player_spawner.players.values():
		if not combat.can_attack(candidate):
			continue
		var distance: float = enemy.global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	if nearest:
		combat.attack(nearest)
