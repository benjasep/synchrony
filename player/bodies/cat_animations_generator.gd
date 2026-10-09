extends SceneTree

## Genera las animaciones del gato (idle, caminar, correr) en
## player/bodies/cat_animations.tres, la AnimationLibrary de cat_body.tscn.
##
##   "$GODOT" --headless --path . --script res://player/bodies/cat_animations_generator.gd
##
## Las animaciones son procedurales y viven en Godot, no en Blender: el .blend de
## baseCat.glb no está disponible. Volver a ejecutar este script sobrescribe el
## .tres, así que los retoques se hacen AQUÍ (en los parámetros de abajo), no en
## el editor de animación, o se pierden en la siguiente generación.
##
## Cómo se construye cada pose:
##   - Las rotaciones se describen en ejes del PERSONAJE (derecha, arriba,
##     delante) y se convierten al marco de reposo de cada hueso. El modelo está
##     en pose T, así que "bajar el brazo" es girar sobre el eje delante.
##   - Las piernas no se animan con ángulos sino con IK: se define dónde está
##     cada pie (en el suelo, retrocediendo, durante el apoyo; en arco hacia
##     delante durante el balanceo) y la altura de la cadera sale de que el pie
##     de apoyo llegue al suelo. Por eso los pies no atraviesan el suelo ni
##     flotan, y el rebote del cuerpo es el natural del paso.
##   - caminar y correr duran lo mismo y empiezan con el pie derecho delante:
##     el BlendSpace1D los mezcla frame a frame, y si estuvieran desfasados las
##     piernas se cruzarían durante la mezcla.
##
## Las piernas del gato son diminutas (cadera a 0,24 m) para las velocidades de
## los roles: con zancadas que no parezcan un spagat, los pies patinan un poco.
## Es lo esperable en un personaje chibi y en primera persona no se ve el propio.

const SCENE_PATH: String = "res://player/bodies/cat_body.tscn"
const OUTPUT_PATH: String = "res://player/bodies/cat_animations.tres"
## Ruta del esqueleto vista desde la raíz de cat_body.tscn, que es la raíz de
## las pistas del AnimationPlayer.
const SKELETON_PATH: String = "Model/Armature/Skeleton3D"
const FPS: float = 30.0

## Duración de un ciclo completo (dos pasos) de caminar y de correr.
const GAIT_CYCLE: float = 0.36
const IDLE_LENGTH: float = 3.0

## Huesos con pista de rotación. Los tres clips animan exactamente el mismo
## conjunto: al mezclar, un hueso que un clip no anima quedaría con el valor de
## otro.
const BONES: Array[StringName] = [
	&"raiz", &"vertebra", &"torso", &"cabeza",
	&"musloD", &"pantorrillaD", &"musloI", &"pantorrillaI",
	&"brazoD", &"antebrazoD", &"brazoI", &"antebrazoI",
	&"orejaD0", &"orejaD1", &"orejaI0", &"orejaI1",
	&"cola0", &"cola1", &"cola2", &"cola3", &"cola4", &"cola5", &"cola6", &"cola7", &"cola8",
]
const TAIL_BONES: int = 9


## Parámetros de una forma de andar. caminar y correr son dos instancias.
class Gait:
	## Fracción del ciclo con cada pie en el suelo. Menos de 0,5 deja una fase
	## de vuelo con los dos pies en el aire (correr).
	var duty: float
	## Recorrido del pie durante el apoyo, en metros.
	var stride: float
	## Altura máxima del pie durante el balanceo.
	var lift: float
	## Cuánto se estira la pierna de apoyo, como fracción de su largo. Menos de 1
	## deja la rodilla algo doblada.
	var reach: float
	## Compresión extra a mitad del apoyo (rebote al correr).
	var compression: float
	## Altura extra del cuerpo a mitad de la fase de vuelo.
	var flight_lift: float
	var hip_yaw: float
	var waddle: float
	var lean: float
	var arms_down: float
	var arm_swing: float
	var elbow: float
	var ear_flop: float
	var ears_back: float
	var tail_raise: float
	var tail_curl: float
	var tail_wave: float


## Pose de un instante: rotación en ejes del personaje por hueso, más el
## desplazamiento vertical de la raíz.
class Pose:
	var rotations: Dictionary[StringName, Quaternion] = {}
	var root_height: float = 0.0

	## Gira un hueso sobre un eje del personaje. Las llamadas se acumulan en
	## orden: la última se aplica encima de las anteriores.
	func turn(bone: StringName, axis: Vector3, degrees: float) -> void:
		var previous: Quaternion = rotations.get(bone, Quaternion.IDENTITY)
		rotations[bone] = Quaternion(axis, deg_to_rad(degrees)) * previous


var _skeleton: Skeleton3D
## Ejes del personaje expresados en el espacio del esqueleto.
var _right: Vector3
var _up: Vector3
var _forward: Vector3
## Metros (escala del juego) a unidades del esqueleto: el modelo está escalado.
var _meters_to_skeleton: float
## Medidas de la pierna, en metros.
var _thigh: float
var _shin: float
var _hip_height: float


func _initialize() -> void:
	var body: Node3D = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	_skeleton = body.get_node(SKELETON_PATH) as Skeleton3D
	if not _skeleton:
		push_error("No se encontró %s en %s" % [SKELETON_PATH, SCENE_PATH])
		quit(1)
		return
	_measure(body)

	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(&"idle", _build(IDLE_LENGTH, _idle_pose))
	library.add_animation(&"caminar", _build(GAIT_CYCLE, _gait_pose.bind(_walk())))
	library.add_animation(&"correr", _build(GAIT_CYCLE, _gait_pose.bind(_run())))
	var error: Error = ResourceSaver.save(library, OUTPUT_PATH)
	body.free()
	if error != OK:
		push_error("No se pudo guardar %s (%s)" % [OUTPUT_PATH, error_string(error)])
		quit(1)
		return
	print("Guardado %s" % OUTPUT_PATH)
	quit(0)


func _walk() -> Gait:
	var gait: Gait = Gait.new()
	gait.duty = 0.6
	gait.stride = 0.22
	gait.lift = 0.035
	gait.reach = 0.985
	gait.compression = 0.06
	gait.flight_lift = 0.0
	gait.hip_yaw = 6.0
	gait.waddle = 5.0
	gait.lean = 4.0
	gait.arms_down = 72.0
	gait.arm_swing = 24.0
	gait.elbow = 18.0
	gait.ear_flop = 7.0
	gait.ears_back = 0.0
	gait.tail_raise = 22.0
	gait.tail_curl = 4.0
	gait.tail_wave = 3.0
	return gait


func _run() -> Gait:
	var gait: Gait = Gait.new()
	gait.duty = 0.35
	gait.stride = 0.2
	gait.lift = 0.08
	gait.reach = 0.95
	gait.compression = 0.08
	gait.flight_lift = 0.03
	gait.hip_yaw = 4.0
	gait.waddle = 2.0
	gait.lean = 14.0
	gait.arms_down = 62.0
	gait.arm_swing = 42.0
	gait.elbow = 70.0
	gait.ear_flop = 12.0
	gait.ears_back = 20.0
	gait.tail_raise = 8.0
	gait.tail_curl = 2.0
	gait.tail_wave = 4.5
	return gait


## Ejes del personaje y medidas de la pierna, sacados del reposo del esqueleto
## tal como lo coloca cat_body.tscn (escalado y girado 180°).
func _measure(body: Node3D) -> void:
	var to_body: Transform3D = Transform3D.IDENTITY
	var node: Node = _skeleton
	while node != body:
		to_body = (node as Node3D).transform * to_body
		node = node.get_parent()

	# Player mira a -Z: en cat_body.tscn derecha es +X, arriba +Y, delante -Z.
	var to_skeleton: Basis = to_body.basis.inverse()
	_right = (to_skeleton * Vector3.RIGHT).normalized()
	_up = (to_skeleton * Vector3.UP).normalized()
	_forward = (to_skeleton * Vector3.FORWARD).normalized()
	_meters_to_skeleton = 1.0 / to_body.basis.get_scale().y

	var hip: Vector3 = to_body * _rest_origin(&"musloD")
	var knee: Vector3 = to_body * _rest_origin(&"pantorrillaD")
	var tail_tip: Vector3 = to_body * _rest_origin(&"cola8")
	var root: Vector3 = to_body * _rest_origin(&"raiz")
	_thigh = hip.distance_to(knee)
	# El último hueso de la pierna no tiene punta en Godot: la pantorrilla llega
	# hasta el suelo, justo debajo de la rodilla.
	_shin = knee.y
	_hip_height = hip.y

	print("pierna: muslo %.3f m, pantorrilla %.3f m, cadera a %.3f m" % [_thigh, _shin, _hip_height])
	if (tail_tip - root).dot(Vector3.BACK) <= 0.0:
		push_warning("La cola no apunta hacia atrás: los ejes del personaje están mal")


func _rest_origin(bone: StringName) -> Vector3:
	return _skeleton.get_bone_global_rest(_skeleton.find_bone(bone)).origin


## Muestrea pose_at(t) a FPS y la convierte en una Animation en bucle.
func _build(length: float, pose_at: Callable) -> Animation:
	var animation: Animation = Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR

	var root_track: int = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(root_track, NodePath("%s:raiz" % SKELETON_PATH))
	var tracks: Dictionary[StringName, int] = {}
	for bone: StringName in BONES:
		var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("%s:%s" % [SKELETON_PATH, bone]))
		tracks[bone] = track

	var root_index: int = _skeleton.find_bone(&"raiz")
	var root_rest: Vector3 = _skeleton.get_bone_rest(root_index).origin
	# La última muestra cae justo antes de length: el bucle interpola de ella a
	# la primera.
	var frames: int = maxi(roundi(length * FPS), 1)
	for frame: int in frames:
		var time: float = length * frame / frames
		var pose: Pose = pose_at.call(time) as Pose
		animation.position_track_insert_key(root_track, time,
			root_rest + _up * pose.root_height * _meters_to_skeleton)
		for bone: StringName in BONES:
			var global_rotation: Quaternion = pose.rotations.get(bone, Quaternion.IDENTITY)
			animation.rotation_track_insert_key(tracks[bone], time, _to_local(bone, global_rotation))
	return animation


## Una rotación en ejes del personaje, aplicada a un hueso en reposo, expresada
## como la rotación local que guarda la pista.
##
## Con el padre en reposo, girar el hueso por R en espacio del esqueleto es
## rest_global * (rest_global⁻¹ · R · rest_global); como rest_global =
## padre_global * rest_local, la pose local es rest_local * ese delta. Si el padre
## también se mueve, el giro queda relativo a él, que es lo que se espera.
func _to_local(bone: StringName, rotation_in_skeleton: Quaternion) -> Quaternion:
	var index: int = _skeleton.find_bone(bone)
	var rest_local: Quaternion = _skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	var rest_global: Quaternion = _skeleton.get_bone_global_rest(index).basis.get_rotation_quaternion()
	return rest_local * (rest_global.inverse() * rotation_in_skeleton * rest_global)


func _idle_pose(time: float) -> Pose:
	var pose: Pose = Pose.new()
	var cycle: float = TAU * time / IDLE_LENGTH
	var breath: float = 0.5 - 0.5 * cos(cycle)

	# Respira: el cuerpo baja apenas y el pecho se abre. Los pies no se mueven,
	# así que las rodillas ceden lo justo.
	pose.root_height = -0.004 * breath
	_place_leg(pose, &"musloD", &"pantorrillaD", 0.0, 0.0, pose.root_height)
	_place_leg(pose, &"musloI", &"pantorrillaI", 0.0, 0.0, pose.root_height)
	pose.turn(&"torso", _right, 1.2 * breath)

	_arms(pose, 72.0 - 2.0 * breath, 2.0 * sin(cycle), 12.0)

	# Mira un poco a un lado y al otro, con la cabeza ladeada.
	pose.turn(&"cabeza", _up, 7.0 * sin(cycle))
	pose.turn(&"cabeza", _forward, 4.0 * sin(cycle + 1.2))

	# Un respingo de la oreja derecha en mitad del bucle (lejos de los bordes,
	# para que el bucle cierre limpio).
	var twitch: float = exp(-pow((time - 1.7) / 0.07, 2.0))
	_ears(pose, 2.0 * breath + 18.0 * twitch, 2.0 * breath, 0.0, 6.0 * twitch)

	_tail(pose, 25.0, 4.0, 3.5, cycle, 0.5)
	return pose


## Una forma de andar en el instante time. phase recorre [0, 1) por ciclo: el
## pie derecho pisa en 0, el izquierdo en 0,5.
func _gait_pose(time: float, gait: Gait) -> Pose:
	var pose: Pose = Pose.new()
	var phase: float = fposmod(time / GAIT_CYCLE, 1.0)
	var cycle: float = TAU * phase

	var right_foot: Vector2 = _foot(phase, gait)
	var left_foot: Vector2 = _foot(fposmod(phase + 0.5, 1.0), gait)
	pose.root_height = _hip_offset(phase, gait)
	_place_leg(pose, &"musloD", &"pantorrillaD", right_foot.x, right_foot.y, pose.root_height)
	_place_leg(pose, &"musloI", &"pantorrillaI", left_foot.x, left_foot.y, pose.root_height)

	# Cadera y hombros giran en contra: pie derecho delante, cadera derecha
	# delante, hombro derecho atrás. La cabeza compensa para mirar al frente.
	var hips: float = gait.hip_yaw * cos(cycle)
	pose.turn(&"raiz", _up, hips)
	pose.turn(&"torso", _up, -1.6 * hips)
	pose.turn(&"cabeza", _up, 0.6 * hips)

	# Contoneo hacia el pie de apoyo (centro del apoyo derecho en duty/2) e
	# inclinación hacia delante, que la cabeza también compensa.
	pose.turn(&"vertebra", _right, -gait.lean)
	pose.turn(&"vertebra", _forward, gait.waddle * cos(cycle - PI * gait.duty))
	pose.turn(&"cabeza", _right, 0.6 * gait.lean)

	# Brazo derecho atrás cuando el pie derecho va delante.
	_arms(pose, gait.arms_down, -gait.arm_swing * cos(cycle), gait.elbow)

	# Orejas y cola van con retraso respecto al rebote: inercia.
	var flop: float = gait.ear_flop * cos(2.0 * cycle - 1.0)
	_ears(pose, flop, flop, gait.ears_back, 0.6 * flop)
	_tail(pose, gait.tail_raise, gait.tail_curl, gait.tail_wave, cycle, 0.6)
	return pose


## Posición del pie respecto a la vertical de su cadera: x hacia delante, y
## altura sobre el suelo. phase = 0 es cuando pisa, adelantado.
func _foot(phase: float, gait: Gait) -> Vector2:
	var half: float = gait.stride * 0.5
	if phase < gait.duty:
		# Apoyo: en el suelo, retrocede a velocidad constante.
		return Vector2(half - gait.stride * phase / gait.duty, 0.0)
	# Balanceo: vuelve hacia delante en arco, arrancando y frenando suave.
	var swing: float = (phase - gait.duty) / (1.0 - gait.duty)
	return Vector2(-half + gait.stride * (0.5 - 0.5 * cos(PI * swing)), gait.lift * sin(PI * swing))


## Cuánto sube o baja la cadera respecto al reposo. Con un pie en el suelo, lo
## alto que permite la pierna de apoyo para llegar a él; en la fase de vuelo
## (correr), un arco entre el final de un apoyo y el principio del siguiente.
func _hip_offset(phase: float, gait: Gait) -> float:
	var height: float = INF
	for leg_phase: float in [phase, fposmod(phase + 0.5, 1.0)]:
		if leg_phase >= gait.duty:
			continue
		var stance: float = leg_phase / gait.duty
		var foot: Vector2 = _foot(leg_phase, gait)
		var leg: float = (_thigh + _shin) * (gait.reach - gait.compression * sin(PI * stance))
		height = minf(height, sqrt(maxf(leg * leg - foot.x * foot.x, 0.0)))
	if is_inf(height):
		var flight_length: float = 0.5 - gait.duty
		var flight: float = fposmod(phase - gait.duty, 0.5) / flight_length
		var leg_at_edge: float = (_thigh + _shin) * gait.reach
		var half: float = gait.stride * 0.5
		height = sqrt(leg_at_edge * leg_at_edge - half * half) + gait.flight_lift * sin(PI * flight)
	return height - _hip_height


## IK de dos huesos en el plano sagital: la pierna llega al pie (x delante,
## y altura) con la cadera desplazada root_height. La rodilla dobla hacia
## delante.
func _place_leg(pose: Pose, thigh: StringName, shin: StringName, foot_x: float, foot_y: float,
		root_height: float) -> void:
	var down: float = _hip_height + root_height - foot_y
	var distance: float = clampf(Vector2(foot_x, down).length(),
		absf(_thigh - _shin) + 0.0001, (_thigh + _shin) * 0.9999)
	var toward_foot: float = atan2(foot_x, down)
	var at_hip: float = acos(clampf(
		(_thigh * _thigh + distance * distance - _shin * _shin) / (2.0 * _thigh * distance), -1.0, 1.0))
	var at_knee: float = acos(clampf(
		(_thigh * _thigh + _shin * _shin - distance * distance) / (2.0 * _thigh * _shin), -1.0, 1.0))
	# Girar sobre el eje derecha lleva hacia delante una pierna que apunta abajo.
	pose.turn(thigh, _right, rad_to_deg(toward_foot + at_hip))
	pose.turn(shin, _right, -rad_to_deg(PI - at_knee))


## Brazos: el modelo está en pose T, así que primero se bajan (giro sobre el eje
## delante) y luego se balancean (giro sobre el eje derecha). El codo, en pose
## T, dobla sobre el eje arriba; al bajar el brazo, ese eje baja con él.
## swing positivo lleva el brazo derecho hacia delante y el izquierdo atrás.
func _arms(pose: Pose, down: float, swing: float, elbow: float) -> void:
	pose.turn(&"brazoD", _forward, down)
	pose.turn(&"brazoD", _right, swing)
	pose.turn(&"antebrazoD", _up, elbow)
	pose.turn(&"brazoI", _forward, -down)
	pose.turn(&"brazoI", _right, -swing)
	pose.turn(&"antebrazoI", _up, -elbow)


## Orejas: apuntan hacia fuera, así que caen girando sobre el eje delante, y
## se echan atrás girando sobre el eje arriba. tip es el extra de la punta.
func _ears(pose: Pose, right_flop: float, left_flop: float, back: float, tip: float) -> void:
	pose.turn(&"orejaD0", _up, -back)
	pose.turn(&"orejaD0", _forward, right_flop)
	pose.turn(&"orejaD1", _forward, tip)
	pose.turn(&"orejaI0", _up, back)
	pose.turn(&"orejaI0", _forward, -left_flop)
	pose.turn(&"orejaI1", _forward, -tip)


## Cola: levantada desde la base, enroscada hacia arriba hueso a hueso, y con
## una onda lateral que viaja hacia la punta.
func _tail(pose: Pose, raise: float, curl: float, wave: float, cycle: float, lag: float) -> void:
	for i: int in TAIL_BONES:
		var bone: StringName = StringName("cola%d" % i)
		pose.turn(bone, _right, -(raise if i == 0 else curl))
		pose.turn(bone, _up, wave * sin(cycle - lag * i))
