class_name LevelNavigation
extends NavigationRegion3D

## Malla de navegación del nivel para un tamaño de agente, con enlaces por los huecos del mapa.

signal baked(polygon_count: int)

const SOURCE_GROUP: StringName = &"navigation_source"

const PLAYER_AGENT: StringName = &"jugador"
const LARGE_AGENT: StringName = &"pesadilla"

const WALK_LAYER: int = 1
const SQUEEZE_LAYER: int = 2
const LINK_SNAP: float = 0.4
const LINK_HEIGHT_SNAP: float = 1.0
const LINK_STEP: float = 0.25
const OPEN_MARGIN: float = 0.5
const LINK_WAIT_TIMEOUT: float = 1.0
const MESH_RESEND_FRAMES: int = 30

enum PassageMode {
	NONE,
	SQUEEZE,
	WALK,
	OPEN,
}


## El enlace de navegación de un [Passage] para este agente.
class PassageLink:
	extends RefCounted
	var passage: Passage
	var rid: RID = RID()
	var squeezes: bool = false
	var reach: PackedFloat32Array = PackedFloat32Array()
	var ends: PackedVector3Array = PackedVector3Array()

static var _regions: Array[LevelNavigation] = []

## Tamaño de agente para el que se hornea esta malla.
@export var agent: StringName = PLAYER_AGENT
## Si usa un mapa de navegación propio en vez del del mundo.
@export var dedicated_map: bool = false
## Si hornea en cuanto el nivel entra al árbol, solo en el servidor.
@export var bake_on_ready: bool = true

@export_group("Huecos")
## Si tiende enlaces por los [Passage] del nivel.
@export var uses_passages: bool = false
## Tamaños de hueco (ancho, alto), en metros, por los que este agente pasa colándose.
@export var passage_fits: Array[Vector2] = []
## Ancho y alto, en metros, desde los que cruza un hueco de pie.
@export var passage_free_size: Vector2 = Vector2(1.7, 1.95)
## Metros desde el muro, a cada lado, donde empieza y termina el cruce.
@export var passage_approach: float = 3.0
## Metros de camino que cuesta de más tomar un hueco por el que hay que colarse.
@export var squeeze_cost: float = 13.0

var is_baked: bool = false

var _waiting_for_map: bool = false
var _own_map: RID = RID()
var _links: Dictionary[RID, PassageLink] = {}
var _waiting_for_links: bool = false
var _links_iteration: int = 0
var _links_wait_id: int = 0
var _map_wait_frames: int = 0


## Devuelve la malla del nivel para [param wanted_agent], o [code]null[/code].
static func find(wanted_agent: StringName) -> LevelNavigation:
	for region: LevelNavigation in _regions:
		if is_instance_valid(region) and region.agent == wanted_agent:
			return region
	return null


## Se registra y, si lleva mapa propio, lo crea y se muda a él.
func _enter_tree() -> void:
	if not _regions.has(self):
		_regions.append(self)
	if dedicated_map and not _own_map.is_valid():
		_own_map = NavigationServer3D.map_create()
		if navigation_mesh:
			NavigationServer3D.map_set_cell_size(_own_map, navigation_mesh.cell_size)
			NavigationServer3D.map_set_cell_height(_own_map, navigation_mesh.cell_height)
		NavigationServer3D.map_set_active(_own_map, true)
		set_navigation_map(_own_map)


## Se borra del registro y libera sus enlaces y su mapa propio.
func _exit_tree() -> void:
	_regions.erase(self)
	_free_passage_links()
	if _own_map.is_valid():
		NavigationServer3D.free_rid(_own_map)
		_own_map = RID()


## Fija de dónde sale la geometría y programa el horneado si toca.
func _ready() -> void:
	if navigation_mesh:
		navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
		navigation_mesh.geometry_source_group_name = SOURCE_GROUP
	set_physics_process(false)
	bake_finished.connect(_on_bake_finished)
	NavigationServer3D.map_changed.connect(_on_map_changed)
	if bake_on_ready:
		bake.call_deferred()


## Comprueba cada frame si el mapa ya absorbió la malla y los enlaces.
func _physics_process(_delta: float) -> void:
	if not _waiting_for_map and not _waiting_for_links:
		set_physics_process(false)
		return
	if _waiting_for_map:
		_map_wait_frames += 1
		if _map_wait_frames % MESH_RESEND_FRAMES == 0:
			NavigationServer3D.region_set_navigation_mesh(get_rid(), navigation_mesh)
	_on_map_changed(get_navigation_map())


## Hornea la malla en un hilo, solo en el servidor.
func bake() -> void:
	if not is_inside_tree() or not navigation_mesh or is_baking():
		return
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		return
	is_baked = false
	_waiting_for_map = false
	_waiting_for_links = false
	_free_passage_links()
	bake_navigation_mesh(true)


## Devuelve cuántos polígonos tiene la malla actual.
func get_polygon_count() -> int:
	if not navigation_mesh:
		return 0
	return navigation_mesh.get_polygon_count()


## Devuelve cómo cruza este agente un hueco de [param size] (ancho, alto).
func get_passage_mode(size: Vector2) -> PassageMode:
	if not navigation_mesh:
		return PassageMode.NONE
	if size.x >= navigation_mesh.agent_radius * 2.0 + OPEN_MARGIN \
			and size.y >= navigation_mesh.agent_height:
		return PassageMode.OPEN
	if size.x >= passage_free_size.x and size.y >= passage_free_size.y:
		return PassageMode.WALK
	for fit: Vector2 in passage_fits:
		if size.x >= fit.x - 0.001 and size.y >= fit.y - 0.001:
			return PassageMode.SQUEEZE
	return PassageMode.NONE


## Devuelve el enlace de hueco con el RID [param link], o [code]null[/code].
func get_passage_link(link: RID) -> PassageLink:
	return _links.get(link)


## Devuelve los enlaces de hueco tendidos.
func get_passage_links() -> Array[PassageLink]:
	var links: Array[PassageLink] = []
	links.assign(_links.values())
	return links


## Al acabar el horneado, espera a que el mapa absorba la malla.
func _on_bake_finished() -> void:
	if get_polygon_count() == 0:
		_mark_baked()
		return
	_waiting_for_map = true
	_map_wait_frames = 0
	set_physics_process(true)
	_on_map_changed(get_navigation_map())


## Marca la malla como lista cuando el mapa ya responde con ella, y tiende los enlaces.
func _on_map_changed(map: RID) -> void:
	if map != get_navigation_map():
		return
	if _waiting_for_links:
		_check_links_ready()
		return
	if not _waiting_for_map:
		return
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	var vertices: PackedVector3Array = navigation_mesh.get_vertices()
	if vertices.is_empty():
		return
	var probe: Vector3 = global_transform * vertices[0]
	if NavigationServer3D.map_get_closest_point_owner(map, probe) != get_rid():
		return
	_waiting_for_map = false
	_build_passage_links()
	if _links.is_empty():
		_mark_baked()
		return
	_waiting_for_links = true
	_links_iteration = NavigationServer3D.map_get_iteration_id(map)
	_links_wait_id += 1
	get_tree().create_timer(LINK_WAIT_TIMEOUT).timeout.connect(
		_on_link_wait_timeout.bind(_links_wait_id))


## Da la malla por lista cuando el mapa ya conecta los enlaces.
func _check_links_ready() -> void:
	var iteration: int = NavigationServer3D.map_get_iteration_id(get_navigation_map())
	if iteration == _links_iteration:
		return
	if iteration >= _links_iteration + 2 or _is_any_link_connected():
		_waiting_for_links = false
		_mark_baked()


## Devuelve [code]true[/code] si el camino entre los extremos de algún enlace ya lo toma.
func _is_any_link_connected() -> bool:
	for link: PassageLink in _links.values():
		var query: NavigationPathQueryParameters3D = NavigationPathQueryParameters3D.new()
		query.map = get_navigation_map()
		query.start_position = link.ends[0]
		query.target_position = link.ends[1]
		query.navigation_layers = WALK_LAYER | SQUEEZE_LAYER
		query.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES
		var result: NavigationPathQueryResult3D = NavigationPathQueryResult3D.new()
		NavigationServer3D.query_path(query, result)
		if result.path_types.has(NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK):
			return true
	return false


## Da la malla por lista si se agota la espera de los enlaces.
func _on_link_wait_timeout(wait_id: int) -> void:
	if not _waiting_for_links or wait_id != _links_wait_id:
		return
	_waiting_for_links = false
	_mark_baked()


## Marca la malla como lista y emite [code]baked[/code].
func _mark_baked() -> void:
	is_baked = true
	baked.emit(get_polygon_count())


## Tiende un enlace por cada [Passage] del nivel que su agente cruza de pie o colándose.
func _build_passage_links() -> void:
	_free_passage_links()
	if not uses_passages or not is_inside_tree() or get_polygon_count() == 0:
		return
	var map: RID = get_navigation_map()
	for node: Node in get_tree().get_nodes_in_group(Passage.GROUP):
		var passage: Passage = node as Passage
		if not passage:
			continue
		var mode: PassageMode = get_passage_mode(passage.size)
		if mode != PassageMode.SQUEEZE and mode != PassageMode.WALK:
			continue
		var link: PassageLink = PassageLink.new()
		link.passage = passage
		link.squeezes = mode == PassageMode.SQUEEZE
		for side: float in [-1.0, 1.0]:
			var along: float = _find_link_reach(map, passage, side)
			if along < 0.0:
				break
			link.reach.append(along)
			link.ends.append(NavigationServer3D.map_get_closest_point(
				map, passage.get_axis_point(side * along)))
		if link.ends.size() < 2:
			continue
		link.rid = NavigationServer3D.link_create()
		NavigationServer3D.link_set_map(link.rid, map)
		NavigationServer3D.link_set_owner_id(link.rid, passage.get_instance_id())
		NavigationServer3D.link_set_bidirectional(link.rid, true)
		NavigationServer3D.link_set_navigation_layers(link.rid,
			SQUEEZE_LAYER if link.squeezes else WALK_LAYER)
		NavigationServer3D.link_set_enter_cost(link.rid, squeeze_cost if link.squeezes else 0.0)
		NavigationServer3D.link_set_start_position(link.rid, link.ends[0])
		NavigationServer3D.link_set_end_position(link.rid, link.ends[1])
		NavigationServer3D.link_set_enabled(link.rid, true)
		_links[link.rid] = link


## Devuelve a qué distancia del muro de [param passage] empieza el cruce por el lado [param side].
func _find_link_reach(map: RID, passage: Passage, side: float) -> float:
	var nearest: float = passage.depth * 0.5 + navigation_mesh.agent_radius
	var along: float = maxf(passage_approach, nearest)
	while along >= nearest - 0.001:
		var wanted: Vector3 = passage.get_axis_point(side * along)
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, wanted)
		if Vector2(closest.x - wanted.x, closest.z - wanted.z).length() <= LINK_SNAP \
				and absf(closest.y - wanted.y) <= LINK_HEIGHT_SNAP:
			return along
		along -= LINK_STEP
	return -1.0


## Quita del servidor de navegación los enlaces tendidos.
func _free_passage_links() -> void:
	for link: RID in _links:
		if link.is_valid():
			NavigationServer3D.free_rid(link)
	_links.clear()
