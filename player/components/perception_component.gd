class_name PerceptionComponent
extends PlayerComponent

## Aplica el VisionMode del rol a la cámara del jugador.
##
## Es puramente local: la percepción no se replica y no se configura en las
## copias remotas. El vidente ve fantasmas y contornos de pared porque su
## cámara y su composición son distintas, no porque el mundo cambie para él.
##
## Cómo se arma la vista del vidente, y por qué en tres piezas:
##
##   cámara principal (cull_mask = capa 1) dibuja el mundo, que el quad de eco
##       tapa entero. Solo está ahí para llenar el DEPTH BUFFER.
##   quad de eco (spatial, pantalla completa) reconstruye puntos y contornos
##       desde ese depth. Tiene que ser un quad 3D y no un ColorRect: un shader
##       canvas_item no tiene acceso al depth texture.
##   SubViewport etéreo (cull_mask = capas 2, 3 y 4) es una segunda cámara sobre
##       el MISMO World3D, con fondo transparente, compuesta encima en 2D.
##
## La segunda pasada es obligatoria, no un adorno: el quad tapa por definición
## todo lo que la cámara dibujó, así que enemigos, compañeros y viewmodel no
## sobrevivirían al post-proceso si se dibujaran en la misma pasada. Y el 2D
## siempre se compone por encima del 3D, que es exactamente el orden que hace
## falta.
##
## Presupuesto de capas visuales: ver Statics.WORLD_VISUAL_LAYER y compañía.

@export var camera: Camera3D
## Quad a pantalla completa donde vive el post-proceso de eco.
@export var echo_quad: MeshInstance3D

@export_group("Segunda pasada")
@export var ethereal_viewport: SubViewport
@export var ethereal_camera: Camera3D
## Dónde se compone la segunda pasada, en el CanvasLayer del jugador.
@export var ethereal_view: TextureRect

var vision_mode: VisionMode

var _echo_material: ShaderMaterial


func configure(profile: RoleProfile) -> void:
	super(profile)
	if not is_owner() or not profile:
		return
	apply_vision_mode(profile.vision_mode)


## También la usan items que otorguen percepción (unas gafas espirituales, por
## ejemplo): el sistema no asume que la visión venga solo del rol.
func apply_vision_mode(mode: VisionMode) -> void:
	vision_mode = mode
	if not camera or not mode:
		return
	camera.cull_mask = mode.cull_mask
	_apply_post_process(mode)
	_apply_ethereal_pass(mode)


## Ajusta un uniform en caliente (el pulso de eco del vidente lo usa).
func set_shader_parameter(parameter: StringName, value: Variant) -> void:
	if _echo_material:
		_echo_material.set_shader_parameter(parameter, value)


func _process(_delta: float) -> void:
	if not vision_mode or vision_mode.ethereal_cull_mask == 0:
		return
	_sync_ethereal_camera()


func _apply_post_process(mode: VisionMode) -> void:
	if not echo_quad:
		return
	if not mode.post_process_shader:
		_echo_material = null
		echo_quad.hide()
		return

	_echo_material = ShaderMaterial.new()
	_echo_material.shader = mode.post_process_shader
	for parameter: StringName in mode.shader_parameters:
		_echo_material.set_shader_parameter(parameter, mode.shader_parameters[parameter])
	if mode.perception_radius > 0.0:
		_echo_material.set_shader_parameter(&"perception_radius", mode.perception_radius)
	echo_quad.material_override = _echo_material

	# El quad se muda a las capas que dibuja esta cámara: si cayera fuera del
	# cull_mask no se dibujaría, y el shader se aplicaría a nada.
	echo_quad.layers = mode.cull_mask
	echo_quad.show()


func _apply_ethereal_pass(mode: VisionMode) -> void:
	var enabled: bool = mode.ethereal_cull_mask != 0
	if ethereal_view:
		ethereal_view.visible = enabled
	if not ethereal_viewport or not ethereal_camera:
		return
	if not enabled:
		ethereal_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	# Sin World3D propio: no es otro mundo, es otra cámara sobre el mismo, igual
	# que una pantalla partida. Con mundo propio no habría enemigos que dibujar.
	ethereal_viewport.own_world_3d = false
	ethereal_viewport.transparent_bg = true
	ethereal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	ethereal_camera.cull_mask = mode.ethereal_cull_mask
	ethereal_camera.environment = _build_ethereal_environment(mode)
	ethereal_camera.current = true

	if ethereal_view:
		ethereal_view.texture = ethereal_viewport.get_texture()

	_resize_ethereal_viewport()
	var host: Viewport = camera.get_viewport()
	if host and not host.size_changed.is_connected(_resize_ethereal_viewport):
		host.size_changed.connect(_resize_ethereal_viewport)
	_sync_ethereal_camera()


## Entorno propio de la segunda pasada, no el del nivel.
##
## Fondo: si el nivel trae un WorldEnvironment con cielo, la segunda pasada lo
## dibujaría y le taparía el eco al vidente.
##
## Ambiente: es la única luz que llega aquí. Las luces del nivel están en la
## capa 1 y la capa de una Light3D decide qué cámaras ven su contribución, así
## que para esta cámara no existen. Ver VisionMode.ethereal_ambient_color.
func _build_ethereal_environment(mode: VisionMode) -> Environment:
	var environment: Environment = Environment.new()
	# BG_CLEAR_COLOR y no BG_COLOR: es el único modo que respeta el
	# transparent_bg del SubViewport.
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = mode.ethereal_ambient_color
	environment.ambient_light_energy = mode.ethereal_ambient_energy
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return environment


## Las dos pasadas tienen que encuadrar igual o el eco y lo etéreo no cuadran.
func _resize_ethereal_viewport() -> void:
	if not ethereal_viewport or not camera:
		return
	var host: Viewport = camera.get_viewport()
	if not host or not host.get_texture():
		return
	# El tamaño de RENDER, no el de la ventana ni el del canvas: con stretch
	# "canvas_items" el 2D se escala pero el 3D se dibuja a otra resolución, y
	# esto además sigue valiendo si el jugador acaba dentro de otro SubViewport.
	var render_size: Vector2i = host.get_texture().get_size()
	ethereal_viewport.size = Vector2i(maxi(render_size.x, 1), maxi(render_size.y, 1))


## La segunda cámara cuelga del SubViewport, que no es un Node3D: la cadena de
## transformadas se corta ahí, así que la de la cámara principal se copia a mano
## cada frame. Este componente es el último de la lista, así que para cuando le
## toca ViewComponent ya movió la cabeza.
func _sync_ethereal_camera() -> void:
	if not ethereal_camera or not camera or not camera.is_inside_tree():
		return
	ethereal_camera.global_transform = camera.global_transform
	ethereal_camera.fov = camera.fov
	ethereal_camera.near = camera.near
	ethereal_camera.far = camera.far
	ethereal_camera.keep_aspect = camera.keep_aspect
