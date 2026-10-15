class_name CombatDebugOverlay
extends Node3D

## Visuales del modo debug de combate (F9). Lo crea [code]Debug[/code] al encender el modo y lo
## libera al apagarlo, así que apagado no queda nada instanciado ni procesándose. Pinta las
## [Hitbox] de todos los enemigos, etéreos incluidos, con un color por zona, y los disparos que
## difunde el servidor: trazo rojo, marcador en el final, etiqueta con zona y daño y destello en
## la hitbox tocada. El rayo azul de apuntado no vive aquí: lo dibuja [FirearmDebugAim].
## Todo es local a cada peer, nunca se replica y no tiene colisión. Va en la capa visual 4, que
## ven los tres roles (el vidente en su segunda pasada), y sin prueba de profundidad: se ve a
## través de las paredes y del modelo. Nunca en la capa 1, de la que el vidente saca su
## profundidad y su eco.

## Grupo de cada [CombatDebugOverlay.HitboxVisual]; con él se borran todos al apagar.
const VISUAL_GROUP: StringName = &"combat_debug_visual"
## Es una máscara: la capa visual 4, la única que ven los tres roles.
const VISUAL_LAYER: int = Statics.BODY_VISUAL_LAYER
## Trazos de disparo a la vez como mucho; al pasarse se borra el más viejo.
const MAX_TRACES: int = 24
## Segundos que un trazo se queda entero antes de empezar a fundirse.
const TRACE_HOLD_SECONDS: float = 1.0
## Segundos que tarda un trazo en fundirse del todo; luego se libera.
const TRACE_FADE_SECONDS: float = 0.5
const HITBOX_ALPHA: float = 0.3
const FLASH_ALPHA: float = 0.85
const FLASH_SECONDS: float = 0.3

const SHOT_COLOR: Color = Color(1.0, 0.15, 0.1)
const AIM_COLOR: Color = Color(0.25, 0.55, 1.0)
const BODY_COLOR: Color = Color(0.25, 0.95, 0.35)
const HEAD_COLOR: Color = Color(1.0, 0.88, 0.15)
const WEAK_SPOT_COLOR: Color = Color(1.0, 0.25, 0.95)

## Medio ancho angular de los rayos, en radianes (ver [code]debug_beam.gdshader[/code]): unos 3 px
## a 720 de alto. El de apuntado, algo más fino para no tapar la mira.
const SHOT_HALF_WIDTH: float = 0.003
const AIM_HALF_WIDTH: float = 0.002
## Metros entre anillos de un rayo. El shader calcula el grosor en cada vértice e interpola entre
## ellos: con vértices solo en los extremos, un rayo largo que pasa cerca de la cámara engorda
## justo ahí. Con un anillo por metro el error es pequeño a partir de 1 m de distancia.
const BEAM_RING_SPACING: float = 1.0
const MAX_BEAM_RINGS: int = 64
## Radio de los marcadores como si estuvieran a 1 m: su material los dibuja siempre a ese tamaño.
const IMPACT_MARKER_RADIUS: float = 0.012
const AIM_MARKER_RADIUS: float = 0.007

## Orden de dibujo: sin prueba de profundidad, lo que tenga más prioridad queda encima.
const HITBOX_PRIORITY: int = 0
const BEAM_PRIORITY: int = 1
const MARKER_PRIORITY: int = 2
const LABEL_PRIORITY: int = 4

const BEAM_SHADER: Shader = preload("res://scripts/debug/debug_beam.gdshader")

## Ids de instancia de las hitboxes que esperan su visual hasta el final del frame. Ids y no
## referencias: una hitbox puede liberarse antes (la del cubo al cargar un modelo), y leer una
## referencia liberada de un array tipado es un error.
var _pending_hitboxes: Array[int] = []


## Volumen de una [Hitbox] pintado con el color de su zona. Cuelga como hijo interno de su
## [CollisionShape3D], así que sigue a la hitbox (y al hueso) sin procesar nada cada frame, se
## oculta con el modelo cuando el enemigo se retira y no aparece en [code]get_children()[/code]:
## [code]Statics.force_visual_layer()[/code] no lo mueve de capa.
class HitboxVisual extends MeshInstance3D:
	## Zona de la hitbox que representa, un valor de [enum Statics.HitZone].
	var zone: int = Statics.HitZone.CUERPO

	var _material: StandardMaterial3D = null
	var _flash: Tween = null


	## Recibe: [param shape] — forma de la [CollisionShape3D]; [param hitbox_zone] — su zona.
	func _init(shape: Shape3D, hitbox_zone: int) -> void:
		name = "CombatDebugVisual"
		zone = hitbox_zone
		mesh = CombatDebugOverlay.make_shape_mesh(shape)
		_material = CombatDebugOverlay.make_flat_material(get_resting_color(),
			CombatDebugOverlay.HITBOX_PRIORITY)
		material_override = _material
		CombatDebugOverlay.prepare_geometry(self)
		add_to_group(CombatDebugOverlay.VISUAL_GROUP)


	## Devuelve el color actual, con el destello si está en curso.
	func get_color() -> Color:
		return _material.albedo_color


	## Devuelve el color de su zona con la transparencia de reposo.
	func get_resting_color() -> Color:
		var color: Color = CombatDebugOverlay.get_zone_color(zone)
		color.a = CombatDebugOverlay.HITBOX_ALPHA
		return color


	## Destello breve: se aclara y vuelve a su color en [constant FLASH_SECONDS] s. Un destello
	## nuevo corta el anterior.
	func flash() -> void:
		if _flash:
			_flash.kill()
		var bright: Color = get_resting_color().lightened(0.6)
		bright.a = CombatDebugOverlay.FLASH_ALPHA
		_material.albedo_color = bright
		_flash = create_tween()
		_flash.tween_property(_material, ^"albedo_color", get_resting_color(),
			CombatDebugOverlay.FLASH_SECONDS)


## Trazo de un disparo resuelto por el servidor: rayo rojo del origen al final, marcador en el
## final con el color de la zona golpeada (rojo si no dio en ninguna hitbox) y, si dio en una,
## una etiqueta con la zona y el daño. Se queda [constant TRACE_HOLD_SECONDS] s, se funde en
## [constant TRACE_FADE_SECONDS] s y se libera solo. Incluye la dispersión: es el tiro real.
class ShotTrace extends Node3D:
	var origin: Vector3 = Vector3.ZERO
	## Donde acabó el tiro: el impacto o el final del alcance.
	var end: Vector3 = Vector3.ZERO
	## Zona de la hitbox golpeada, o [constant Firearm.NO_ZONE] si no dio en ninguna.
	var zone: int = Firearm.NO_ZONE
	## Ruta absoluta de la hitbox golpeada; vacía si no dio en ninguna.
	var hitbox_path: NodePath = NodePath()
	## Daño que hizo el tiro; [code]0[/code] si no hizo ninguno.
	var damage: float = 0.0

	var _beam_material: ShaderMaterial = null
	var _marker_material: StandardMaterial3D = null
	var _label: Label3D = null


	## Recibe lo que difunde [code]Firearm._play_fire_effects()[/code]: [param shot_origin],
	## [param shot_end], [param shot_hitbox_path], [param shot_zone] y [param shot_damage].
	func _init(shot_origin: Vector3, shot_end: Vector3, shot_hitbox_path: NodePath,
			shot_zone: int, shot_damage: float) -> void:
		name = "ShotTrace"
		origin = shot_origin
		end = shot_end
		hitbox_path = shot_hitbox_path
		zone = shot_zone
		damage = shot_damage


	## Monta el rayo, el marcador y la etiqueta y arranca el fundido.
	func _ready() -> void:
		var beam: MeshInstance3D = CombatDebugOverlay.make_beam(CombatDebugOverlay.SHOT_COLOR,
			CombatDebugOverlay.SHOT_HALF_WIDTH)
		_beam_material = beam.material_override as ShaderMaterial
		CombatDebugOverlay.place_beam(beam, origin, end)
		add_child(beam)

		var marker: MeshInstance3D = CombatDebugOverlay.make_marker(
			CombatDebugOverlay.get_zone_color(zone), CombatDebugOverlay.IMPACT_MARKER_RADIUS)
		_marker_material = marker.material_override as StandardMaterial3D
		marker.position = end
		add_child(marker)

		if zone != Firearm.NO_ZONE:
			_label = CombatDebugOverlay.make_label(_describe_hit(), CombatDebugOverlay.get_zone_color(zone))
			_label.position = end
			add_child(_label)

		var tween: Tween = create_tween()
		tween.tween_interval(CombatDebugOverlay.TRACE_HOLD_SECONDS)
		tween.tween_method(set_alpha, 1.0, 0.0, CombatDebugOverlay.TRACE_FADE_SECONDS)
		tween.tween_callback(queue_free)


	## Aplica la opacidad del fundido al rayo, al marcador y a la etiqueta.
	## Recibe: [param alpha] — de [code]1[/code] (entero) a [code]0[/code] (invisible).
	func set_alpha(alpha: float) -> void:
		var beam_color: Color = CombatDebugOverlay.SHOT_COLOR
		beam_color.a = alpha
		_beam_material.set_shader_parameter(&"color", beam_color)
		var marker_color: Color = _marker_material.albedo_color
		marker_color.a = alpha
		_marker_material.albedo_color = marker_color
		if _label:
			_label.modulate.a = alpha
			_label.outline_modulate.a = alpha


	## Devuelve el texto de la etiqueta: la zona y el daño, o "sin daño" si no hizo ninguno.
	func _describe_hit() -> String:
		var zone_name: String = str(Statics.HitZone.keys()[zone]) \
			if zone >= 0 and zone < Statics.HitZone.size() else "?"
		if damage <= 0.0:
			return "%s sin daño" % zone_name
		if is_equal_approx(damage, roundf(damage)):
			return "%s -%d" % [zone_name, roundi(damage)]
		return "%s -%.1f" % [zone_name, damage]


## Pinta las hitboxes que ya existen y se suscribe a las que lleguen mientras esté encendido.
func _ready() -> void:
	for node: Node in get_tree().get_nodes_in_group(Hitbox.GROUP):
		_queue_decoration(node as Hitbox)
	get_tree().node_added.connect(_on_node_added)


## Deja de vigilar el árbol y borra los visuales de las hitboxes; los trazos son hijos suyos y
## se van con él.
func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for node: Node in get_tree().get_nodes_in_group(VISUAL_GROUP):
		node.queue_free()


## Dibuja un disparo ya resuelto por el servidor y hace destellar la hitbox que tocó, si este
## peer la tiene pintada. Lo llama [code]Firearm._play_fire_effects()[/code] en cada peer.
## Recibe: [param origin] — origen del disparo; [param end] — donde acabó;
## [param hitbox_path] — ruta absoluta de la hitbox golpeada (vacía si ninguna);
## [param zone] — su zona, o [constant Firearm.NO_ZONE]; [param damage] — daño que hizo.
func add_shot(origin: Vector3, end: Vector3, hitbox_path: NodePath, zone: int, damage: float) -> void:
	add_child(ShotTrace.new(origin, end, hitbox_path, zone, damage))
	var traces: Array[ShotTrace] = get_traces()
	for i: int in range(traces.size() - MAX_TRACES):
		traces[i].queue_free()
	if hitbox_path.is_empty():
		return
	var hitbox: Hitbox = get_node_or_null(hitbox_path) as Hitbox
	if hitbox:
		for visual: HitboxVisual in get_hitbox_visuals(hitbox):
			visual.flash()


## Devuelve los trazos vivos, del más viejo al más nuevo.
func get_traces() -> Array[ShotTrace]:
	var traces: Array[ShotTrace] = []
	for child: Node in get_children():
		var trace: ShotTrace = child as ShotTrace
		if trace and not trace.is_queued_for_deletion():
			traces.append(trace)
	return traces


## Devuelve los visuales de [param hitbox], uno por cada [CollisionShape3D] ya pintada.
static func get_hitbox_visuals(hitbox: Hitbox) -> Array[HitboxVisual]:
	var visuals: Array[HitboxVisual] = []
	for child: Node in hitbox.get_children():
		var shape: CollisionShape3D = child as CollisionShape3D
		if not shape:
			continue
		for shape_child: Node in shape.get_children(true):
			var visual: HitboxVisual = shape_child as HitboxVisual
			if visual and not visual.is_queued_for_deletion():
				visuals.append(visual)
	return visuals


## Devuelve el color de [param zone]: verde el cuerpo, amarillo la cabeza y magenta el punto
## débil, lejos del azul y el rojo de los rayos. Sin zona ([constant Firearm.NO_ZONE]), el rojo
## del disparo.
static func get_zone_color(zone: int) -> Color:
	match zone:
		Statics.HitZone.CUERPO:
			return BODY_COLOR
		Statics.HitZone.CABEZA:
			return HEAD_COLOR
		Statics.HitZone.PUNTO_DEBIL:
			return WEAK_SPOT_COLOR
	return SHOT_COLOR


## Devuelve la malla equivalente a [param shape] en su propio espacio, el de la
## [CollisionShape3D]: esfera, cápsula, caja o cilindro con sus medidas. Cualquier otra forma
## cae en su malla de depuración de líneas.
static func make_shape_mesh(shape: Shape3D) -> Mesh:
	var sphere: SphereShape3D = shape as SphereShape3D
	if sphere:
		var sphere_mesh: SphereMesh = SphereMesh.new()
		sphere_mesh.radius = sphere.radius
		sphere_mesh.height = sphere.radius * 2.0
		sphere_mesh.radial_segments = 16
		sphere_mesh.rings = 8
		return sphere_mesh
	var capsule: CapsuleShape3D = shape as CapsuleShape3D
	if capsule:
		# En las dos, height es el alto total, casquetes incluidos.
		var capsule_mesh: CapsuleMesh = CapsuleMesh.new()
		capsule_mesh.radius = capsule.radius
		capsule_mesh.height = capsule.height
		capsule_mesh.radial_segments = 16
		capsule_mesh.rings = 4
		return capsule_mesh
	var box: BoxShape3D = shape as BoxShape3D
	if box:
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = box.size
		return box_mesh
	var cylinder: CylinderShape3D = shape as CylinderShape3D
	if cylinder:
		var cylinder_mesh: CylinderMesh = CylinderMesh.new()
		cylinder_mesh.top_radius = cylinder.radius
		cylinder_mesh.bottom_radius = cylinder.radius
		cylinder_mesh.height = cylinder.height
		return cylinder_mesh
	return shape.get_debug_mesh() if shape else null


## Devuelve un material plano (sin luz ni niebla), transparente y sin prueba de profundidad.
## Recibe: [param color] — color con su alfa; [param priority] — orden de dibujo.
static func make_flat_material(color: Color, priority: int) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.disable_fog = true
	material.albedo_color = color
	material.render_priority = priority
	return material


## Deja [param geometry] como debe estar todo visual de depuración: en la capa 4, sin sombras y
## fuera de la iluminación global.
static func prepare_geometry(geometry: GeometryInstance3D) -> void:
	geometry.layers = VISUAL_LAYER
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Devuelve un rayo sin colocar: un cilindro de radio 1 y alto 1 que
## [code]debug_beam.gdshader[/code] adelgaza a un grosor constante en pantalla. Es
## [code]top_level[/code]: se coloca en coordenadas globales con [code]place_beam()[/code].
## Recibe: [param color] — color del rayo; [param half_width] — medio ancho angular en radianes.
static func make_beam(color: Color, half_width: float) -> MeshInstance3D:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	cylinder.rings = 0
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = BEAM_SHADER
	material.render_priority = BEAM_PRIORITY
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"half_width", half_width)
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.mesh = cylinder
	beam.material_override = material
	beam.top_level = true
	prepare_geometry(beam)
	return beam


## Estira y orienta [param beam] de [param from] a [param to], en coordenadas globales: su eje Y
## mide la distancia y X y Z quedan unitarios, como espera el shader. Ajusta sus anillos a la
## longitud ([constant BEAM_RING_SPACING]) y lo oculta si los dos puntos casi coinciden.
static func place_beam(beam: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta: Vector3 = to - from
	var length: float = delta.length()
	if length < 0.001:
		beam.hide()
		return
	var cylinder: CylinderMesh = beam.mesh as CylinderMesh
	var rings: int = clampi(floori(length / BEAM_RING_SPACING), 0, MAX_BEAM_RINGS)
	if cylinder and cylinder.rings != rings:
		cylinder.rings = rings
	var axis: Vector3 = delta / length
	var helper: Vector3 = Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT
	var side: Vector3 = axis.cross(helper).normalized()
	# side × axis: base dextrógira, o el cilindro saldría del revés.
	beam.transform = Transform3D(Basis(side, axis * length, side.cross(axis)), from + delta * 0.5)
	beam.show()


## Devuelve un marcador esférico sin colocar, que se dibuja siempre al tamaño que tendría a 1 m
## para que se vea igual de cerca que de lejos. Es [code]top_level[/code]: su
## [code]position[/code] es global.
## Recibe: [param color] — color del marcador; [param radius] — radio aparente a 1 m.
static func make_marker(color: Color, radius: float) -> MeshInstance3D:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var material: StandardMaterial3D = make_flat_material(color, MARKER_PRIORITY)
	material.fixed_size = true
	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.mesh = sphere
	marker.material_override = material
	marker.top_level = true
	prepare_geometry(marker)
	return marker


## Devuelve una etiqueta sin colocar, siempre de cara a la cámara, del mismo tamaño a cualquier
## distancia y un poco por encima de su punto. Es [code]top_level[/code]: su
## [code]position[/code] es global.
## Recibe: [param text] — el texto; [param color] — su color.
static func make_label(text: String, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.modulate = color
	label.outline_modulate = Color.BLACK
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.0008
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.offset = Vector2(0.0, 28.0)
	label.render_priority = LABEL_PRIORITY
	label.outline_render_priority = LABEL_PRIORITY - 1
	label.top_level = true
	prepare_geometry(label)
	return label


## Pinta las hitboxes que entren al árbol mientras el modo está encendido.
## Recibe: [param node] — el nodo que acaba de entrar.
func _on_node_added(node: Node) -> void:
	var hitbox: Hitbox = node as Hitbox
	if hitbox:
		_queue_decoration(hitbox)


## Apunta [param hitbox] para pintarla al final del frame. Diferido porque al entrar al árbol
## sus formas aún no han entrado, y el enemigo puede liberar la hitbox en su
## [code]_ready()[/code] (la del cubo, al cargar un modelo).
func _queue_decoration(hitbox: Hitbox) -> void:
	if not hitbox:
		return
	if _pending_hitboxes.is_empty():
		_decorate_pending.call_deferred()
	_pending_hitboxes.append(hitbox.get_instance_id())


## Pinta las hitboxes apuntadas que sigan existiendo y dentro del árbol.
func _decorate_pending() -> void:
	var ids: Array[int] = _pending_hitboxes.duplicate()
	_pending_hitboxes.clear()
	for id: int in ids:
		var hitbox: Hitbox = instance_from_id(id) as Hitbox
		if hitbox and hitbox.is_inside_tree():
			_decorate(hitbox)


## Cuelga un [CombatDebugOverlay.HitboxVisual] de cada [CollisionShape3D] de [param hitbox] que
## aún no tenga uno, como hijo interno.
func _decorate(hitbox: Hitbox) -> void:
	for child: Node in hitbox.get_children():
		var shape: CollisionShape3D = child as CollisionShape3D
		if not shape or not shape.shape or _has_visual(shape):
			continue
		shape.add_child(HitboxVisual.new(shape.shape, hitbox.zone), false, Node.INTERNAL_MODE_BACK)


## Devuelve [code]true[/code] si [param shape] ya tiene su visual.
func _has_visual(shape: CollisionShape3D) -> bool:
	for child: Node in shape.get_children(true):
		if child is HitboxVisual and not child.is_queued_for_deletion():
			return true
	return false
