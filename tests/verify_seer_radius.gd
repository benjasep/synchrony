extends Node3D

## Prueba de píxeles: ejecutar con --rendering-driver vulkan
## res://tests/verify_seer_radius.tscn. Requiere render real, sin --headless.
var failures: int = 0
var perception: PerceptionComponent
var target: MeshInstance3D
var main_viewport: SubViewport


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
	perception.apply_vision_mode(RoleDatabase.get_profile(Statics.Role.SEER).vision_mode)
	target = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	target.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.GREEN
	target.material_override = material
	main_viewport.add_child(target)
	for layer: int in [Statics.ETHEREAL_VISUAL_LAYER, Statics.BODY_VISUAL_LAYER]:
		target.layers = layer
		await _expect_alpha("capa %d dentro de 12m" % layer, Vector3(0, 0, -11.5), true)
		await _expect_alpha("capa %d fuera de 12m" % layer, Vector3(0, 0, -12.5), false)
		# Profundidad 11m, distancia real 12.53m: debe quedar fuera.
		await _expect_alpha("capa %d fuera en diagonal" % layer, Vector3(6, 0, -11), false)
		perception.set_shader_parameter(&"perception_radius", 25.0)
		await _expect_alpha("capa %d revelada por pulso" % layer, Vector3(6, 0, -11), true)
		await _expect_alpha("capa %d fuera incluso del pulso" % layer, Vector3(0, 0, -25.5), false)
		perception.set_shader_parameter(&"perception_radius", 12.0)
		await _expect_alpha("capa %d oculta al terminar pulso" % layer, Vector3(0, 0, -20), false)
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
	print(">>> Radio del vidente: %d fallos" % failures)
	get_tree().quit(failures)


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
	var color: Color = image.get_pixelv(pixel)
	_check(label, color.a > 0.9 if visible_expected else color.a < 0.01)
	if visible_expected:
		_check(label + " conserva color", color.g > 0.9)


func _check(label: String, condition: bool) -> void:
	print("  %s %s" % ["ok" if condition else "FALLO", label])
	if not condition:
		failures += 1
