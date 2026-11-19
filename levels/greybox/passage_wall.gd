class_name PassageWall
extends Node3D

## Muro de greybox con huecos, para probar por dónde cabe quién.

## Metros de muro sobre su eje X local.
@export var length: float = 12.0
## Metros de alto del muro.
@export var height: float = 3.0
## Metros de grosor del muro.
@export var thickness: float = 0.3
## Color del muro.
@export var color: Color = Color(0.62, 0.6, 0.56)

@export_group("Puertas del jugador")
## X local, en metros, del centro de cada puerta del jugador.
@export var player_doors: PackedFloat32Array = PackedFloat32Array()
## Ancho y alto, en metros, de las puertas del jugador.
@export var player_door_size: Vector2 = Vector2(1.0, 2.0)
## Color del dintel y del rótulo de las puertas del jugador.
@export var player_door_color: Color = Color(0.25, 0.6, 0.75)

@export_group("Rótulos")
## Si rotula cada hueco con su nombre y su tamaño.
@export var show_labels: bool = true
## Agente cuya manera de cruzar se añade al rótulo.
@export var label_agent: StringName = LevelNavigation.LARGE_AGENT
## Tamaño de letra de los rótulos.
@export var label_font_size: int = 64
## Metros por píxel de los rótulos.
@export var label_pixel_size: float = 0.004


## Un hueco del muro: el de un [Passage] o una puerta del jugador.
class Opening:
	extends RefCounted
	var center: float = 0.0
	var size: Vector2 = Vector2.ZERO
	var passage: Passage = null


## Levanta el muro alrededor de sus huecos.
func _ready() -> void:
	var wall_material: StandardMaterial3D = _make_material(color)
	var door_material: StandardMaterial3D = _make_material(player_door_color)
	var cursor: float = -length * 0.5
	for opening: Opening in _collect_openings():
		var left: float = opening.center - opening.size.x * 0.5
		var right: float = opening.center + opening.size.x * 0.5
		if left < cursor - 0.001 or right > length * 0.5 + 0.001:
			push_warning("PassageWall %s: el hueco en x = %.2f se sale del muro o pisa a otro."
				% [name, opening.center])
			continue
		_add_block(cursor, left, 0.0, height, wall_material)
		_add_block(left, right, opening.size.y, height,
			wall_material if opening.passage else door_material)
		cursor = right
		if show_labels:
			_add_label(opening)
	_add_block(cursor, length * 0.5, 0.0, height, wall_material)


## Devuelve los huecos del muro, de los [Passage] hijos y de las puertas, ordenados por X.
func _collect_openings() -> Array[Opening]:
	var openings: Array[Opening] = []
	for child: Node in get_children():
		var passage: Passage = child as Passage
		if not passage:
			continue
		passage.depth = thickness
		var opening: Opening = Opening.new()
		opening.center = passage.position.x
		opening.size = passage.size
		opening.passage = passage
		openings.append(opening)
	for door_center: float in player_doors:
		var door: Opening = Opening.new()
		door.center = door_center
		door.size = player_door_size
		openings.append(door)
	openings.sort_custom(func(a: Opening, b: Opening) -> bool:
		return a.center < b.center)
	return openings


## Añade un bloque de muro con colisión entre [param from_x] y [param to_x].
func _add_block(from_x: float, to_x: float, bottom: float, top: float,
		material: StandardMaterial3D) -> void:
	if to_x - from_x < 0.01 or top - bottom < 0.01:
		return
	var size: Vector3 = Vector3(to_x - from_x, top - bottom, thickness)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(shape)
	body.add_child(mesh_instance)
	add_child(body)
	body.position = Vector3((from_x + to_x) * 0.5, (bottom + top) * 0.5, 0.0)


## Rotula un hueco encima del muro con su nombre, su tamaño y cómo lo cruza el agente.
func _add_label(opening: Opening) -> void:
	var label: Label3D = Label3D.new()
	label.font_size = label_font_size
	label.pixel_size = label_pixel_size
	label.outline_size = 16
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.layers = Statics.BODY_VISUAL_LAYER
	if opening.passage:
		label.text = "%s\n%.2f × %.2f m" % [opening.passage.name, opening.size.x, opening.size.y]
		var navigation: LevelNavigation = null
		if label_agent != &"":
			navigation = LevelNavigation.find(label_agent)
		if navigation:
			var mode: LevelNavigation.PassageMode = navigation.get_passage_mode(opening.size)
			label.text += "\n" + _describe_mode(mode)
			label.modulate = _get_mode_color(mode)
	else:
		label.text = "solo jugador"
		label.modulate = player_door_color.lightened(0.4)
	add_child(label)
	label.position = Vector3(opening.center, height + 0.15, 0.0)


## Devuelve en palabras cómo cruza el agente un hueco.
func _describe_mode(mode: LevelNavigation.PassageMode) -> String:
	match mode:
		LevelNavigation.PassageMode.OPEN:
			return "pasa libre"
		LevelNavigation.PassageMode.WALK:
			return "cruza de pie"
		LevelNavigation.PassageMode.SQUEEZE:
			return "se cuela"
	return "no cabe"


## Devuelve el color del rótulo para [param mode].
func _get_mode_color(mode: LevelNavigation.PassageMode) -> Color:
	match mode:
		LevelNavigation.PassageMode.OPEN:
			return Color(0.6, 1.0, 0.6)
		LevelNavigation.PassageMode.WALK:
			return Color(1.0, 1.0, 1.0)
		LevelNavigation.PassageMode.SQUEEZE:
			return Color(1.0, 0.8, 0.3)
	return Color(1.0, 0.45, 0.4)


## Devuelve un material liso de color [param albedo].
func _make_material(albedo: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = albedo
	return material
