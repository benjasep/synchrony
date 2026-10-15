extends Node

## Prueba de extremo a extremo: carga un nivel, aparece, cae, anda, suelta, recoge, dispara y
## cambia de item con las teclas 1–4 siendo el host. Se corre con:
## [code]"$GODOT" --headless --path . res://tests/verify_level_spawn.tscn[/code]

## Nivel propio de la prueba: suelo plano y nada más. No usa [code]test_level.tscn[/code], un
## patio de pruebas que va cambiando: cuando le pusieron el mapa provisional, una de sus casas
## quedó justo delante del origen y el jugador se estampaba contra su pared a los 0,17 m.
const ARENA_PATH: String = "res://tests/spawn_arena.tscn"
const REPORT_PATH: String = "res://equipment/evidence_report.tscn"

var failures: int = 0
var completed: bool = false


## Carga la arena fijando el rol de depuración en militar antes de que entre al árbol (el
## spawner genera ya en su [code]_ready()[/code]) y recorre la batería: configuración sin lobby,
## gravedad, movimiento simulado, soltar y recoger, disparar y cambiar de item.
func _ready() -> void:
	_start_watchdog()
	var level: Node3D = (load(ARENA_PATH) as PackedScene).instantiate() as Node3D
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
		# Sin esto el item volvía al inventario pero guardado: invisible hasta
		# pulsar su tecla, sin que nada avise de que se ha cogido.
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

	await _verify_slot_keys(player, spawner)
	_finish()


## Cambia de item con las acciones [code]slot_1[/code]…[code]slot_4[/code] por la ruta real: el
## evento entra por el viewport, [InventoryComponent] lo recibe en
## [code]_unhandled_input()[/code] y pide el cambio al host con [code]request_equip()[/code].
## Usa una evidencia porque es el caso que motivó las teclas: quien recogía un informe con
## otro item en la mano no podía ni mirarlo ni soltarlo.
func _verify_slot_keys(player: Player, spawner: PlayerSpawner) -> void:
	print("--- Cambiar de item con 1–4 ---")
	var inventory: InventoryComponent = player.inventory
	var added: bool = inventory.add_item_from_scene(REPORT_PATH, {})
	await get_tree().process_frame
	_check("recoge una evidencia sin soltar lo que empuña", added and inventory.active_item != null \
		and inventory.items.back() != inventory.active_item)
	if not added or inventory.items.size() > InventoryComponent.SLOT_ACTIONS.size():
		return
	var report_index: int = inventory.items.size() - 1
	var report: Equipment = inventory.items[report_index]
	var first: Equipment = inventory.items[0]

	await _press_action(InventoryComponent.SLOT_ACTIONS[report_index])
	_check("la tecla %d empuña la evidencia" % (report_index + 1),
		inventory.active_item == report and report.is_equipped())
	await _press_action(InventoryComponent.SLOT_ACTIONS[0])
	_check("la tecla 1 vuelve al primer item y guarda la evidencia",
		inventory.active_item == first and first.is_equipped() and not report.is_equipped())

	# Contador en un Array: una lambda captura por valor, así que un int no cambiaría fuera.
	var equips: Array[int] = [0]
	var count_equip: Callable = func(_item: Equipment) -> void: equips[0] += 1
	inventory.item_equipped.connect(count_equip)
	await _press_action(InventoryComponent.SLOT_ACTIONS[0])
	_check("la tecla del item que ya empuña no pide nada", equips[0] == 0)
	await _press_action(InventoryComponent.SLOT_ACTIONS[InventoryComponent.SLOT_ACTIONS.size() - 1])
	_check("una tecla sin item detrás no cambia nada",
		equips[0] == 0 and inventory.active_item == first)
	inventory.item_equipped.disconnect(count_equip)

	var dummy: Player = spawner.players_container.get_child(1) as Player \
		if spawner.players_container.get_child_count() > 1 else null
	_check("los maniquíes no atienden las teclas", dummy != null \
		and not dummy.inventory.is_processing_unhandled_input())


## Pulsa y suelta [param action] como lo haría el teclado: el evento pasa por [Input] y el
## viewport, así que llega a los [code]_unhandled_input()[/code] igual que una tecla de verdad.
func _press_action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


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
