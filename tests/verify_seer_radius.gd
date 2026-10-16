extends Node3D

## Prueba de píxeles: ejecutar con --rendering-driver vulkan
## res://tests/verify_seer_radius.tscn. Requiere render real, sin --headless.
var failures: int = 0
var perception: PerceptionComponent
var target: MeshInstance3D
var main_viewport: SubViewport
var wall: MeshInstance3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Esta prueba requiere render real; ejecutar sin --headless.")
		get_tree().quit(1)
		return
	main_viewport = SubViewport.new()
	main_viewport.size = Vector2i(256, 256)
	main_viewport.own_world_3d = true
	main_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(main_viewport)
	var camera: Camera3D = Camera3D.new()
	main_viewport.add_child(camera)
	camera.current = true
	var echo: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2, 2)
	echo.mesh = quad
	echo.extra_cull_margin = 16384.0
	camera.add_child(echo)
	echo.position.z = -1.0
	var ethereal: SubViewport = SubViewport.new()
	main_viewport.add_child(ethereal)
	var second_camera: Camera3D = Camera3D.new()
	ethereal.add_child(second_camera)
	perception = PerceptionComponent.new()
	perception.camera = camera
	perception.echo_quad = echo
	perception.ethereal_viewport = ethereal
	perception.ethereal_camera = second_camera
	main_viewport.add_child(perception)
	var overlay: TextureRect = TextureRect.new()
	overlay.size = Vector2(256, 256)
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main_viewport.add_child(overlay)
	perception.ethereal_view = overlay
	perception.apply_vision_mode(RoleDatabase.get_profile(Statics.Role.SEER).vision_mode)
	wall = MeshInstance3D.new()
	var wall_mesh: BoxMesh = BoxMesh.new()
	wall_mesh.size = Vector3(40, 40, 0.5)
	wall.mesh = wall_mesh
	wall.position = Vector3(0, 0, -3)
	wall.layers = Statics.WORLD_VISUAL_LAYER
	main_viewport.add_child(wall)
	target = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	target.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.GREEN
	target.material_override = material
	main_viewport.add_child(target)
	for layer: int in [Statics.ETHEREAL_VISUAL_LAYER, Statics.PHYSICAL_ENEMY_VISUAL_LAYER, Statics.BODY_VISUAL_LAYER, Statics.VIEWMODEL_VISUAL_LAYER]:
		target.layers = layer
		await _expect_alpha("capa %d visible detras de pared dentro de 12m" % layer, Vector3(0, 0, -11.5), true)
		await _expect_alpha("capa %d oculta detras de pared fuera de 12m" % layer, Vector3(0, 0, -12.5), false)
		# Profundidad 11m, distancia real 12.53m: debe quedar fuera.
		await _expect_alpha("capa %d fuera en diagonal" % layer, Vector3(6, 0, -11), false)
		perception.set_shader_parameter(&"perception_radius", 25.0)
		await _expect_alpha("capa %d revelada por pulso" % layer, Vector3(6, 0, -11), true)
		await _expect_alpha("capa %d fuera incluso del pulso" % layer, Vector3(0, 0, -25.5), false)
		perception.set_shader_parameter(&"perception_radius", 12.0)
		await _expect_alpha("capa %d oculta al terminar pulso" % layer, Vector3(0, 0, -20), false)
	wall.hide()
	target.layers = Statics.WORLD_VISUAL_LAYER
	await _expect_echo("mundo dentro del radio", Vector3(0, 0, -8), true)
	await _expect_echo("mundo fuera del radio", Vector3(0, 0, -12.5), false)
	await _expect_echo("mundo fuera en diagonal", Vector3(6, 0, -11), false)
	perception.set_shader_parameter(&"perception_radius", 25.0)
	await _expect_echo("pulso amplia tambien los contornos", Vector3(6, 0, -11), true)
	perception.set_shader_parameter(&"perception_radius", 12.0)
	# El filtro debe conservar el fondo transparente cuando no hay geometría.
	target.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = ethereal.get_texture().get_image()
	_check("fondo etereo transparente", image.get_pixel(128, 128).a < 0.01)
	for role: Statics.Role in [Statics.Role.SOLDIER, Statics.Role.TECHNICIAN]:
		perception.apply_vision_mode(RoleDatabase.get_profile(role).vision_mode)
		target.show()
		target.layers = Statics.PHYSICAL_ENEMY_VISUAL_LAYER
		wall.show()
		await _expect_normal_visibility("rol %d ve enemigo delante de pared" % role, Vector3(0, 0, -2), true)
		await _expect_normal_visibility("rol %d no ve enemigo detras de pared" % role, Vector3(0, 0, -8), false)
		wall.hide()
		await _expect_normal_visibility("rol %d conserva vision sin limite del vidente" % role, Vector3(0, 0, -15), true)
		target.layers = Statics.ETHEREAL_VISUAL_LAYER
		await _expect_normal_visibility("rol %d sigue sin ver etereos" % role, Vector3(0, 0, -2), false)
	print(">>> Radio del vidente: %d fallos" % failures)
	get_tree().quit(failures)


func _expect_normal_visibility(label: String, position: Vector3, visible_expected: bool) -> void:
	target.position = position
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var pixel: Vector2i = Vector2i(perception.camera.unproject_position(position))
	var color: Color = main_viewport.get_texture().get_image().get_pixelv(pixel)
	_check(label, color.g > color.r + 0.5 if visible_expected else color.g < color.r + 0.5)


func _expect_echo(label: String, position: Vector3, visible_expected: bool) -> void:
	target.position = position
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = main_viewport.get_texture().get_image()
	var brightest: float = 0.0
	for y: int in image.get_height():
		for x: int in image.get_width():
			brightest = maxf(brightest, image.get_pixel(x, y).r)
	_check(label, brightest > 0.01 if visible_expected else brightest < 0.001)


func _expect_alpha(label: String, position: Vector3, visible_expected: bool) -> void:
	target.position = position
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var pixel: Vector2i = Vector2i(perception.ethereal_camera.unproject_position(position))
	var image: Image = perception.ethereal_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_check("render real disponible", false)
		get_tree().quit(1)
		return
	var composed: Image = main_viewport.get_texture().get_image()
	var max_alpha: float = 0.0
	var max_outline: float = 0.0
	var texture_color: float = 0.0
	var final_outline: float = 0.0
	# Busca el borde alrededor del centro proyectado; el interior debe quedar vacío.
	for y: int in range(maxi(pixel.y - 16, 0), mini(pixel.y + 17, image.get_height())):
		for x: int in range(maxi(pixel.x - 16, 0), mini(pixel.x + 17, image.get_width())):
			var color: Color = image.get_pixel(x, y)
			max_alpha = maxf(max_alpha, color.a)
			if color.a > 0.01:
				max_outline = maxf(max_outline, color.r)
				texture_color = maxf(texture_color, absf(color.g - color.r))
			final_outline = maxf(final_outline, composed.get_pixel(x, y).r)
	_check(label, max_alpha > 0.9 if visible_expected else max_alpha < 0.01)
	_check(label + " en imagen final", final_outline > 0.01 if visible_expected else final_outline < 0.001)
	if visible_expected:
		_check(label + " solo bordes blancos, sin textura verde", max_outline > 0.01 and texture_color < 0.01)
		_check(label + " interior transparente", image.get_pixelv(pixel).a < 0.01)


func _check(label: String, condition: bool) -> void:
	print("  %s %s" % ["ok" if condition else "FALLO", label])
	if not condition:
		failures += 1
