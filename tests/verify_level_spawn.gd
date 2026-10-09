extends Node

## Prueba de extremo a extremo: carga un nivel, aparece, cae, anda, suelta, recoge y dispara
## siendo el host. Se corre con:
## [code]"$GODOT" --headless --path . res://tests/verify_level_spawn.tscn[/code]

var failures: int = 0
var completed: bool = false


## Carga [code]test_level.tscn[/code] fijando el rol de depuración en militar antes de que
## entre al árbol (el spawner genera ya en su [code]_ready()[/code]) y recorre la batería:
## configuración sin lobby, gravedad, movimiento simulado, soltar y recoger, y disparar.
func _ready() -> void:
	_start_watchdog()
	var level: Node3D = load("res://tests/test_level.tscn").instantiate() as Node3D
	# El rol lo declara la PRUEBA, no el nivel. Esta batería ejercita soltar,
	# recoger y disparar, así que necesita un rol CON equipo; dejarlo al
	# debug_role del nivel hizo que cambiar el default del export tumbara cuatro
	# comprobaciones sin tocar una línea de código. Se asigna antes de entrar al
	# árbol porque PlayerSpawner._ready() genera ya, dentro de sí mismo.
	var level_spawner: PlayerSpawner = level.get_node("PlayerSpawner") as PlayerSpawner
	level_spawner.debug_role = Statics.Role.SOLDIER
	# add_child() directo desde _ready() falla: el padre está ocupado.
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame

	_check("el nivel entra al árbol", level.is_inside_tree())
	_check("PlayerSpawner.instance se registra", PlayerSpawner.instance != null)

	var spawner: PlayerSpawner = PlayerSpawner.instance
	# Contra lo que el nivel pide, no contra un 1 fijo: el nivel de pruebas puede
	# generar maniquíes de relleno, y el invariante es que salgan tantos como
	# debug_player_count, ni uno más.
	_check("aparecen los %d jugadores configurados" % spawner.debug_player_count,
		spawner.players_container.get_child_count() == spawner.debug_player_count)

	# El índice 0 es siempre el jugador local; el resto son maniquíes inertes.
	var player: Player = spawner.players_container.get_child(0) as Player
	_check("el hijo es un Player", player != null)
	if not player:
		_finish()
		return

	print("--- Configuración sin lobby ---")
	_check("tiene RoleProfile", player.profile != null)
	_check("el rol es el de depuración", player.data.role == spawner.debug_role)
	_check("es el jugador local", player.is_local_player())
	_check("su cámara está activa", player.camera.current)
	_check("no se ve su propio cuerpo", not player.body.visible)
	_check("el movimiento está procesando", player.movement.is_physics_processing())
	_check("aparece con su equipo", player.inventory.items.size() == 1)

	print("--- Gravedad y colisión ---")
	var start_y: float = player.global_position.y
	player.global_position = Vector3(0.0, 5.0, 0.0)
	for i: int in 90:
		await get_tree().physics_frame
	_check("cayó desde 5m", player.global_position.y < 5.0)
	_check("se apoyó en el suelo", player.is_on_floor())
	_check("no atravesó el suelo", player.global_position.y > -0.5)
	print("  (y inicial %.2f, y final %.2f)" % [start_y, player.global_position.y])

	print("--- Movimiento por input simulado ---")
	var before: Vector3 = player.global_position
	player.movement.set_physics_process(false)
	player.movement.input_direction = Vector2(0.0, -1.0)
	for i: int in 60:
		player.movement.apply_motion(get_physics_process_delta_time())
		await get_tree().physics_frame
	var travelled: float = before.distance_to(player.global_position)
	_check("se desplazó con input hacia delante", travelled > 1.0)
	print("  (recorrió %.2f m)" % travelled)

	# El host se dirige los rpc_id(1) a sí mismo. Sin "call_local" en el @rpc,
	# Godot los rechaza y el anfitrión no puede ni soltar ni recoger ni disparar.
	# Este bloque existe porque ese bug se escapó a la primera tanda de tests.
	print("--- Soltar y recoger siendo el host ---")
	_check("empieza con un item", player.inventory.items.size() == 1)
	player.inventory.request_drop(0)
	await get_tree().process_frame
	_check("soltar vacía el inventario", player.inventory.items.is_empty())
	_check("aparece un pickup en el mundo", spawner.pickups_container.get_child_count() == 1)

	var pickup: EquipmentPickup = spawner.pickups_container.get_child(0) as EquipmentPickup
	_check("el pickup es del tipo correcto", pickup != null)
	if pickup:
		# Detección por RAYCAST real, no asignando current_target a mano: eso es
		# lo que ocultó que RayCast3D ignora las Area3D por defecto.
		_check("el pickup está en la capa de interacción",
			pickup.collision_layer == Interactable.INTERACTION_LAYER)
		_check("el rayo detecta áreas", player.interaction.ray.collide_with_areas)

		var ray: RayCast3D = player.interaction.ray
		pickup.global_position = ray.global_position - ray.global_basis.z * 1.5
		await get_tree().physics_frame
		ray.force_raycast_update()
		_check("el rayo golpea el pickup", ray.is_colliding() and ray.get_collider() == pickup)

		await get_tree().physics_frame
		_check("InteractionComponent lo fija como objetivo",
			player.interaction.current_target == pickup)

		player.interaction.request_interact()
		await get_tree().process_frame
		_check("recogerlo lo devuelve al inventario", player.inventory.items.size() == 1)
		_check("el pickup desaparece del mundo", not is_instance_valid(pickup) \
			or pickup.is_queued_for_deletion())
		# Sin esto el item volvía al inventario pero guardado: invisible y sin
		# poder usarlo, porque no hay acción para cambiar de slot.
		_check("y vuelve a la mano, no al fondo del inventario",
			player.inventory.active_item != null \
			and player.inventory.active_item.is_equipped())

	print("--- Disparar siendo el host ---")
	# Independiente de debug_role: metemos un arma a mano para cubrir siempre
	# este camino, que es el que reventaba.
	player.inventory.add_item_from_scene("res://equipment/firearm.tscn", {})
	await get_tree().process_frame
	var gun_index: int = player.inventory.items.size() - 1
	player.inventory.request_equip(gun_index)
	await get_tree().process_frame
	var gun: Firearm = player.inventory.active_item as Firearm
	_check("equipar el arma por petición al host", gun != null)
	if gun:
		var ammo_before: int = gun.in_magazine
		gun.use()
		await get_tree().process_frame
		_check("el disparo consume munición", gun.in_magazine == ammo_before - 1)
		_check("resolvió competencia al equiparla", gun.proficiency != null)

	_finish()


## Arranca un temporizador de 60 s que da el test por fallido si no ha terminado: si un error
## de script aborta la corrutina [code]_ready()[/code], [code]_finish()[/code] nunca corre y el
## proceso se quedaría colgado para siempre.
func _start_watchdog() -> void:
	get_tree().create_timer(60.0).timeout.connect(_on_watchdog_timeout)


## Si el test no ha terminado, lo avisa y cierra el proceso con código 99.
func _on_watchdog_timeout() -> void:
	if completed:
		return
	print(">>> WATCHDOG: el test no terminó (mira el SCRIPT ERROR de arriba)")
	get_tree().quit(99)


## Marca el test como terminado, imprime el resumen y cierra el proceso con el número de fallos
## como código de salida.
func _finish() -> void:
	completed = true
	print("")
	if failures == 0:
		print(">>> TODO OK")
	else:
		print(">>> %d FALLOS" % failures)
	get_tree().quit(failures)


## Imprime el resultado de una comprobación y suma un fallo si no se cumple.
## Recibe: [param label] — descripción de lo comprobado; [param condition] — si se cumple.
func _check(label: String, condition: bool) -> void:
	if condition:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FALLO %s" % label)
