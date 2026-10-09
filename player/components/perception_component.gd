class_name PerceptionComponent
extends PlayerComponent

## Aplica el [VisionMode] del rol a la cámara, solo en el cliente dueño (la percepción no se
## replica). Para el vidente arma tres piezas: la cámara principal solo llena el depth, el quad
## de eco lo convierte en contornos y un [SubViewport] etéreo compone encima, en 2D, lo que el
## quad taparía (enemigos etéreos, compañeros, viewmodel).

@export var camera: Camera3D
@export var echo_quad: MeshInstance3D

@export_group("Segunda pasada")
@export var ethereal_viewport: SubViewport
@export var ethereal_camera: Camera3D
@export var ethereal_view: TextureRect

var vision_mode: VisionMode

var _echo_material: ShaderMaterial


## Aplica el [VisionMode] del perfil solo en el dueño; en las copias remotas no toca la vista.
## Recibe: [param profile] — perfil del rol; con [code]null[/code] no aplica nada.
func configure(profile: RoleProfile) -> void:
	super(profile)
	if not is_owner() or not profile:
		return
	apply_vision_mode(profile.vision_mode)


## Guarda el modo y aplica su [code]cull_mask[/code] a la cámara, el post-proceso y la segunda
## pasada. Es pública porque la percepción también podría venir de un item, no solo del rol.
## Recibe: [param mode] — modo a aplicar; con [code]null[/code] o sin cámara solo se guarda.
func apply_vision_mode(mode: VisionMode) -> void:
	vision_mode = mode
	if not camera or not mode:
		return
	camera.cull_mask = mode.cull_mask
	_apply_post_process(mode)
	_apply_ethereal_pass(mode)


## Cambia en caliente un uniform del shader de eco; sin post-proceso activo no hace nada. Lo
## usa [SeerEchoAbility] para el pulso.
## Recibe: [param parameter] — nombre del uniform; [param value] — valor nuevo.
func set_shader_parameter(parameter: StringName, value: Variant) -> void:
	if _echo_material:
		_echo_material.set_shader_parameter(parameter, value)


## Si el modo tiene segunda pasada, copia cada frame la cámara principal a la etérea. Solo
## corre en el dueño.
func _process(_delta: float) -> void:
	if not vision_mode or vision_mode.ethereal_cull_mask == 0:
		return
	_sync_ethereal_camera()


## Crea el material de eco con el shader y los uniforms del modo (más
## [code]perception_radius[/code] si es positivo), lo pone en el quad y muda el quad a las capas
## de [code]cull_mask[/code] para que la cámara lo dibuje. Sin shader, oculta el quad.
## Recibe: [param mode] — modo de visión a aplicar.
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


## Enciende o apaga la segunda pasada según [code]ethereal_cull_mask[/code]. Al encenderla, el
## [SubViewport] comparte el [World3D] del jugador, dibuja con fondo transparente y su propio
## entorno, sigue el tamaño del viewport anfitrión y se muestra en [code]ethereal_view[/code].
## Recibe: [param mode] — modo de visión a aplicar.
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


## Construye el entorno de la segunda pasada, no el del nivel: fondo transparente, para que un
## cielo del nivel no tape el eco, y la luz ambiental del modo, que es la única que llega porque
## las luces del nivel están en la capa 1 y esta cámara no las ve.
## Recibe: [param mode] — de donde salen el color y la energía ambiental.
## Devuelve: un [Environment] nuevo.
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


## Iguala el [SubViewport] etéreo a la resolución de render del viewport anfitrión, para que eco
## y segunda pasada encuadren igual. También se llama en cada [code]size_changed[/code] del
## anfitrión.
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


## Copia a la cámara etérea el transform, FOV, planos de recorte y aspecto de la principal. Va a
## mano porque el [SubViewport] no es un [Node3D] y corta la cadena de transformadas; este
## componente va el último en Components para correr después de que [ViewComponent] mueva la
## cabeza.
func _sync_ethereal_camera() -> void:
	if not ethereal_camera or not camera or not camera.is_inside_tree():
		return
	ethereal_camera.global_transform = camera.global_transform
	ethereal_camera.fov = camera.fov
	ethereal_camera.near = camera.near
	ethereal_camera.far = camera.far
	ethereal_camera.keep_aspect = camera.keep_aspect
