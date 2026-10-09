extends Node

## Verifica la capa de jugadores, los enemigos y la animación; sale con código != 0 si falla.
## Se corre como escena y no con --script, que deja [code]multiplayer[/code] en null:
## [code]"$GODOT" --headless --path . res://tests/verify_player_data.tscn[/code]

var failures: int = 0
var runtime_completed: bool = false


## Pone un peer offline (los RPC y [code]is_server()[/code] lo necesitan), ejecuta las dos
## fases e imprime el resumen; cuenta como fallo que la fase de runtime no termine. Cierra el
## proceso con el número de fallos como código de salida.
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


## Comprueba los datos sin montar jugadores: nombres y roles de [RoleDatabase], competencias y
## su fallback, máscaras de visión de cada rol y la escena del enemigo etéreo.
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
	var enemy: Enemy = enemy_scene.instantiate() as Enemy
	_check("es un Enemy", enemy != null)
	if enemy:
		_check("cableado", enemy.model != null and enemy.model_placeholder != null \
			and enemy.health != null)
		_check("marcado como etereo", enemy.is_ethereal \
			and enemy.get_visual_layer() == Statics.ETHEREAL_VISUAL_LAYER)
		# El cubo viene ya en la capa etérea desde la escena; _ready() la fuerza
		# otra vez para cubrir el .glb que vendrá de Blender.
		_check("el placeholder esta en la capa eterea",
			enemy.model_placeholder != null \
			and enemy.model_placeholder.layers == Statics.ETHEREAL_VISUAL_LAYER)
		_check("NO esta en la capa del mundo (o lo verian los tres)",
			enemy.model_placeholder != null \
			and enemy.model_placeholder.layers & Statics.WORLD_VISUAL_LAYER == 0)
		enemy.free()


## Comprueba un [Player] militar de otro peer (id 77) ya en el árbol: cableado, reparto de
## autoridad, modelo y medidas del cuerpo, loadout, estado del item, soltar, recoger,
## reanimar y las escenas de pickup y spawner. Después lanza las verificaciones en caliente y
## marca [code]runtime_completed[/code].
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
	await _verify_body_animation("res://player/bodies/cat_body.tscn", 4.0)
	await _verify_body_animation("res://enemies/pesadilla/pesadilla_animation.tscn", 1.5)
	await _verify_physical_enemy()
	await _verify_foot_placement()
	runtime_completed = true


## Mueve a mano un envoltorio de modelo y comprueba que su [LocomotionAnimator] mide la
## velocidad por posición, se la pasa al árbol, ignora un teletransporte y apaga el árbol al
## ocultarse: la misma medida que hace un peer remoto, donde velocity no se replica.
## Recibe: [param path] — escena del envoltorio; [param test_speed] — velocidad simulada
## en m/s.
func _verify_body_animation(path: String, test_speed: float) -> void:
	print("--- Animacion: %s ---" % path.get_file())
	var holder: Node3D = Node3D.new()
	get_tree().root.add_child.call_deferred(holder)
	var body: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	holder.add_child(body)
	await get_tree().process_frame
	var animator: LocomotionAnimator = body.get_node_or_null("LocomotionAnimator") as LocomotionAnimator
	_check("tiene LocomotionAnimator", animator != null)
	if not animator:
		holder.free()
		return
	_check("animador cableado", animator.tree != null and animator.tracked == body)
	# Se pregunta al árbol y no a un AnimationPlayer concreto: el del gato vive
	# en el envoltorio, el de la pesadilla viene dentro de su .glb.
	_check("el arbol ve idle, caminar y correr", animator.tree.has_animation(&"idle") \
		and animator.tree.has_animation(&"caminar") and animator.tree.has_animation(&"correr"))

	for i: int in 45:
		await get_tree().physics_frame
		holder.position.x += test_speed / Engine.physics_ticks_per_second
	_check("mide la velocidad por posicion", absf(animator.speed - test_speed) < 0.2)
	_check("y se la pasa al arbol",
		absf(float(animator.tree.get(animator.blend_parameter)) - test_speed) < 0.2)
	var playback: AnimationNodeStateMachinePlayback = animator.tree.get(&"parameters/playback") \
		as AnimationNodeStateMachinePlayback
	_check("el arbol arranca en locomotion",
		playback != null and playback.get_current_node() == &"locomotion")

	holder.position.x += 50.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("ignora un teletransporte", animator.speed < animator.max_plausible_speed)

	# Al dueño el cuerpo se le oculta en primera persona.
	holder.visible = false
	await get_tree().physics_frame
	_check("oculto, el arbol se apaga", not animator.tree.active)
	holder.free()


## Mete la pesadilla en el árbol (su modelo se instancia en [code]_ready()[/code]) y comprueba
## que trae su modelo y que todo él queda solo en la capa del mundo: si cayera en la etérea, el
## técnico y el militar no la verían.
func _verify_physical_enemy() -> void:
	print("--- Enemigo fisico (pesadilla) ---")
	var enemy: Enemy = (load("res://enemies/pesadilla/pesadilla.tscn") as PackedScene) \
		.instantiate() as Enemy
	_check("es un Enemy", enemy != null)
	if not enemy:
		return
	get_tree().root.add_child.call_deferred(enemy)
	await get_tree().process_frame
	_check("no es etereo", not enemy.is_ethereal)
	_check("trae su modelo y oculta el cubo", enemy.model.get_child_count() > 1 \
		and not enemy.model_placeholder.visible)
	_check("todo el modelo en la capa del mundo",
		_all_meshes_in_layer(enemy.model, Statics.WORLD_VISUAL_LAYER))
	enemy.queue_free()
	await get_tree().process_frame


## Compara los pies de la pesadilla en plano y sobre escalones con la animación pura: el foot
## placement debe desplazar cada pie exactamente lo que sube o baja el suelo bajo él. El
## modelo mira a -X, así que un escalón que acaba en x = -0.3 separa los pies delanteros de
## los traseros.
func _verify_foot_placement() -> void:
	print("--- Foot placement (pesadilla) ---")
	var step: float = 0.25
	var flat: Array[AABB] = [AABB(Vector3(-5, -1, -5), Vector3(10, 1, 10))]
	var step_up_front: Array[AABB] = [AABB(Vector3(-5, -1, -5), Vector3(10, 1, 10)),
		AABB(Vector3(-3, 0, -2), Vector3(2.7, step, 4))]
	var step_down_rear: Array[AABB] = [AABB(Vector3(-5, -1, -5), Vector3(4.7, 1, 10)),
		AABB(Vector3(-0.3, -1 - step, -5), Vector3(5.3, 1, 10))]

	# [trasero L, trasero R, delantero L, delantero R]
	var animated: Array[float] = await _feet_heights_on(flat, false)
	_check("el envoltorio trae FootPlacement con cuatro patas", animated.size() == 4)
	if animated.size() != 4:
		return
	var on_flat: Array[float] = await _feet_heights_on(flat, true)
	_check("en plano no cambia la animacion", _feet_match(on_flat, animated, [0.0, 0.0, 0.0, 0.0]))
	var front_up: Array[float] = await _feet_heights_on(step_up_front, true)
	_check("escalon delante: las manos suben y las patas traseras no",
		_feet_match(front_up, animated, [0.0, 0.0, step, step]))
	var rear_down: Array[float] = await _feet_heights_on(step_down_rear, true)
	_check("desnivel detras: las patas traseras bajan y las manos no",
		_feet_match(rear_down, animated, [-step, -step, 0.0, 0.0]))
	var disabled: Array[float] = await _feet_heights_on(step_up_front, false)
	_check("apagado, manda la animacion", _feet_match(disabled, animated, [0.0, 0.0, 0.0, 0.0]))


## Monta un suelo de cajas, pone la pesadilla encima y mide la altura global de cada hueso de
## contacto. Lee dentro de [code]skeleton_updated[/code] porque fuera de esa señal Godot ya ha
## descartado la pose modificada y solo queda la animación pura.
## Recibe: [param ground] — cajas del suelo, en coordenadas globales; [param placement_enabled]
## — si el foot placement está encendido.
## Devuelve: una altura por pata, en el orden de [code]legs[/code]; vacío si el modelo no trae
## un [FootPlacement] con cuatro patas.
func _feet_heights_on(ground: Array[AABB], placement_enabled: bool) -> Array[float]:
	var holder: Node3D = Node3D.new()
	for box: AABB in ground:
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = box.size
		shape.shape = box_shape
		body.position = box.get_center()
		body.add_child(shape)
		holder.add_child(body)
	var model: Node3D = (load("res://enemies/pesadilla/pesadilla_animation.tscn") as PackedScene) \
		.instantiate() as Node3D
	holder.add_child(model)
	get_tree().root.add_child.call_deferred(holder)
	await get_tree().process_frame

	var heights: Array[float] = []
	var placement: FootPlacement = model.get_node_or_null("pesadilla/Armature/Skeleton3D/FootPlacement") \
		as FootPlacement
	if not placement or placement.legs.size() != 4:
		holder.free()
		return heights
	placement.enabled = placement_enabled
	# Que la física registre el suelo y que el suavizado y el fundido se asienten.
	await get_tree().create_timer(0.8).timeout

	var skeleton: Skeleton3D = placement.get_skeleton()
	skeleton.skeleton_updated.connect(func() -> void:
		for leg: FootPlacementLeg in placement.legs:
			var bone: int = skeleton.find_bone(leg.contact_bone)
			heights.append((skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin.y),
		CONNECT_ONE_SHOT)
	await skeleton.skeleton_updated
	# El await se reanuda DENTRO de la emisión: liberar aquí el esqueleto que la
	# está emitiendo tumba el motor. Se espera a que termine el frame.
	holder.queue_free()
	await get_tree().process_frame
	return heights


## Comprueba que cada pie esté a su altura animada más el desnivel esperado, con 2 cm de
## tolerancia por lo poco que se mueve el idle entre muestras; imprime el primer pie que falla.
## Recibe: [param measured] — alturas medidas; [param animated] — alturas en plano sin foot
## placement; [param expected_offsets] — desnivel esperado de cada pie.
## Devuelve: [code]true[/code] si todos los pies coinciden.
func _feet_match(measured: Array[float], animated: Array[float], expected_offsets: Array[float]) -> bool:
	if measured.size() != animated.size():
		return false
	for i: int in measured.size():
		if absf(measured[i] - (animated[i] + expected_offsets[i])) > 0.02:
			print("        pie %d: %.3f, esperado %.3f" % [i, measured[i], animated[i] + expected_offsets[i]])
			return false
	return true


## Monta un vidente y un militar enteros y comprueba las tres piezas de la vista del vidente
## (cámara, quad de eco, segunda pasada) y que el militar no monte ninguna. Usa el id de este
## peer: la percepción solo se configura en el dueño, y con un id ajeno pasaría en vacío.
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


## Imprime el resultado de una comprobación y suma un fallo si no se cumple.
## Recibe: [param label] — descripción de lo comprobado; [param condition] — si se cumple.
func _check(label: String, condition: bool) -> void:
	if condition:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FALLO %s" % label)


## Devuelve [code]true[/code] si toda la geometría bajo [param node] está solo en la capa de
## cuerpos.
func _all_meshes_in_body_layer(node: Node) -> bool:
	return _all_meshes_in_layer(node, Statics.BODY_VISUAL_LAYER)


## Recorre [param node] y sus descendientes comprobando que cada [GeometryInstance3D] tenga
## exactamente [param layer] como máscara de capas visuales.
## Devuelve: [code]true[/code] si todas la tienen (también si no hay geometría).
func _all_meshes_in_layer(node: Node, layer: int) -> bool:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry and geometry.layers != layer:
		return false
	for child: Node in node.get_children():
		if not _all_meshes_in_layer(child, layer):
			return false
	return true
