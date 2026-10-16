class_name PlayerBody
extends Node3D

## Contrato del cuerpo visible de un jugador: va en la raíz del envoltorio del modelo
## ([code]cat_body.tscn[/code]) y es lo único que el resto del juego sabe de él. [Player] lo
## guarda al instanciar el [code]body_scene[/code] del rol y le pide el forcejeo;
## [CaptureComponent] le pide los restos cuando una decapitación lo parte. Ni [GrabAttack] ni
## [Player] saben qué cuerpo es: si el [code]body_scene[/code] no es un [PlayerBody] (la cápsula
## de referencia), no hay forcejeo ni restos y todo sigue igual que sin él.
##
## Al entrar al árbol parte su malla skinneada en dos, cabeza y cuerpo, por islas (trozos de
## malla conexos, contando como uno los vértices que comparten posición): una isla va a la
## cabeza si más de la mitad de su peso está en [code]head_bone[/code] o en sus descendientes
## (las orejas). Las islas son cerradas, así que partir por ellas no deja agujeros. Vivo se ven
## las dos mallas sobre el mismo esqueleto y el cuerpo se ve idéntico: son los mismos triángulos
## repartidos. Las mallas partidas se calculan una vez por malla de origen y las comparten
## todos los cuerpos que la usan.
##
## Los nodos de [code]head_remains_only[/code] y [code]body_remains_only[/code] (el muñón, por
## ejemplo) se ocultan en vida y solo se ven en su pieza de los restos: añadirlos es cosa de la
## escena, sin código.

## Máximo de pesos por vértice de una malla de Godot ([code]ARRAY_FLAG_USE_8_BONE_WEIGHTS[/code]):
## el paso fijo con el que [Piece] los guarda.
const MAX_INFLUENCES: int = 8

## Restos de un cuerpo partido, recién hechos por [code]create_remains()[/code]: dos copias del
## envoltorio fuera del árbol, con la pose congelada y sin animación. La raíz de cada copia
## ocupa el lugar de este nodo: todo va en el espacio del envoltorio.
class Remains:
	## Copia que solo muestra la cabeza y los nodos de [code]head_remains_only[/code].
	var head: Node3D
	## Copia que solo muestra el cuerpo y los nodos de [code]body_remains_only[/code].
	var body: Node3D
	## Caja de la geometría posada del cuerpo, en el espacio del envoltorio.
	var body_bounds: AABB


## Una pieza de la partición: su malla y, para posar sus vértices en la CPU (la caja de los
## restos), la posición de cada vértice que usa con sus binds del [Skin] y pesos, a paso
## [constant MAX_INFLUENCES].
class Piece:
	var mesh: ArrayMesh = ArrayMesh.new()
	var triangles: int = 0
	var positions: PackedVector3Array = PackedVector3Array()
	var binds: PackedInt32Array = PackedInt32Array()
	var weights: PackedFloat32Array = PackedFloat32Array()


## La partición de una malla de origen, compartida por todos los cuerpos que la usan.
class MeshSplit:
	var head: Piece = Piece.new()
	var body: Piece = Piece.new()


## Conjuntos disjuntos sobre índices de vértice, con compresión de caminos.
class UnionFind:
	var parents: PackedInt32Array = PackedInt32Array()

	func _init(size: int) -> void:
		parents.resize(size)
		for i: int in size:
			parents[i] = i

	## Devuelve el representante del conjunto de [param index].
	func find(index: int) -> int:
		var root: int = index
		while parents[root] != root:
			root = parents[root]
		while parents[index] != root:
			var next: int = parents[index]
			parents[index] = root
			index = next
		return root

	## Junta los conjuntos de [param a] y [param b].
	func union(a: int, b: int) -> void:
		var root_a: int = find(a)
		var root_b: int = find(b)
		if root_a != root_b:
			parents[root_b] = root_a


@export var skeleton: Skeleton3D
## Malla skinneada que se parte. Tras partirla muestra solo el cuerpo; la cabeza va en un
## [MeshInstance3D] hermano creado al entrar al árbol.
@export var skinned_mesh: MeshInstance3D
@export var animation_tree: AnimationTree
## Hueso de la cabeza: ella y sus descendientes se separan del cuerpo.
@export var head_bone: StringName = &"cabeza"

@export_group("Estados")
## Ruta de los parámetros de la máquina de estados con la locomoción y el forcejeo:
## [code]parameters[/code] si es la raíz del árbol.
@export var state_machine_path: StringName = &"parameters"
@export var locomotion_state: StringName = &"locomotion"
## Estado mientras algo lo tiene atrapado.
@export var struggle_state: StringName = &"forcejeo"

@export_group("Restos")
## Nodos que solo se ven en la pieza de la cabeza de los restos (el muñón del cuello).
@export var head_remains_only: Array[Node3D] = []
## Nodos que solo se ven en la pieza del cuerpo de los restos (el muñón del tronco).
@export var body_remains_only: Array[Node3D] = []
## Radio de la esfera de la cabeza, centrada en los ojos. Tiene que dejar la cámara del dueño,
## que va en ese centro, por encima del suelo.
@export var head_radius: float = 0.25
@export var head_mass: float = 3.0
@export var body_mass: float = 15.0
## Freno del giro de la cabeza. La esfera rodaría como una bola por todo el nivel; una cabeza de
## verdad (orejas, morro) se para enseguida.
@export var head_angular_damp: float = 4.0

## Particiones ya hechas, por malla de origen, [Skin] y hueso de la cabeza.
static var _split_cache: Dictionary[String, MeshSplit] = {}

## Muestra la cabeza en vida; [code]null[/code] si no se pudo partir.
var head_mesh: MeshInstance3D = null
## Muestra el cuerpo en vida (es [code]skinned_mesh[/code]); [code]null[/code] si no se pudo
## partir.
var body_mesh: MeshInstance3D = null

var _split: MeshSplit = null
var _struggling: bool = false


## Parte la malla y oculta los nodos que solo existen en los restos. Corre al añadirse bajo
## [code]Player.body[/code], antes de que [Player] fuerce la capa visual de cuerpos: así esa capa
## llega también a la malla nueva de la cabeza.
func _ready() -> void:
	for node: Node3D in head_remains_only + body_remains_only:
		if node:
			node.hide()
	_split_mesh()


## Devuelve [code]true[/code] si la malla se partió y puede dar restos.
func can_create_remains() -> bool:
	return _split != null


## Devuelve la partición en uso, o [code]null[/code]. Compartida: no modificarla.
func get_split() -> MeshSplit:
	return _split


## Devuelve [code]true[/code] mientras está en el estado de forcejeo.
func is_struggling() -> bool:
	return _struggling


## Viaja al estado de forcejeo o vuelve a la locomoción. Con el árbol apagado (el cuerpo del
## dueño, oculto en primera persona) el viaje queda pendiente hasta que vuelva a procesar.
## Recibe: [param enabled] — [code]true[/code] mientras algo lo tiene atrapado.
func set_struggling(enabled: bool) -> void:
	_struggling = enabled
	var playback: AnimationNodeStateMachinePlayback = _get_playback()
	if playback:
		playback.travel(struggle_state if enabled else locomotion_state)


## Copia el cuerpo en dos piezas, cabeza y cuerpo, con la pose actual del esqueleto congelada.
## Solo se copia la geometría (los hijos [Node3D]): árbol, reproductor y
## [LocomotionAnimator] cuelgan como [Node] y se quedan fuera, y cualquier [AnimationMixer] o
## [SkeletonModifier3D] más abajo se quita, para que nada mueva la pose. El cuerpo vivo no se
## toca: ocultarlo es cosa de quien llama.
## Devuelve: los restos, fuera del árbol, o [code]null[/code] si la malla no se pudo partir.
func create_remains() -> Remains:
	if not _split:
		return null
	var remains: Remains = Remains.new()
	remains.head = _copy_piece(true)
	remains.body = _copy_piece(false)
	remains.body_bounds = _compute_posed_bounds(_split.body)
	return remains


## Parte [code]skinned_mesh[/code] (o toma la partición de la caché), le deja el cuerpo y crea
## al lado un [MeshInstance3D] con la cabeza, copia del original (capas, materiales, skin y
## esqueleto). Si falta algo o no sale una cabeza y un cuerpo, avisa y deja la malla entera.
func _split_mesh() -> void:
	var source: ArrayMesh = skinned_mesh.mesh as ArrayMesh if skinned_mesh else null
	if not skeleton or not source:
		push_warning("PlayerBody %s: sin esqueleto o sin ArrayMesh, no se parte" % name)
		return
	var head_index: int = skeleton.find_bone(head_bone)
	if head_index < 0:
		push_warning("PlayerBody %s: el esqueleto no tiene %s" % [name, head_bone])
		return
	var key: String = "%d/%d/%s" % [source.get_instance_id(),
		skinned_mesh.skin.get_instance_id() if skinned_mesh.skin else 0, head_bone]
	var split: MeshSplit = _split_cache.get(key, null)
	if not split:
		split = _build_split(source, _get_head_binds(head_index))
		if split.head.triangles == 0 or split.body.triangles == 0:
			push_warning("PlayerBody %s: la malla no se separa en cabeza y cuerpo" % name)
			return
		_split_cache[key] = split
	_split = split

	head_mesh = skinned_mesh.duplicate() as MeshInstance3D
	head_mesh.name = "%sCabeza" % skinned_mesh.name
	head_mesh.mesh = split.head.mesh
	skinned_mesh.add_sibling(head_mesh)
	skinned_mesh.mesh = split.body.mesh
	body_mesh = skinned_mesh


## Devuelve, por cada bind del [Skin] (o hueso, sin skin), si deforma con la cabeza: si su hueso
## es [param head_index] o desciende de él.
func _get_head_binds(head_index: int) -> Array[bool]:
	var head_bones: Array[bool] = []
	head_bones.resize(skeleton.get_bone_count())
	for bone: int in skeleton.get_bone_count():
		var current: int = bone
		while current >= 0 and current != head_index:
			current = skeleton.get_bone_parent(current)
		head_bones[bone] = current == head_index
	var skin: Skin = skinned_mesh.skin
	if not skin:
		return head_bones
	var binds: Array[bool] = []
	binds.resize(skin.get_bind_count())
	for bind: int in skin.get_bind_count():
		var bone: int = _get_bind_bone(skin, bind)
		binds[bind] = bone >= 0 and head_bones[bone]
	return binds


## Devuelve el hueso del esqueleto al que apunta [param bind]: por nombre si lo tiene, si no
## por índice.
func _get_bind_bone(skin: Skin, bind: int) -> int:
	var bind_name: StringName = skin.get_bind_name(bind)
	if bind_name != &"":
		return skeleton.find_bone(bind_name)
	return skin.get_bind_bone(bind)


## Parte cada superficie de triángulos de [param source] por islas y reparte sus triángulos
## entre las dos piezas. Las superficies que no son de triángulos van enteras al cuerpo.
## Recibe: [param head_binds] — por bind, si deforma con la cabeza.
## Devuelve: la partición; una pieza sin triángulos queda con la malla vacía.
static func _build_split(source: ArrayMesh, head_binds: Array[bool]) -> MeshSplit:
	var split: MeshSplit = MeshSplit.new()
	for surface: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var format: int = source.surface_get_format(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		else:
			indices.resize(positions.size())
			for i: int in positions.size():
				indices[i] = i
		var head_indices: PackedInt32Array = PackedInt32Array()
		var body_indices: PackedInt32Array = indices
		if source.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			var islands: UnionFind = _find_islands(positions, indices)
			var head_islands: Dictionary[int, bool] = _find_head_islands(arrays, format, islands,
				head_binds)
			body_indices = PackedInt32Array()
			for triangle: int in range(0, indices.size() - 2, 3):
				var is_head: bool = head_islands.has(islands.find(indices[triangle]))
				for corner: int in 3:
					if is_head:
						head_indices.append(indices[triangle + corner])
					else:
						body_indices.append(indices[triangle + corner])
		_add_piece_surface(split.head, source, surface, arrays, format, head_indices)
		_add_piece_surface(split.body, source, surface, arrays, format, body_indices)
	return split


## Devuelve las islas de una superficie: vértices unidos por triángulos o por compartir
## posición (la malla duplica los vértices de las costuras de normales y UV).
static func _find_islands(positions: PackedVector3Array, indices: PackedInt32Array) -> UnionFind:
	var islands: UnionFind = UnionFind.new(positions.size())
	var first_at: Dictionary[Vector3, int] = {}
	for vertex: int in positions.size():
		var point: Vector3 = positions[vertex]
		if first_at.has(point):
			islands.union(first_at[point], vertex)
		else:
			first_at[point] = vertex
	for triangle: int in range(0, indices.size() - 2, 3):
		islands.union(indices[triangle], indices[triangle + 1])
		islands.union(indices[triangle], indices[triangle + 2])
	return islands


## Devuelve los representantes de las islas que van a la cabeza: más de la mitad de su peso
## total en binds de la cabeza.
## Recibe: [param arrays] y [param format] — los de la superficie; [param islands] — sus islas;
## [param head_binds] — por bind, si deforma con la cabeza.
static func _find_head_islands(arrays: Array, format: int, islands: UnionFind,
		head_binds: Array[bool]) -> Dictionary[int, bool]:
	var head_islands: Dictionary[int, bool] = {}
	if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
		return head_islands
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride: int = _get_influences(format)
	var head_weight: Dictionary[int, float] = {}
	var total_weight: Dictionary[int, float] = {}
	for vertex: int in positions.size():
		var island: int = islands.find(vertex)
		for k: int in stride:
			var weight: float = weights[vertex * stride + k]
			if weight <= 0.0:
				continue
			total_weight[island] = total_weight.get(island, 0.0) + weight
			var bind: int = bones[vertex * stride + k]
			if bind >= 0 and bind < head_binds.size() and head_binds[bind]:
				head_weight[island] = head_weight.get(island, 0.0) + weight
	for island: int in head_weight:
		if head_weight[island] > 0.5 * total_weight[island]:
			head_islands[island] = true
	return head_islands


## Añade a [param piece] una copia de la superficie [param surface] de [param source] con solo
## [param indices]: los arrays de vértices enteros (sin remapear), el mismo formato y el mismo
## material. Apunta los vértices que usa con sus pesos. No añade nada si no hay triángulos.
static func _add_piece_surface(piece: Piece, source: ArrayMesh, surface: int, arrays: Array,
		format: int, indices: PackedInt32Array) -> void:
	if indices.is_empty():
		return
	var piece_arrays: Array = arrays.duplicate()
	piece_arrays[Mesh.ARRAY_INDEX] = indices
	var blend_shapes: Array[Array] = []
	if source.get_blend_shape_count() > 0:
		if piece.mesh.get_blend_shape_count() == 0:
			piece.mesh.blend_shape_mode = source.blend_shape_mode
			for shape: int in source.get_blend_shape_count():
				piece.mesh.add_blend_shape(source.get_blend_shape_name(shape))
		blend_shapes = source.surface_get_blend_shape_arrays(surface)
	# Fuera los bits de qué arrays hay (los deduce de piece_arrays): quedan los flags de
	# compresión, de 8 pesos y de formato de los canales custom.
	var flags: int = format & ~((1 << Mesh.ARRAY_MAX) - 1)
	piece.mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), piece_arrays,
		blend_shapes, {}, flags)
	var new_surface: int = piece.mesh.get_surface_count() - 1
	piece.mesh.surface_set_material(new_surface, source.surface_get_material(surface))
	piece.mesh.surface_set_name(new_surface, source.surface_get_name(surface))
	@warning_ignore("integer_division")
	piece.triangles += indices.size() / 3
	_collect_vertices(piece, arrays, format, indices)


## Apunta en [param piece] cada vértice distinto de [param indices] con sus binds y pesos, a
## paso [constant MAX_INFLUENCES] (los huecos con peso 0).
static func _collect_vertices(piece: Piece, arrays: Array, format: int,
		indices: PackedInt32Array) -> void:
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var has_weights: bool = arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null
	var bones: PackedInt32Array = PackedInt32Array()
	var weights: PackedFloat32Array = PackedFloat32Array()
	if has_weights:
		bones = arrays[Mesh.ARRAY_BONES]
		weights = arrays[Mesh.ARRAY_WEIGHTS]
	var stride: int = _get_influences(format)
	var seen: Dictionary[int, bool] = {}
	for vertex: int in indices:
		if seen.has(vertex):
			continue
		seen[vertex] = true
		piece.positions.append(positions[vertex])
		for k: int in MAX_INFLUENCES:
			var used: bool = has_weights and k < stride
			piece.binds.append(bones[vertex * stride + k] if used else 0)
			piece.weights.append(weights[vertex * stride + k] if used else 0.0)


## Devuelve los pesos por vértice de una superficie con [param format].
static func _get_influences(format: int) -> int:
	return 8 if format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4


## Copia la geometría del envoltorio en una raíz nueva que solo muestra la pieza pedida, con la
## pose actual del esqueleto. Duplica sin instanciar las escenas hijas (el glb): así copia
## también los nodos creados en ejecución, como la malla de la cabeza.
## Recibe: [param is_head] — [code]true[/code] para la pieza de la cabeza.
## Devuelve: la copia, fuera del árbol.
func _copy_piece(is_head: bool) -> Node3D:
	var copy: Node3D = Node3D.new()
	copy.name = "RestosCabeza" if is_head else "RestosCuerpo"
	var flags: int = Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS
	for child: Node in get_children():
		var geometry: Node3D = child as Node3D
		if geometry:
			copy.add_child(geometry.duplicate(flags))
	_strip_animation(copy)

	_set_copy_visible(copy, head_mesh, is_head)
	_set_copy_visible(copy, body_mesh, not is_head)
	for node: Node3D in head_remains_only:
		_set_copy_visible(copy, node, is_head)
	for node: Node3D in body_remains_only:
		_set_copy_visible(copy, node, not is_head)

	var skeleton_copy: Skeleton3D = copy.get_node_or_null(get_path_to(skeleton)) as Skeleton3D
	if skeleton_copy:
		for bone: int in skeleton.get_bone_count():
			skeleton_copy.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone))
			skeleton_copy.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone))
			skeleton_copy.set_bone_pose_scale(bone, skeleton.get_bone_pose_scale(bone))
	return copy


## Quita de [param node] y sus descendientes todo lo que movería la pose congelada.
func _strip_animation(node: Node) -> void:
	for child: Node in node.get_children():
		if child is AnimationMixer or child is SkeletonModifier3D or child is LocomotionAnimator:
			node.remove_child(child)
			child.free()
		else:
			_strip_animation(child)


## Muestra u oculta en [param copy] el nodo que corresponde a [param original], buscado por su
## ruta desde este envoltorio.
func _set_copy_visible(copy: Node3D, original: Node3D, shown: bool) -> void:
	if not original:
		return
	var node: Node3D = copy.get_node_or_null(get_path_to(original)) as Node3D
	if node:
		node.visible = shown


## Devuelve la caja de [param piece] con la pose actual: cada vértice se posa en la CPU como lo
## hace el skinning (suma de bind por peso) y se lleva al espacio del envoltorio.
func _compute_posed_bounds(piece: Piece) -> AABB:
	var to_body: Transform3D = _get_transform_to_self(skinned_mesh)
	var bind_poses: Array[Transform3D] = _get_posed_binds()
	var bounds: AABB = AABB()
	for vertex: int in piece.positions.size():
		var rest: Vector3 = piece.positions[vertex]
		var posed: Vector3 = Vector3.ZERO
		var total: float = 0.0
		for k: int in MAX_INFLUENCES:
			var weight: float = piece.weights[vertex * MAX_INFLUENCES + k]
			var bind: int = piece.binds[vertex * MAX_INFLUENCES + k]
			if weight <= 0.0 or bind < 0 or bind >= bind_poses.size():
				continue
			posed += (bind_poses[bind] * rest) * weight
			total += weight
		var point: Vector3 = to_body * (posed / total if total > 0.0 else rest)
		bounds = AABB(point, Vector3.ZERO) if vertex == 0 else bounds.expand(point)
	return bounds


## Devuelve, por bind del [Skin] (o hueso, sin skin), la transformación de skinning con la pose
## actual: la del hueso en el esqueleto por la inversa de su reposo.
func _get_posed_binds() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	var skin: Skin = skinned_mesh.skin
	if not skin:
		for bone: int in skeleton.get_bone_count():
			poses.append(skeleton.get_bone_global_pose(bone) \
				* skeleton.get_bone_global_rest(bone).affine_inverse())
		return poses
	for bind: int in skin.get_bind_count():
		var bone: int = _get_bind_bone(skin, bind)
		poses.append(skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) if bone >= 0 \
			else Transform3D.IDENTITY)
	return poses


## Devuelve el transform de [param node] en el espacio de este envoltorio, recorriendo la cadena
## de padres (vale también fuera del árbol).
func _get_transform_to_self(node: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current and current != self:
		var current_3d: Node3D = current as Node3D
		if current_3d:
			result = current_3d.transform * result
		current = current.get_parent()
	return result


## Devuelve la reproducción de la máquina de estados del forcejeo, o [code]null[/code].
func _get_playback() -> AnimationNodeStateMachinePlayback:
	if not animation_tree:
		return null
	return animation_tree.get(StringName("%s/playback" % state_machine_path)) \
		as AnimationNodeStateMachinePlayback
