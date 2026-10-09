class_name FootPlacement
extends SkeletonModifier3D

## Apoya las patas de un modelo animado sobre el suelo real (escalones, rampas): después del
## [AnimationTree], baja e inclina el cuerpo y corrige cada pata con un IK de dos huesos.
## Con desnivel cero reproduce la animación exacta. Cosmético y local, nunca se replica.
## Apágalo ([code]enabled = false[/code]) cuando una animación deba mandar sobre el cuerpo.

@export var enabled: bool = true
## Antepasado de todas las patas y de ningún hueso que deba quedarse quieto (presa_*).
@export var body_bone: StringName = &"vertebra_1"
@export var legs: Array[FootPlacementLeg] = []

@export_group("Suelo")
@export_flags_3d_physics var ground_mask: int = 1
@export var max_step_up: float = 0.45
@export var max_step_down: float = 0.45
@export var ray_margin: float = 0.25

@export_group("Cuerpo")
@export_range(0.0, 60.0, 0.5, "degrees") var max_body_pitch: float = 25.0

@export_group("Suavizado")
@export var smoothing_time: float = 0.08
@export var blend_time: float = 0.25

var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _resolved_skeleton: Skeleton3D
var _resolved_bone_count: int = -1
var _body_index: int = -1
var _chains: Array[PackedInt32Array] = []
var _chain_is_front: Array[bool] = []
var _offsets: PackedFloat32Array = PackedFloat32Array()
var _has_offsets: bool = false
var _weight: float = 1.0


## Lo llama el [Skeleton3D] cada frame, después de la animación: funde el peso hacia
## [code]enabled[/code], mide el suelo bajo cada pie, desplaza e inclina el hueso del cuerpo
## y resuelve el IK de cada pata. Godot descarta la pose retocada al acabar el frame.
## Recibe: [param delta] — segundos desde la última actualización del esqueleto.
func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton or not skeleton.is_inside_tree() or not _resolve(skeleton):
		return

	var target_weight: float = 1.0 if enabled else 0.0
	if blend_time > 0.0:
		_weight = move_toward(_weight, target_weight, delta / blend_time)
	else:
		_weight = target_weight
	if _weight <= 0.0:
		# Al volver a encenderse arranca del suelo que haya entonces, no del que
		# había cuando se apagó.
		_has_offsets = false
		return

	var to_world: Transform3D = skeleton.global_transform
	var to_skeleton: Transform3D = to_world.affine_inverse()
	var up: Vector3 = (to_skeleton.basis * Vector3.UP).normalized()

	# Todo lo animado se lee ANTES de tocar ningún hueso: en cuanto se mueve el
	# cuerpo, get_bone_global_pose() de sus descendientes ya devuelve la pose
	# modificada.
	var roots: Array[Transform3D] = []
	var middles: Array[Transform3D] = []
	var ends: Array[Transform3D] = []
	var contacts: Array[Vector3] = []
	for chain: PackedInt32Array in _chains:
		roots.append(skeleton.get_bone_global_pose(chain[0]))
		middles.append(skeleton.get_bone_global_pose(chain[1]))
		ends.append(skeleton.get_bone_global_pose(chain[2]))
		contacts.append(skeleton.get_bone_global_pose(chain[3]).origin)

	_update_offsets(skeleton, to_world, to_skeleton, up, contacts, delta)

	var body_transform: Transform3D = _compute_body_transform(roots, up)
	var body_moved: bool = not body_transform.is_equal_approx(Transform3D.IDENTITY)
	if body_moved:
		skeleton.set_bone_global_pose(_body_index,
			body_transform * skeleton.get_bone_global_pose(_body_index))

	for i: int in _chains.size():
		var offset: float = _offsets[i] * _weight
		if not body_moved and absf(offset) < 0.0001:
			continue
		var target: Vector3 = ends[i].origin + up * offset
		_solve_leg(skeleton, _chains[i], body_transform * roots[i],
			body_transform * middles[i], body_transform * ends[i].origin, ends[i].basis, target)


## Lanza un raycast vertical bajo cada pie y guarda en [code]_offsets[/code] cuánto sube o baja
## el suelo respecto al origen del esqueleto, recortado a los límites de paso y suavizado; la
## primera medida tras resolver o reactivar se aplica de golpe. Sin impacto, el objetivo es 0.
## Recibe: [param skeleton] — da el espacio físico; [param to_world]/[param to_skeleton] — paso
## entre espacio del esqueleto y mundo; [param up] — vertical en espacio del esqueleto;
## [param contacts] — posición animada de cada contacto, en ese espacio; [param delta] —
## segundos del frame.
func _update_offsets(skeleton: Skeleton3D, to_world: Transform3D, to_skeleton: Transform3D,
		up: Vector3, contacts: Array[Vector3], delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = skeleton.get_world_3d().direct_space_state
	_query.collision_mask = ground_mask
	var smoothing: float = 1.0 - exp(-delta / maxf(smoothing_time, 0.0001))

	for i: int in contacts.size():
		# El origen del esqueleto es el suelo sobre el que se animó el clip, así
		# que el desnivel es la altura del impacto sobre ese plano.
		var flat: Vector3 = contacts[i] - up * up.dot(contacts[i])
		_query.from = to_world * (flat + up * (max_step_up + ray_margin))
		_query.to = to_world * (flat - up * (max_step_down + ray_margin))
		var hit: Dictionary = space.intersect_ray(_query)
		var target_offset: float = 0.0
		if not hit.is_empty():
			var hit_position: Vector3 = hit["position"]
			target_offset = clampf(up.dot(to_skeleton * hit_position), -max_step_down, max_step_up)

		if _has_offsets:
			_offsets[i] = lerpf(_offsets[i], target_offset, smoothing)
		else:
			_offsets[i] = target_offset
	_has_offsets = true


## Calcula cuánto bajar e inclinar el cuerpo: el desnivel más bajo de las traseras fija la
## altura de la cadera y el de las delanteras, la de los hombros, que se alcanza girando sobre
## la cadera hasta [code]max_body_pitch[/code]. Con un solo grupo de patas solo desplaza.
## Recibe: [param roots] — pose animada del hueso raíz de cada pata; [param up] — vertical;
## ambos en espacio del esqueleto.
## Devuelve: la transformada que se antepone a la pose del cuerpo, en espacio del esqueleto;
## identidad si no hay patas.
func _compute_body_transform(roots: Array[Transform3D], up: Vector3) -> Transform3D:
	var rear: float = INF
	var front: float = INF
	var hip: Vector3 = Vector3.ZERO
	var shoulder: Vector3 = Vector3.ZERO
	var rear_count: int = 0
	var front_count: int = 0
	for i: int in _chains.size():
		var offset: float = _offsets[i] * _weight
		if _chain_is_front[i]:
			front = minf(front, offset)
			shoulder += roots[i].origin
			front_count += 1
		else:
			rear = minf(rear, offset)
			hip += roots[i].origin
			rear_count += 1

	if rear_count == 0 and front_count == 0:
		return Transform3D.IDENTITY
	if rear_count == 0 or front_count == 0:
		# Bípedo (o solo delanteras): sin inclinación, el cuerpo baja lo que
		# necesite el pie más bajo.
		return Transform3D(Basis.IDENTITY, up * minf(rear, front))

	hip /= float(rear_count)
	shoulder /= float(front_count)
	var forward: Vector3 = shoulder - hip
	forward -= up * up.dot(forward)
	var distance: float = forward.length()
	var pitch: Transform3D = Transform3D.IDENTITY
	if distance > 0.001:
		forward /= distance
		var limit: float = deg_to_rad(max_body_pitch)
		var angle: float = clampf(atan2(front - rear, distance), -limit, limit)
		# Girar sobre forward × up lleva forward hacia up: ángulo positivo sube
		# los hombros.
		var tilt: Basis = Basis(forward.cross(up).normalized(), angle)
		pitch = Transform3D(tilt, hip - tilt * hip)
	return Transform3D(Basis.IDENTITY, up * rear) * pitch


## IK analítico de dos huesos (ley del coseno) en espacio del esqueleto: lleva el hueso final a
## [param target] doblando la rodilla en el plano de la animación y le devuelve su orientación
## animada. Fuera de alcance estira la pata sin alargar huesos; si algún hueso mide cero o la
## rodilla queda alineada con el objetivo, no toca nada.
## Recibe: [param chain] — índices [raíz, medio, final, contacto]; [param root],
## [param middle] y [param end_origin] — pose animada ya desplazada con el cuerpo;
## [param end_basis] — rotación animada del hueso final; [param target] — destino del hueso
## final, que no se mueve con el cuerpo porque el pie pisa el terreno.
func _solve_leg(skeleton: Skeleton3D, chain: PackedInt32Array, root: Transform3D,
		middle: Transform3D, end_origin: Vector3, end_basis: Basis, target: Vector3) -> void:
	var upper: float = root.origin.distance_to(middle.origin)
	var lower: float = middle.origin.distance_to(end_origin)
	var to_target: Vector3 = target - root.origin
	if upper < 0.0001 or lower < 0.0001 or to_target.length_squared() < 0.000001:
		return

	var direction: Vector3 = to_target.normalized()
	# Fuera de alcance la pata se estira hacia el objetivo y el pie se queda
	# corto; no se estira el hueso.
	var reach: float = clampf(to_target.length(), absf(upper - lower) + 0.0001, upper + lower - 0.0001)

	var bend: Vector3 = middle.origin - root.origin
	bend -= direction * direction.dot(bend)
	if bend.length_squared() < 0.00000001:
		return
	bend = bend.normalized()

	var along: float = (upper * upper - lower * lower + reach * reach) / (2.0 * reach)
	var height: float = sqrt(maxf(upper * upper - along * along, 0.0))
	var new_middle: Vector3 = root.origin + direction * along + bend * height
	var new_end: Vector3 = root.origin + direction * reach

	var root_rotation: Basis = Basis(Quaternion(
		(middle.origin - root.origin).normalized(), (new_middle - root.origin).normalized()))
	var end_after_root: Vector3 = root.origin + root_rotation * (end_origin - root.origin)
	var middle_rotation: Basis = Basis(Quaternion(
		(end_after_root - new_middle).normalized(), (new_end - new_middle).normalized()))

	skeleton.set_bone_global_pose(chain[0], Transform3D(root_rotation * root.basis, root.origin))
	skeleton.set_bone_global_pose(chain[1],
		Transform3D(middle_rotation * root_rotation * middle.basis, new_middle))
	skeleton.set_bone_global_pose(chain[2], Transform3D(end_basis, new_end))


## Traduce los nombres de huesos a índices y descarta, con un aviso, las patas con algún hueso
## inexistente. Solo se repite si cambia el esqueleto o su número de huesos (no al cambiar
## [code]legs[/code] o [code]body_bone[/code]), y entonces reinicia el suavizado.
## Recibe: [param skeleton] — el esqueleto actual del modificador.
## Devuelve: [code]true[/code] si existe el hueso del cuerpo y queda al menos una pata válida.
func _resolve(skeleton: Skeleton3D) -> bool:
	if skeleton == _resolved_skeleton and skeleton.get_bone_count() == _resolved_bone_count:
		return _body_index >= 0 and not _chains.is_empty()
	_resolved_skeleton = skeleton
	_resolved_bone_count = skeleton.get_bone_count()
	_chains.clear()
	_chain_is_front.clear()
	_has_offsets = false

	_body_index = skeleton.find_bone(body_bone)
	if _body_index < 0:
		push_warning("FootPlacement: no existe el hueso de cuerpo '%s'" % body_bone)
	for leg: FootPlacementLeg in legs:
		if not leg:
			continue
		var chain: PackedInt32Array = PackedInt32Array([
			skeleton.find_bone(leg.root_bone), skeleton.find_bone(leg.middle_bone),
			skeleton.find_bone(leg.end_bone), skeleton.find_bone(leg.contact_bone)])
		if chain.has(-1):
			push_warning("FootPlacement: pata con huesos inexistentes (%s, %s, %s, %s)"
				% [leg.root_bone, leg.middle_bone, leg.end_bone, leg.contact_bone])
			continue
		_chains.append(chain)
		_chain_is_front.append(leg.is_front)
	_offsets.resize(_chains.size())
	return _body_index >= 0 and not _chains.is_empty()
