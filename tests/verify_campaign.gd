extends Node

const TUTORIAL_PATH: String = "res://levels/tutorial.tscn"
const LEVEL_1_PATH: String = "res://levels/level_1.tscn"
const REPORT_PATH: String = "res://equipment/evidence_report.tscn"
const CARD_PATH: String = "res://equipment/evidence_id_card.tscn"

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree: SceneTree = get_tree()
	# Deja el verificador en la raíz mientras el juego cambia sus escenas activas.
	tree.current_scene = null
	tree.create_timer(10.0).timeout.connect(func() -> void: tree.quit(1))
	_check("el tutorial sigue siendo el mapa por defecto", Game.instance.main_scene.resource_path == TUTORIAL_PATH)
	await _verify_map_tabs()
	tree.change_scene_to_packed(Game.instance.get_level_scene(Game.instance.selected_level))
	await tree.scene_changed
	await tree.process_frame
	var tutorial: MissionDirector = MissionDirector.instance
	tutorial.end_screen_seconds = 0.05
	_check("el tutorial conserva la misión original de Greybox",
		tutorial.mission.resource_path == "res://mission/missions/test_mission.tres")
	_check("el tutorial usa una de las extracciones originales",
		tutorial.extraction_zone != null and tutorial.extraction_zone.get_parent().name == &"Extraction")
	await _complete_mission(2)
	await tree.scene_changed
	_check("ganar el tutorial carga Nivel 1", tree.current_scene.scene_file_path == LEVEL_1_PATH)
	await tree.process_frame
	await _verify_level_1_layout(tree.current_scene)
	MissionDirector.instance.return_after_end = false
	await _complete_mission(2)
	print(">>> Campaña: %d fallos" % failures)
	tree.quit(failures)


func _verify_map_tabs() -> void:
	var tree: SceneTree = get_tree()
	tree.change_scene_to_file("res://ui/main_menu.tscn")
	await tree.scene_changed
	await tree.process_frame
	var menu: MainMenu = tree.current_scene as MainMenu
	var tutorial: Button = menu.level_tabs.get_child(0) as Button
	var level_1: Button = menu.level_tabs.get_child(1) as Button
	_check("el menú ofrece Tutorial y Nivel 1", tutorial.text == "Tutorial" and level_1.text == "Nivel 1")
	_click_tab_edge(level_1)
	_check("el borde del recuadro selecciona Nivel 1", level_1.button_pressed and not tutorial.button_pressed
		and Game.instance.get_level_scene(Game.instance.selected_level).resource_path == LEVEL_1_PATH)
	_click_tab_edge(tutorial)
	_check("el borde del recuadro selecciona Tutorial", tutorial.button_pressed and not level_1.button_pressed
		and Game.instance.get_level_scene(Game.instance.selected_level).resource_path == TUTORIAL_PATH)
	_check("seleccionar un mapa conserva el menú para crear la partida", tree.current_scene == menu)


func _click_tab_edge(tab: Button) -> void:
	var position: Vector2 = tab.get_global_transform_with_canvas() * Vector2(tab.size.x - 3.0, tab.size.y * 0.5)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)


func _verify_level_1_layout(level: Node) -> void:
	await get_tree().physics_frame
	var player: Player = PlayerSpawner.instance.get_player(multiplayer.get_unique_id())
	var enemy: Enemy = level.get_node("Enemies/Pesadilla") as Enemy
	var attack: StationaryAttack = enemy.get_node("StationaryAttack") as StationaryAttack
	_check("la Pesadilla del Nivel 1 hereda el ataque automático", attack.combat.enemy == enemy)
	for child: Node in level.get_node("SpawnPoints").get_children():
		var spawn: Marker3D = child as Marker3D
		_check("la Pesadilla está fuera del alcance del punto %s" % spawn.name,
			enemy.global_position.distance_to(spawn.global_position) > attack.combat.melee.reach)
	for house: String in ["root_casa4", "root_casa10"]:
		var door: Node3D = level.get_node("StaticBody3D/Nivel/RootNivel/%s/casa/Door_Frame" % house) as Node3D
		for side: float in [-1.0, 1.0]:
			for offset: float in [-0.25, 0.25]:
				_check("la cápsula atraviesa %s desde ambos lados" % house,
					not _doorway_blocks(player, door, side, offset))
		_check("la pared sigue bloqueando junto a la puerta de %s" % house,
			_doorway_blocks(player, door, 1.0, -1.2))
		var walls: Node3D = door.get_parent() as Node3D
		_check("el lateral izquierdo de %s tiene colisión" % house, _body_motion_blocks(player,
			walls.to_global(Vector3(1, 0.05, -4.5)), walls.global_basis * Vector3(-2, 0, 0)))
		_check("el lateral derecho de %s tiene colisión" % house, _body_motion_blocks(player,
			walls.to_global(Vector3(5.9, 0.05, -4.5)), walls.global_basis * Vector3(2, 0, 0)))
		_check("la pared trasera de %s tiene colisión" % house, _body_motion_blocks(player,
			walls.to_global(Vector3(3.45, 0.05, -7.9)), walls.global_basis * Vector3(0, 0, -2)))


func _doorway_blocks(player: Player, door: Node3D, side: float, offset: float) -> bool:
	var normal: Vector3 = door.global_basis.z.normalized()
	var across: Vector3 = door.global_basis.x.normalized()
	var start: Vector3 = door.global_position + Vector3.UP * 0.05 + across * offset + normal * side
	return _body_motion_blocks(player, start, -normal * side * 2.0)


func _body_motion_blocks(player: Player, start: Vector3, motion: Vector3) -> bool:
	var query: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	query.from = Transform3D(Basis.IDENTITY, start)
	query.motion = motion
	return PhysicsServer3D.body_test_motion(player.get_rid(), query)


func _complete_mission(report_count: int) -> void:
	var director: MissionDirector = MissionDirector.instance
	var spawner: PlayerSpawner = PlayerSpawner.instance
	var player: Player = spawner.get_player(multiplayer.get_unique_id())
	var extraction: ExtractionZone = director.extraction_zone
	_check("la misión está activa y tiene extracción", director.is_running and extraction != null and extraction.is_active)
	_check("un jugador puede completar el nivel en solitario", player != null and spawner.players.size() == 1)
	if not player or not extraction:
		return
	player.movement.set_physics_process(false)
	player.global_position = extraction.global_position + Vector3.UP * 0.05
	for _frame: int in range(12):
		if extraction.contains(player):
			break
		await get_tree().physics_frame
	_check("el jugador entra en la extracción", extraction.contains(player))
	director._evaluate()
	_check("la extracción exige los objetos de misión", not director.has_ended)

	var reports: int = 0
	var cards: int = 0
	for node: Node in spawner.pickups_container.get_children():
		var pickup: EquipmentPickup = node as EquipmentPickup
		if pickup.scene_path == REPORT_PATH:
			reports += 1
		elif pickup.scene_path == CARD_PATH:
			cards += 1
		_check("el objetivo en %s está en un sitio accesible" % pickup.global_position,
			_has_clearance(player, pickup.global_position))
		_check("el objetivo se puede recoger", pickup.can_interact(player))
		pickup.perform(player)
	_check("se colocan los informes y el carnet", reports == report_count and cards == 1)
	_check("la extracción en %s tiene espacio libre" % extraction.global_position,
		_has_clearance(player, extraction.global_position))
	director._evaluate()
	_check("reunir las evidencias en la extracción da la victoria", director.has_ended and director.won)


func _has_clearance(player: Player, position: Vector3) -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = player.collision.shape
	query.transform.origin = position + Vector3.UP * (player.collision.position.y + 0.05)
	query.collision_mask = 1
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _check(label: String, condition: bool) -> void:
	print("%s %s" % ["ok" if condition else "FALLO", label])
	if not condition:
		failures += 1
