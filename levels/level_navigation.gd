class_name LevelNavigation
extends NavigationRegion3D

## Malla de navegación del nivel, pensada para la IA de los enemigos. Solo la hornea el servidor,
## que es quien decide por ellos, al empezar el nivel y en un hilo: Godot recorre el árbol en el
## hilo principal y hornea en segundo plano. Las fuentes son las colisiones estáticas de los
## nodos del grupo [constant SOURCE_GROUP] y de toda su descendencia, así que el mapa no tiene que
## colgar de este nodo: basta con meter su raíz en el grupo. La [NavigationMesh] de
## [code]level_base.tscn[/code] está ajustada a la cápsula del jugador, y su resolución
## ([code]cell_size[/code], [code]cell_height[/code]) es la de los mapas de navegación del
## proyecto ([code]navigation/3d/default_cell_*[/code]): si no coinciden, Godot avisa por cada
## región, también en el editor. Se accede como [code]LevelNavigation.instance[/code], igual que
## [PlayerSpawner].

## Solo servidor. La malla recién horneada ya está en el mapa de navegación, así que
## [code]NavigationServer3D.map_get_path()[/code] ya la usa. Puede tener 0 polígonos si el mapa
## no aportó suelo horneable.
signal baked(polygon_count: int)

## Grupo de los nodos cuyas colisiones estáticas, con las de su descendencia, forman el suelo
## navegable. El nivel se lo pone a la raíz de su mapa.
const SOURCE_GROUP: StringName = &"navigation_source"

static var instance: LevelNavigation

## Hornea en cuanto el nivel termina de entrar al árbol (solo en el servidor).
@export var bake_on_ready: bool = true

## Solo servidor: [code]true[/code] desde que la última malla horneada está en el mapa.
var is_baked: bool = false

var _waiting_for_map: bool = false


## Se registra como [code]LevelNavigation.instance[/code].
func _enter_tree() -> void:
	instance = self


## Limpia [code]LevelNavigation.instance[/code] si todavía apunta a este nodo.
func _exit_tree() -> void:
	if instance == self:
		instance = null


## Fija de dónde sale la geometría, sin fiarse de la escena, y, si toca, programa el horneado.
## En diferido: el mapa puede ir detrás de este nodo en el árbol y su [code]_ready()[/code] aún
## no habría corrido.
func _ready() -> void:
	if navigation_mesh:
		# Es el contrato con el mapa: si la escena lo cambiara, el mapa dejaría de
		# hornearse sin ningún error.
		navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
		navigation_mesh.geometry_source_group_name = SOURCE_GROUP
	bake_finished.connect(_on_bake_finished)
	NavigationServer3D.map_changed.connect(_on_map_changed)
	if bake_on_ready:
		bake.call_deferred()


## Solo servidor: hornea la malla en un hilo y, al terminar, emite [code]baked[/code]. No hace
## nada si ya está horneando o falta la [NavigationMesh].
func bake() -> void:
	if not is_inside_tree() or not navigation_mesh or is_baking():
		return
	# Sin peer (nivel suelto antes de que lo cree PlayerSpawner) se es el servidor.
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		return
	is_baked = false
	_waiting_for_map = false
	bake_navigation_mesh(true)


## Devuelve cuántos polígonos tiene la malla actual; 0 si no hay malla o aún no se horneó.
func get_polygon_count() -> int:
	if not navigation_mesh:
		return 0
	return navigation_mesh.get_polygon_count()


## Al acabar el horneado queda pendiente de que el mapa de navegación absorba la malla, cosa que
## hace en alguna sincronización posterior: antes, las consultas aún verían la anterior. Una malla
## vacía no tiene nada que esperar.
func _on_bake_finished() -> void:
	if get_polygon_count() == 0:
		_mark_baked()
		return
	_waiting_for_map = true
	_on_map_changed(get_navigation_map())


## Cuando el mapa de este nodo ya responde con los polígonos de la malla nueva, la marca como
## lista. No basta con que cambie: puede avisar de una sincronización que empezó antes de recibir
## la malla, porque el mapa se sincroniza en segundo plano. Con una señal y no con
## [code]await[/code]: si el nivel se libera antes, la conexión muere con él.
## Recibe: [param map] — el mapa de navegación que cambió.
func _on_map_changed(map: RID) -> void:
	if not _waiting_for_map or map != get_navigation_map():
		return
	var vertices: PackedVector3Array = navigation_mesh.get_vertices()
	if vertices.is_empty():
		return
	# Un vértice de la malla nueva solo puede pertenecer a esta región una vez el mapa la tiene.
	var probe: Vector3 = global_transform * vertices[0]
	if NavigationServer3D.map_get_closest_point_owner(map, probe) != get_rid():
		return
	_waiting_for_map = false
	_mark_baked()


## Marca la malla como lista y emite [code]baked[/code].
func _mark_baked() -> void:
	is_baked = true
	baked.emit(get_polygon_count())
