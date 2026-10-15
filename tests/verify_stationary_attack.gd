extends Node3D

const AttackDriver = preload("res://enemies/components/stationary_attack.gd")

## Verifica alcance, enfriamiento, muerte y posición fija con el combate real.
## Godot --headless --path . res://tests/verify_stationary_attack.tscn
var failures: int = 0
var deaths: int = 0


func _ready() -> void:
	_watchdog()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var greybox: Node3D = (load("res://levels/greybox_level.tscn") as PackedScene).instantiate() as Node3D
	var ghost: Enemy = greybox.get_node("Enemies/Ghost") as Enemy
	var nightmare: Enemy = greybox.get_node("Enemies/Pesadilla") as Enemy
	var scene_driver: AttackDriver = nightmare.get_node("StationaryAttack") as AttackDriver
	_check("solo la pesadilla tiene ataque automatico", not ghost.has_node("StationaryAttack"))
	_check("Greybox conecta la pesadilla al combate y al spawner", scene_driver.combat == nightmare.get_node("Combat") \
		and scene_driver.player_spawner == greybox.get_node("PlayerSpawner"))
	_check("sin agarre que desplace al enemigo en esta prueba", scene_driver.combat.grab == null)
	greybox.free()
	var spawner: PlayerSpawner = (load("res://player/player_spawner.tscn") as PackedScene).instantiate() as PlayerSpawner
	spawner.debug_role = Statics.Role.SEER
	add_child(spawner)
	await get_tree().process_frame
	var player: Player = spawner.players.values()[0] as Player
	# Mantiene al jugador quieto sin suelo: la prueba no simula locomoción.
	player.movement.set_physics_process(false)
	player.global_position = Vector3(0, 0, -8)
	player.health.died.connect(func() -> void: deaths += 1)
	var enemy: Enemy = (load("res://enemies/pesadilla/pesadilla.tscn") as PackedScene).instantiate() as Enemy
	add_child(enemy)
	var combat: EnemyCombat = enemy.get_node("Combat") as EnemyCombat
	# Misma configuración local de Greybox: golpes, sin el remate que alinea y mueve.
	combat.grab = null
	var driver: AttackDriver = AttackDriver.new()
	driver.combat = combat
	driver.player_spawner = spawner
	enemy.add_child(driver)
	var origin: Vector3 = enemy.global_position
	var initial_health: float = player.health.current_health
	await get_tree().create_timer(0.8).timeout
	_check("fuera del alcance no recibe dano", is_equal_approx(player.health.current_health, initial_health))
	player.global_position = Vector3(0, 0, -1.5)
	await get_tree().create_timer(0.8).timeout
	_check("dentro del alcance recibe un golpe", is_equal_approx(player.health.current_health, initial_health - combat.melee.damage))
	await get_tree().create_timer(0.5).timeout
	_check("respeta el enfriamiento", is_equal_approx(player.health.current_health, initial_health - combat.melee.damage))
	# Espera la muerte real por golpes sucesivos; no fuerza la salud ni la señal.
	for frame: int in 600:
		if player.health.is_dead:
			break
		await get_tree().physics_frame
	_check("los ataques llevan al estado de muerte", player.health.is_dead and is_zero_approx(player.health.current_health))
	_check("la muerte se emite una sola vez", deaths == 1)
	_check("el muerto pierde los controles", not player.movement.is_physics_processing() \
		and not player.interaction.is_physics_processing() and not player.inventory.is_processing_unhandled_input())
	_check("el enemigo no se desplaza", enemy.global_position.is_equal_approx(origin))
	await get_tree().create_timer(0.3).timeout
	_check("no vuelve a atacar al muerto", not combat.is_busy() and deaths == 1)
	print(">>> Ataque sin movimiento: %d fallos" % failures)
	get_tree().quit(failures)


func _check(label: String, condition: bool) -> void:
	print("  %s %s" % ["ok" if condition else "FALLO", label])
	if not condition:
		failures += 1


func _watchdog() -> void:
	await get_tree().create_timer(20.0).timeout
	push_error("La prueba de ataque sin movimiento no termino.")
	get_tree().quit(1)
