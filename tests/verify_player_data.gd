extends Node

## Verificación de la capa de jugadores sin abrir el editor.
##
##   "$GODOT" --headless --path . res://tests/verify_player_data.tscn
##
## Sale con código != 0 si algo falla, así que sirve en CI.
##
## Corre como ESCENA y no con --script a propósito: con --script el bucle
## principal no crea un MultiplayerAPI, `Node.multiplayer` es null y todo lo que
## toque autoridad o RPC revienta.

var failures: int = 0
var runtime_completed: bool = false


func _ready() -> void:
	# is_server() y los .rpc() necesitan un peer, aunque sea offline.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	_verify_data()
	await _verify_runtime()

	print("")
	# Un error de script aborta la función pero no la escena: sin este centinela
	# el test cantaría victoria habiéndose saltado media batería.
	if not runtime_completed:
		failures += 1
		print(">>> La fase de runtime no terminó (mira el SCRIPT ERROR de arriba)")
	if failures == 0:
		print(">>> TODO OK")
	else:
		print(">>> %d FALLOS" % failures)
	get_tree().quit(failures)


func _verify_data() -> void:
	print("--- RoleDatabase ---")
	_check("perfil del militar existe", RoleDatabase.get_profile(Statics.Role.SOLDIER) != null)
	_check("nombre del vidente", RoleDatabase.get_role_name(Statics.Role.SEER) == "Vidente")
	_check("nombre del tecnico", RoleDatabase.get_role_name(Statics.Role.TECHNICIAN) == "Técnico")
	_check("nombre del militar", RoleDatabase.get_role_name(Statics.Role.SOLDIER) == "Militar")
	_check("3 roles seleccionables", RoleDatabase.get_selectable_roles().size() == 3)
	_check("NONE no es seleccionable", not RoleDatabase.get_selectable_roles().has(Statics.Role.NONE))

	print("--- Competencia: el militar es experto con su arma ---")
	var soldier: RoleProfile = RoleDatabase.get_profile(Statics.Role.SOLDIER)
	var soldier_gun: FirearmProficiency = soldier.get_proficiency(Statics.EquipmentTag.FIREARM) as FirearmProficiency
	_check("militar tiene FirearmProficiency", soldier_gun != null)
	_check("militar no tiembla", soldier_gun != null and is_zero_approx(soldier_gun.sway_amplitude))
	_check("militar sin penalizacion de dispersion", soldier_gun != null and is_equal_approx(soldier_gun.spread_multiplier, 1.0))

	print("--- Competencia: fallback para quien no es su rol ---")
	var technician: RoleProfile = RoleDatabase.get_profile(Statics.Role.TECHNICIAN)
	var tech_gun: FirearmProficiency = technician.get_proficiency(Statics.EquipmentTag.FIREARM) as FirearmProficiency
	_check("tecnico cae al default de arma", tech_gun != null)
	_check("tecnico SI tiembla", tech_gun != null and tech_gun.sway_amplitude > 0.0)
	_check("tecnico puede usarla igual", tech_gun != null and tech_gun.usable)

	var seer: RoleProfile = RoleDatabase.get_profile(Statics.Role.SEER)
	var seer_light: LightProficiency = seer.get_proficiency(Statics.EquipmentTag.LIGHT_SOURCE) as LightProficiency
	_check("vidente cae al default de luz", seer_light != null)
	_check("vidente hace parpadear la linterna", seer_light != null and seer_light.flicker_chance > 0.0)

	var tech_light: LightProficiency = technician.get_proficiency(Statics.EquipmentTag.LIGHT_SOURCE) as LightProficiency
	_check("tecnico experto con la luz", tech_light != null and is_zero_approx(tech_light.flicker_chance))

	print("--- Fallback global para tags sin default ---")
	_check("tag sin default cae al fallback", soldier.get_proficiency(Statics.EquipmentTag.RITUAL_TOOL) != null)

	print("--- Percepcion ---")
	_check("vidente NO ve la capa 1 (mundo)", seer.vision_mode.cull_mask & 1 == 0)
	_check("vidente SI ve la capa 2 (etereos)", seer.vision_mode.cull_mask & 2 != 0)
	_check("militar SI ve el mundo", soldier.vision_mode.cull_mask & 1 != 0)
	_check("militar NO ve etereos", soldier.vision_mode.cull_mask & 2 == 0)


func _verify_runtime() -> void:
	var scene: PackedScene = load("res://player/player.tscn") as PackedScene
	_check("player.tscn carga", scene != null)
	var p: Player = scene.instantiate() as Player
	_check("player.tscn instancia un Player", p != null)
	# Los @export de tipo nodo se resuelven al entrar al árbol, no al instanciar.
	# OJO: add_child() directo sobre root desde _ready() FALLA ("parent node is
	# busy setting up children") y solo deja un ERROR en consola — el nodo se
	# queda fuera del árbol y todo lo demás falla en cascada.
	get_tree().root.add_child.call_deferred(p)
	await get_tree().process_frame
	_check("el Player entró al árbol", p.is_inside_tree())
	p.setup(Statics.PlayerData.new(77, "Tester", 0, Statics.Role.SOLDIER))
	await get_tree().process_frame

	print("--- Cableado de la escena ---")
	_check("componentes cableados", p.movement != null and p.view != null \
		and p.interaction != null and p.inventory != null and p.health != null \
		and p.perception != null)
	_check("nodos cableados", p.head != null and p.camera != null and p.hand_anchor != null \
		and p.body != null and p.hud_layer != null and p.synchronizer != null)
	_check("componentes conocen a su Player", p.movement.player == p and p.view.player == p)
	_check("ViewComponent tiene la cabeza", p.view.head == p.head)
	_check("Inventory tiene el hand_anchor", p.inventory.hand_anchor == p.hand_anchor)
	_check("Interaction tiene el ray", p.interaction.ray != null)

	print("--- Reparto de autoridad ---")
	_check("Player al cliente dueño", p.get_multiplayer_authority() == 77)
	_check("Movement al cliente", p.movement.get_multiplayer_authority() == 77)
	_check("View al cliente", p.view.get_multiplayer_authority() == 77)
	_check("Perception al cliente", p.perception.get_multiplayer_authority() == 77)
	_check("Synchronizer al cliente", p.synchronizer.get_multiplayer_authority() == 77)
	_check("Health al SERVIDOR", p.health.get_multiplayer_authority() == Statics.SERVER_ID)
	_check("Inventory al SERVIDOR", p.inventory.get_multiplayer_authority() == Statics.SERVER_ID)
	_check("HandAnchor al SERVIDOR", p.hand_anchor.get_multiplayer_authority() == Statics.SERVER_ID)

	print("--- Loadout inicial ---")
	_check("el militar aparece con su arma", p.inventory.items.size() == 1)
	_check("y la lleva equipada", p.inventory.active_item != null)
	var gun: Firearm = p.inventory.active_item as Firearm
	_check("el item activo es el arma", gun != null)
	_check("resolvió su competencia al equipar", gun != null and gun.proficiency != null)
	_check("el militar no tiembla con ella", gun != null \
		and is_zero_approx((gun.proficiency as FirearmProficiency).sway_amplitude))

	print("--- Estado transferible del item ---")
	if gun:
		gun.in_magazine = 3
		var state: Dictionary = gun.get_state()
		_check("get_state guarda la munición", state.get("in_magazine") == 3)
		var fresh: Firearm = load("res://equipment/firearm.tscn").instantiate() as Firearm
		fresh.set_state(state)
		_check("set_state la restaura", fresh.in_magazine == 3)
		fresh.free()

	print("--- Soltar no deja huérfanos ---")
	var dropped: Equipment = p.inventory.active_item
	p.inventory.drop_all()
	_check("el inventario queda vacío", p.inventory.items.is_empty())
	_check("no queda item activo", p.inventory.active_item == null)
	_check("el item se libera (no huérfano)", not is_instance_valid(dropped) \
		or dropped.is_queued_for_deletion())

	print("--- Recoger deja el item en la mano ---")
	# Con las manos vacías y sin acción de cambio de slot, un item recogido que
	# no se equipa solo queda invisible e inservible para siempre.
	p.inventory.add_item_from_scene("res://equipment/firearm.tscn", {"in_magazine": 3})
	_check("el item recogido entra al inventario", p.inventory.items.size() == 1)
	_check("y queda activo", p.inventory.active_item != null)
	var picked: Firearm = p.inventory.active_item as Firearm
	_check("el item recogido está equipado", picked != null and picked.is_equipped())
	_check("su modelo se ve", picked != null \
		and (picked.model == null or picked.model.visible))
	_check("conserva la munición al recogerlo", picked != null and picked.in_magazine == 3)

	print("--- Reanimar devuelve el control ---")
	_check("Player conecta health.revived", p.health.revived.is_connected(p._handle_revived))
	p.health.max_health = 10.0
	p.health.current_health = 10.0
	p.health.apply_damage(20.0)
	_check("queda derribado", p.health.is_downed)
	_check("no está muerto (es reanimable)", not p.health.is_dead)
	p.health.revive()
	_check("revive", not p.health.is_downed)
	_check("recupera vida al revivir", p.health.current_health > 0.0)

	print("--- Escenas nuevas ---")
	var pickup: EquipmentPickup = load("res://equipment/equipment_pickup.tscn").instantiate() as EquipmentPickup
	_check("el pickup es un Interactable", pickup is Interactable)
	if pickup:
		pickup.free()

	var spawner: PlayerSpawner = load("res://player/player_spawner.tscn").instantiate() as PlayerSpawner
	_check("spawner instancia", spawner != null)
	_check("spawner cableado", spawner != null and spawner.players_spawner != null \
		and spawner.pickups_spawner != null and spawner.player_scene != null \
		and spawner.pickup_scene != null)
	if spawner:
		spawner.free()

	p.free()
	runtime_completed = true


func _check(label: String, condition: bool) -> void:
	if condition:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FALLO %s" % label)
