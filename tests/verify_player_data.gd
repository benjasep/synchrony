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

	print("--- Percepcion: el vidente reconstruye, los demas miran ---")
	# La cámara del vidente SÍ dibuja el mundo, y eso no contradice que sea
	# ciego: es la única forma de tener su profundidad en el depth buffer. Lo
	# que ve es el eco que el shader saca de ahí; el color del mundo queda
	# tapado por el quad.
	_check("la camara del vidente solo dibuja el mundo (fuente del depth)",
		seer.vision_mode.cull_mask == Statics.WORLD_VISUAL_LAYER)
	_check("el vidente tiene shader de eco", seer.vision_mode.post_process_shader != null)
	_check("y un alcance limitado", seer.vision_mode.perception_radius > 0.0)
	# Todo lo que el vidente ve "bien" llega por la segunda pasada: si cayera en
	# la pasada principal se lo comería el post-proceso.
	_check("vidente SI ve etereos (segunda pasada)",
		seer.vision_mode.ethereal_cull_mask & Statics.ETHEREAL_VISUAL_LAYER != 0)
	_check("vidente SI ve a sus companeros",
		seer.vision_mode.ethereal_cull_mask & Statics.BODY_VISUAL_LAYER != 0)
	_check("vidente SI ve el item que empuna",
		seer.vision_mode.ethereal_cull_mask & Statics.VIEWMODEL_VISUAL_LAYER != 0)
	_check("la segunda pasada NO repite el mundo",
		seer.vision_mode.ethereal_cull_mask & Statics.WORLD_VISUAL_LAYER == 0)

	for other: RoleProfile in [technician, soldier]:
		_check("%s SI ve el mundo" % other.display_name,
			other.vision_mode.cull_mask & Statics.WORLD_VISUAL_LAYER != 0)
		_check("%s NO ve etereos" % other.display_name,
			other.vision_mode.cull_mask & Statics.ETHEREAL_VISUAL_LAYER == 0)
		# Sin segunda pasada no hay por dónde colarse: es la única que dibuja la
		# capa etérea.
		_check("%s no tiene segunda pasada" % other.display_name,
			other.vision_mode.ethereal_cull_mask == 0)
		_check("%s sin post-proceso" % other.display_name,
			other.vision_mode.post_process_shader == null)

	print("--- Enemigo etereo ---")
	var enemy_scene: PackedScene = load("res://enemies/ethereal_entity.tscn") as PackedScene
	_check("ethereal_entity.tscn carga", enemy_scene != null)
	var enemy: EtherealEntity = enemy_scene.instantiate() as EtherealEntity
	_check("es un EtherealEntity", enemy != null)
	if enemy:
		_check("cableado", enemy.model != null and enemy.model_placeholder != null \
			and enemy.health != null)
		# El cubo viene ya en la capa etérea desde la escena; _ready() la fuerza
		# otra vez para cubrir el .glb que vendrá de Blender.
		_check("el placeholder esta en la capa eterea",
			enemy.model_placeholder != null \
			and enemy.model_placeholder.layers == Statics.ETHEREAL_VISUAL_LAYER)
		_check("NO esta en la capa del mundo (o lo verian los tres)",
			enemy.model_placeholder != null \
			and enemy.model_placeholder.layers & Statics.WORLD_VISUAL_LAYER == 0)
		enemy.free()


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
		and p.body != null and p.body_placeholder != null and p.hud_layer != null \
		and p.synchronizer != null)
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

	print("--- Modelo del cuerpo ---")
	for role: Statics.Role in RoleDatabase.get_selectable_roles():
		var profile: RoleProfile = RoleDatabase.get_profile(role)
		_check("%s trae body_scene" % profile.display_name, profile.body_scene != null)
	var model: Node3D = p.body.get_child(p.body.get_child_count() - 1) as Node3D
	_check("el modelo colgó de Body", model != null and model != p.body_placeholder)
	_check("la cápsula de referencia se ocultó", not p.body_placeholder.visible)
	# En la capa 1 el vidente (cull_mask 14) no vería a sus compañeros.
	_check("el modelo está en la capa de cuerpos", model != null \
		and _all_meshes_in_body_layer(model))
	# Este peer es el 1 y el dueño del Player es el 77, así que la instancia es
	# la copia remota de otro jugador: su cuerpo TIENE que verse. Al dueño se le
	# apaga en _configure_local_only() para no romper la primera persona.
	_check("el cuerpo de otro jugador se ve", p.body.visible)

	print("--- Medidas del cuerpo ---")
	var soldier_profile: RoleProfile = RoleDatabase.get_profile(Statics.Role.SOLDIER)
	_check("la cámara está a la altura del perfil", \
		is_equal_approx(p.head.position.y, soldier_profile.eye_height))
	var shape: CapsuleShape3D = p.collision.shape as CapsuleShape3D
	_check("la cápsula mide lo que dice el perfil", shape != null \
		and is_equal_approx(shape.height, soldier_profile.body_height) \
		and is_equal_approx(shape.radius, soldier_profile.body_radius))
	_check("y apoya en el suelo", \
		is_equal_approx(p.collision.position.y, soldier_profile.body_height * 0.5))
	_check("la cámara no sobresale del cuerpo", p.head.position.y <= soldier_profile.body_height)
	# Los sub-recursos de un .tscn se comparten entre instancias: sin duplicate()
	# redimensionar a un jugador se lo redimensionaría a todos.
	var untouched: Player = scene.instantiate() as Player
	_check("la cápsula es propia de esta instancia", p.collision.shape != untouched.collision.shape)
	untouched.free()

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

	await _verify_seer_view()
	runtime_completed = true


## El vidente en caliente. Hace falta un Player entero y no solo su .tres porque
## lo que se comprueba es el cableado de las tres piezas de su vista.
##
## El id tiene que ser el de este peer: PerceptionComponent solo configura la
## percepción del dueño, así que con un id ajeno no se aplicaría nada y el test
## pasaría en vacío.
func _verify_seer_view() -> void:
	print("--- Vista del vidente, en caliente ---")
	var local_id: int = multiplayer.get_unique_id()
	var seer: Player = load("res://player/player.tscn").instantiate() as Player
	get_tree().root.add_child.call_deferred(seer)
	await get_tree().process_frame
	seer.setup(Statics.PlayerData.new(local_id, "Vidente", 0, Statics.Role.SEER))
	await get_tree().process_frame

	_check("es el jugador local", seer.is_local_player())
	_check("perception cableado", seer.perception.echo_quad != null \
		and seer.perception.ethereal_viewport != null \
		and seer.perception.ethereal_camera != null \
		and seer.perception.ethereal_view != null)

	_check("la camara dibuja el mundo (depth del eco)",
		seer.camera.cull_mask == Statics.WORLD_VISUAL_LAYER)
	_check("el quad de eco esta visible", seer.perception.echo_quad.visible)
	var material: ShaderMaterial = seer.perception.echo_quad.material_override as ShaderMaterial
	_check("con material de shader", material != null)
	_check("y el shader del perfil", material != null and material.shader != null)
	# Si el quad cayera fuera del cull_mask de la cámara no se dibujaría y el
	# post-proceso se aplicaría a nada.
	_check("el quad cae dentro del cull_mask de la camara",
		seer.perception.echo_quad.layers & seer.camera.cull_mask != 0)
	_check("el radio del perfil llego al shader", material != null \
		and is_equal_approx(material.get_shader_parameter(&"perception_radius"), 12.0))

	_check("la segunda pasada renderiza", seer.perception.ethereal_viewport.render_target_update_mode \
		== SubViewport.UPDATE_ALWAYS)
	_check("con fondo transparente", seer.perception.ethereal_viewport.transparent_bg)
	# Con mundo propio la segunda cámara miraría a un escenario vacío: no habría
	# enemigos que dibujar.
	_check("y sobre el MISMO World3D", not seer.perception.ethereal_viewport.own_world_3d)
	_check("la camara eterea ve la capa 2",
		seer.perception.ethereal_camera.cull_mask & Statics.ETHEREAL_VISUAL_LAYER != 0)
	_check("y NO repite el mundo",
		seer.perception.ethereal_camera.cull_mask & Statics.WORLD_VISUAL_LAYER == 0)
	_check("se compone en el HUD", seer.perception.ethereal_view.visible \
		and seer.perception.ethereal_view.texture != null)

	# El SubViewport no es un Node3D: la cadena de transformadas se corta ahí y
	# sin la copia manual la segunda cámara se queda en el origen.
	seer.global_position = Vector3(3.0, 0.0, -7.0)
	await get_tree().process_frame
	_check("la camara eterea sigue a la principal",
		seer.perception.ethereal_camera.global_position.is_equal_approx(seer.camera.global_position))

	print("--- ...y el militar no monta nada de eso ---")
	var soldier: Player = load("res://player/player.tscn").instantiate() as Player
	get_tree().root.add_child.call_deferred(soldier)
	await get_tree().process_frame
	soldier.setup(Statics.PlayerData.new(local_id, "Militar", 0, Statics.Role.SOLDIER))
	await get_tree().process_frame
	_check("sin quad de eco", not soldier.perception.echo_quad.visible)
	_check("sin segunda pasada", soldier.perception.ethereal_viewport.render_target_update_mode \
		== SubViewport.UPDATE_DISABLED)
	_check("sin composicion en el HUD", not soldier.perception.ethereal_view.visible)
	_check("su camara NO dibuja la capa eterea",
		soldier.camera.cull_mask & Statics.ETHEREAL_VISUAL_LAYER == 0)
	# El arma en la mano tiene que salir de la capa del mundo o el vidente que la
	# recoja empuñaría un item invisible.
	var gun: Equipment = soldier.inventory.active_item
	_check("el item empunado pasa a la capa de viewmodel", gun != null \
		and gun.model != null and _all_meshes_in_layer(gun.model, Statics.VIEWMODEL_VISUAL_LAYER))

	seer.queue_free()
	soldier.queue_free()


func _check(label: String, condition: bool) -> void:
	if condition:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FALLO %s" % label)


func _all_meshes_in_body_layer(node: Node) -> bool:
	return _all_meshes_in_layer(node, Statics.BODY_VISUAL_LAYER)


func _all_meshes_in_layer(node: Node, layer: int) -> bool:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry and geometry.layers != layer:
		return false
	for child: Node in node.get_children():
		if not _all_meshes_in_layer(child, layer):
			return false
	return true
