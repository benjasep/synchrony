class_name SqueezeModifier
extends SkeletonModifier3D

## Hace que un modelo animado quepa por un [Passage] más chico que él, con posturas de autor y un
## ajuste limitado del esqueleto.

const BEND_SAMPLES: int = 72
const SLACK: float = 2.0
const STICKINESS: float = 0.6
const BODY_WEIGHT: float = 3.0

## Si adapta el modelo a los huecos.
@export var enabled: bool = true

@export_group("Posturas")
@export var tree: AnimationTree
## Parámetro del árbol con la mezcla de la postura baja.
@export var low_parameter: StringName = &"parameters/bajo/blend_amount"
## Parámetro del árbol con la mezcla de la postura estrecha.
@export var narrow_parameter: StringName = &"parameters/estrecho/blend_amount"
## Metros de alto que necesita el modelo de pie, con su malla.
@export var standing_height: float = 1.92
## Metros de alto que necesita en la postura baja, con su malla.
@export var low_height: float = 1.02
## Metros de medio ancho que necesita de pie, con sus garras.
@export var standing_half_width: float = 0.80
## Metros de medio ancho que necesita en la postura estrecha, con sus garras.
@export var narrow_half_width: float = 0.44
## Metros de alto que necesita en la postura estrecha, con su malla.
@export var narrow_height: float = 1.60
## Metros desde el muro a los que empieza a adoptar la postura.
@export var posture_start: float = 3.0
## Metros desde el muro a los que ya tiene la postura entera.
@export var posture_full: float = 2.4
## Metros pasado el muro a los que empieza a soltar la postura al salir.
@export var release_start: float = 1.5
## Metros pasado el muro a los que ya soltó la postura al salir.
@export var release_end: float = 2.1
## Segundos de suavizado de la mezcla de posturas.
@export var posture_smoothing: float = 0.25
## Fracción de postura a partir de la cual se adopta entera.
@export_range(0.1, 1.0, 0.05) var posture_saturation: float = 0.75

@export_group("Topes del ajuste")
## Metros que, como mucho, baja el cuerpo además de lo que da la postura.
@export var max_drop: float = 0.22
## Metros que, como mucho, mete una mano o un pie hacia dentro.
@export var max_inward: float = 0.35
## Grados que, como mucho, gira el plano de una pata.
@export_range(0.0, 180.0, 1.0, "degrees") var max_turn: float = 55.0
## Metros que rodillas y codos se quedan, como mínimo, de su lado de la línea media.
@export var midline_clearance: float = 0.06
## Metros que muñecas y corvejones se quedan de su lado de la línea media; negativo, la cruzan.
@export var end_midline_clearance: float = -0.05
## Metros de radio del tronco alrededor de la columna, donde no entra una rodilla ni un codo.
@export var body_radius: float = 0.22
## Huesos de la columna, de la cadera a la cabeza, que no pueden asomar por encima del hueco.
@export var spine_bones: Array[StringName] = [
	&"vertebra_1", &"vertebra_2", &"vertebra_3", &"vertebra_4", &"cuello", &"craneo"]
## Patas que ajusta.
@export var limbs: Array[SqueezeLimb] = []

@export_group("Holguras")
## Metros de malla sobre los huesos de la columna.
@export var top_clearance: float = 0.24
## Metros de malla sobre huesos concretos de la columna, por nombre.
@export var top_clearance_overrides: Dictionary[StringName, float] = {&"craneo": 0.36}
## Metros de radio de malla alrededor de muñecas y tobillos.
@export var limb_clearance: float = 0.16
## Metros de radio de malla alrededor de codos, rodillas y muslos.
@export var middle_clearance: float = 0.26
## Metros de margen de las puntas de los dedos hasta el marco.
@export var tip_clearance: float = 0.05
## Metros de altura mínima de codos y rodillas sobre el suelo.
@export var floor_clearance: float = 0.26
## Metros de altura mínima de la punta de una garra sobre el suelo.
@export var tip_floor: float = 0.02
## Metros de altura mínima de un hueso que pisa sobre el suelo.
@export var planted_floor: float = 0.1
## Cuánto sigue la garra más allá de su último hueso, en veces lo que mide el anterior.
@export var tip_extension: float = 1.0

@export_group("Colgajos")
## Prefijo de los huesos que cuelgan.
@export var hanging_prefix: String = "liquido"

@export_group("Agacharse")
## Metros que baja el tobillo de una pata plantada por cada metro que baja su cadera.
@export_range(0.0, 1.0, 0.05) var crouch_ratio: float = 0.75
## Metros de altura mínima del tobillo sobre el hueso que pisa.
@export var min_ankle_height: float = 0.2

@export_group("Alcance")
## Metros a cada lado del muro en que el hueco aprieta del todo.
@export var core: float = 0.45
## Metros más allá de [code]core[/code] en que el hueco deja de apretar.
@export var fade: float = 0.4
## Metros, desde el origen del esqueleto, hasta los que busca huecos.
@export var search_radius: float = 5.5
## Segundos de suavizado del giro de codos y rodillas.
@export var smoothing_time: float = 0.08
## Segundos entre búsquedas del hueco más cercano.
@export var search_interval: float = 0.25
## Metros fuera del ancho del hueco a los que este deja de apretar al cuerpo.
@export var side_margin: float = 0.5

var drop: float = 0.0
var low_amount: float = 0.0
var narrow_amount: float = 0.0
var pressure: float = 0.0
var strain: float = 0.0
var strain_drop: float = 0.0
var strain_inward: float = 0.0
var strain_limb: float = 0.0

var _resolved_skeleton: Skeleton3D
var _resolved_bone_count: int = -1
var _spine: PackedInt32Array = PackedInt32Array()
var _spine_clearances: PackedFloat32Array = PackedFloat32Array()
var _chains: Array[PackedInt32Array] = []
var _tips: Array[PackedInt32Array] = []
var _planted: Array[PackedInt32Array] = []
var _tip_parents: Array[PackedInt32Array] = []
var _hanging: PackedInt32Array = PackedInt32Array()
var _angles: PackedFloat32Array = PackedFloat32Array()
var _chosen: PackedFloat32Array = PackedFloat32Array()
var _passage: Passage = null
var _search_left: float = 0.0
var _gate: float = 0.0
var _lateral: Vector3 = Vector3.ZERO
var _forward: Vector3 = Vector3.ZERO
var _anchors: PackedInt32Array = PackedInt32Array()
var _sides: PackedFloat32Array = PackedFloat32Array()
var _middle_clearances: PackedFloat32Array = PackedFloat32Array()


## Adapta la pose de cada frame al hueco más cercano.
func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton or not skeleton.is_inside_tree() or not _resolve(skeleton):
		return
	_update_passage(skeleton, delta)
	drop = 0.0
	pressure = 0.0
	strain = 0.0
	strain_drop = 0.0
	strain_inward = 0.0
	strain_limb = 0.0
	var passage: Passage = _passage if enabled else null
	_update_posture(skeleton, passage, delta)
	if not passage:
		_angles.fill(0.0)
		_chosen.fill(0.0)
		return

	var to_skeleton: Transform3D = skeleton.global_transform.affine_inverse()
	var up: Vector3 = (to_skeleton.basis * Vector3.UP).normalized()
	var from_passage: Transform3D = to_skeleton * passage.global_transform
	var to_passage: Transform3D = from_passage.affine_inverse()
	var lateral: Vector3 = from_passage.basis.x.normalized()
	var origin: Vector3 = from_passage.origin
	var half_width: float = passage.size.x * 0.5
	var height: float = passage.size.y
	_gate = 1.0 - smoothstep(half_width, half_width + maxf(side_margin, 0.001),
		absf((to_passage * Vector3.ZERO).x))
	if _gate <= 0.0:
		_angles.fill(0.0)
		_chosen.fill(0.0)
		return

	var spine_poses: Array[Transform3D] = []
	for index: int in _spine:
		spine_poses.append(skeleton.get_bone_global_pose(index))
	var roots: Array[Transform3D] = []
	var ends: Array[Transform3D] = []
	var tip_points: Array[PackedVector3Array] = []
	var planted_poses: Array[Array] = []
	for i: int in _chains.size():
		roots.append(skeleton.get_bone_global_pose(_chains[i][0]))
		ends.append(skeleton.get_bone_global_pose(_chains[i][2]))
		var points: PackedVector3Array = PackedVector3Array()
		for slot: int in _tips[i].size():
			var tip: Vector3 = skeleton.get_bone_global_pose(_tips[i][slot]).origin
			var parent: int = _tip_parents[i][slot]
			if parent >= 0:
				tip += (tip - skeleton.get_bone_global_pose(parent).origin) * tip_extension
			points.append(tip)
		tip_points.append(points)
		var poses: Array[Transform3D] = []
		for index: int in _planted[i]:
			poses.append(skeleton.get_bone_global_pose(index))
		planted_poses.append(poses)
	var hanging_bases: Array[Basis] = []
	for index: int in _hanging:
		hanging_bases.append(skeleton.get_bone_global_pose(index).basis)

	_flatten_spine(skeleton, passage, spine_poses, to_passage, up, height)
	var spine_points: PackedVector3Array = PackedVector3Array()
	for index: int in _spine:
		spine_points.append(skeleton.get_bone_global_pose(index).origin)

	var smoothing: float = 1.0 - exp(-delta / maxf(smoothing_time, 0.0001))
	for i: int in _chains.size():
		var chain: PackedInt32Array = _chains[i]
		var root: Transform3D = skeleton.get_bone_global_pose(chain[0])
		var middle: Transform3D = skeleton.get_bone_global_pose(chain[1])
		var carried_end: Vector3 = skeleton.get_bone_global_pose(chain[2]).origin
		var root_drop: float = up.dot(roots[i].origin - root.origin)
		var end_pose: Transform3D = ends[i]
		var poses: Array[Transform3D] = []
		poses.assign(planted_poses[i])

		var lift: float = 0.0
		for point: Vector3 in tip_points[i]:
			lift = maxf(lift, tip_floor - up.dot(point))
		for pose: Transform3D in poses:
			lift = maxf(lift, planted_floor - up.dot(pose.origin))
		if lift > 0.0005:
			var raise: Vector3 = up * lift
			end_pose.origin += raise
			for slot: int in poses.size():
				poses[slot] = Transform3D(poses[slot].basis, poses[slot].origin + raise)
			for slot: int in tip_points[i].size():
				tip_points[i][slot] += raise

		var target: Vector3 = end_pose.origin
		var end_basis: Basis = end_pose.basis
		if not poses.is_empty() and root_drop > 0.0005:
			var pivot: Vector3 = poses[0].origin
			var leg: Vector3 = target - pivot
			var length: float = leg.length()
			var rise: float = maxf(up.dot(leg) - root_drop * crouch_ratio, min_ankle_height)
			var flat: Vector3 = leg - up * up.dot(leg)
			if length > 0.001 and flat.length_squared() > 0.000001 and rise < length:
				var lowered: Vector3 = pivot + flat.normalized() \
					* sqrt(length * length - rise * rise) + up * rise
				end_basis = Basis(Quaternion((pivot - target).normalized(),
					(pivot - lowered).normalized())) * end_basis
				target = lowered

		var end_point: Vector3 = to_passage * target
		var middle_point: Vector3 = to_passage * middle.origin
		var weight: float = maxf(_get_weight(passage, to_passage * root.origin),
			maxf(_get_weight(passage, middle_point), _get_weight(passage, end_point)))
		for point: Vector3 in tip_points[i]:
			weight = maxf(weight, _get_weight(passage, to_passage * point))
		pressure = maxf(pressure, weight)

		var side: float = signf(end_point.x) if absf(end_point.x) > 0.001 else 1.0
		var excess: float = side * end_point.x - (half_width - limb_clearance)
		for point: Vector3 in tip_points[i]:
			excess = maxf(excess, side * (to_passage * point).x - (half_width - tip_clearance))
		excess *= weight
		var side_axis: Vector3 = _lateral * _sides[i]
		var anchor: Vector3 = Vector3.ZERO
		if _anchors[i] >= 0:
			anchor = skeleton.get_bone_global_pose(_anchors[i]).origin
		var push: Vector3 = -lateral * side
		var allowed: float = max_inward
		var toward_midline: float = -side_axis.dot(push)
		if toward_midline > 0.001:
			allowed = minf(allowed, maxf(side_axis.dot(target - anchor) - end_midline_clearance,
				0.0) / toward_midline)
		strain_inward = maxf(strain_inward, excess - allowed)
		strain = maxf(strain, excess - allowed)
		excess = minf(excess, allowed)
		var inward: Vector3 = Vector3.ZERO
		if excess > 0.0:
			inward = push * excess
			target += inward

		var moved: bool = root_drop > 0.0005 or weight > 0.0 or absf(_angles[i]) > 0.001 \
			or middle_point.y < floor_clearance or lift > 0.0005
		if not moved:
			_chosen[i] = 0.0
			continue
		_solve_limb(skeleton, i, root, middle, carried_end, end_basis, target, passage,
			to_passage, weight, smoothing, side_axis, anchor, spine_points)
		for slot: int in poses.size():
			skeleton.set_bone_global_pose(_planted[i][slot],
				Transform3D(poses[slot].basis, poses[slot].origin + inward))

	for slot: int in _hanging.size():
		skeleton.set_bone_global_pose(_hanging[slot], Transform3D(hanging_bases[slot],
			skeleton.get_bone_global_pose(_hanging[slot]).origin))


## Baja el cuerpo entero lo que la columna asome por encima del dintel, hasta [code]max_drop[/code].
func _flatten_spine(skeleton: Skeleton3D, passage: Passage, poses: Array[Transform3D],
		to_passage: Transform3D, up: Vector3, height: float) -> void:
	var wanted: float = 0.0
	for i: int in poses.size():
		var point: Vector3 = to_passage * poses[i].origin
		var weight: float = _get_weight(passage, point)
		pressure = maxf(pressure, weight)
		wanted = maxf(wanted, weight * (point.y + _spine_clearances[i] - height))
	drop = clampf(wanted, 0.0, max_drop)
	strain_drop = maxf(wanted - drop, 0.0)
	strain = maxf(strain, strain_drop)
	if drop > 0.0005 and not poses.is_empty():
		skeleton.set_bone_global_pose(_spine[0],
			Transform3D(poses[0].basis, poses[0].origin - up * drop))


## Resuelve el IK de una pata girando su plano para que el codo o la rodilla quepan en el hueco.
func _solve_limb(skeleton: Skeleton3D, limb: int, root: Transform3D, middle: Transform3D,
		end_origin: Vector3, end_basis: Basis, target: Vector3, passage: Passage,
		to_passage: Transform3D, weight: float, smoothing: float, side_axis: Vector3,
		anchor: Vector3, spine_points: PackedVector3Array) -> void:
	var chain: PackedInt32Array = _chains[limb]
	var upper: float = root.origin.distance_to(middle.origin)
	var lower: float = middle.origin.distance_to(end_origin)
	var to_target: Vector3 = target - root.origin
	if upper < 0.0001 or lower < 0.0001 or to_target.length_squared() < 0.000001:
		return
	var direction: Vector3 = to_target.normalized()
	var reach: float = clampf(to_target.length(), absf(upper - lower) + 0.0001,
		upper + lower - 0.0001)
	var bend: Vector3 = middle.origin - root.origin
	bend -= direction * direction.dot(bend)
	if bend.length_squared() < 0.00000001:
		return
	bend = bend.normalized()

	var along: float = (upper * upper - lower * lower + reach * reach) / (2.0 * reach)
	var height: float = sqrt(maxf(upper * upper - along * along, 0.0))
	var base: Vector3 = root.origin + direction * along
	var turned: Vector3 = direction.cross(bend)
	var side_limit: float = passage.size.x * 0.5 - _middle_clearances[limb]
	var top_limit: float = passage.size.y - _middle_clearances[limb]
	var slack: float = (1.0 - weight) * SLACK

	var best_angle: float = 0.0
	var best_cost: float = INF
	var best_score: float = INF
	var best_hole_cost: float = 0.0
	var turn_limit: float = deg_to_rad(max_turn)
	for sample: int in BEND_SAMPLES:
		var angle: float = turn_limit * (2.0 * float(sample) / float(BEND_SAMPLES - 1) - 1.0)
		var candidate: Vector3 = base + (bend * cos(angle) + turned * sin(angle)) * height
		var point: Vector3 = to_passage * candidate
		var hole_cost: float = maxf(absf(point.x) - side_limit - slack, 0.0) \
			+ maxf(point.y - top_limit - slack, 0.0)
		var cost: float = hole_cost + maxf(floor_clearance - point.y, 0.0) \
			+ _get_body_cost(candidate, side_axis, anchor, spine_points) * BODY_WEIGHT
		var score: float = cost * 100.0 + absf(angle) \
			+ absf(angle_difference(_chosen[limb], angle)) * STICKINESS
		if score < best_score:
			best_score = score
			best_cost = cost
			best_hole_cost = hole_cost
			best_angle = angle
	strain_limb = maxf(strain_limb, best_hole_cost)
	strain = maxf(strain, best_hole_cost)
	_chosen[limb] = best_angle
	_angles[limb] = lerp_angle(_angles[limb], best_angle, smoothing)
	bend = bend * cos(_angles[limb]) + turned * sin(_angles[limb])

	var new_middle: Vector3 = base + bend * height
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


## Calcula cuánto de cada postura pide el hueco y lo escribe en el árbol.
func _update_posture(skeleton: Skeleton3D, passage: Passage, delta: float) -> void:
	var wanted_low: float = 0.0
	var wanted_narrow: float = 0.0
	if passage:
		var to_passage: Transform3D = passage.global_transform.affine_inverse()
		var body: Vector3 = to_passage * skeleton.global_position
		var half_width: float = passage.size.x * 0.5
		var near: float = _get_posture_reach(body.z,
			(to_passage.basis * skeleton.global_basis * _forward).z) \
			* (1.0 - smoothstep(half_width, half_width + maxf(side_margin, 0.001), absf(body.x)))
		var low: float = clampf((standing_height - passage.size.y)
			/ maxf(standing_height - low_height, 0.01) / posture_saturation, 0.0, 1.0)
		var narrow: float = clampf((standing_half_width - half_width)
			/ maxf(standing_half_width - narrow_half_width, 0.01) / posture_saturation, 0.0, 1.0)
		if low > 0.0 and narrow > 0.0 and passage.size.y >= narrow_height - max_drop:
			low = 0.0
			narrow = 1.0
		wanted_low = near * low
		wanted_narrow = near * narrow
	var smoothing: float = 1.0 - exp(-delta / maxf(posture_smoothing, 0.0001))
	low_amount = lerpf(low_amount, wanted_low, smoothing)
	narrow_amount = lerpf(narrow_amount, wanted_narrow, smoothing)
	if tree:
		tree.set(low_parameter, low_amount)
		tree.set(narrow_parameter, narrow_amount)


## Devuelve, de 0 a 1, cuánta postura pide el hueco según dónde está el cuerpo sobre su eje.
func _get_posture_reach(along: float, facing: float) -> float:
	var past: float = along * signf(facing)
	if past > 0.0:
		return 1.0 - smoothstep(release_start, maxf(release_end, release_start + 0.01), past)
	return 1.0 - smoothstep(posture_full, maxf(posture_start, posture_full + 0.01), absf(along))


## Devuelve cuánto se mete en el propio cuerpo un codo o una rodilla en [param point].
func _get_body_cost(point: Vector3, side_axis: Vector3, anchor: Vector3,
		spine_points: PackedVector3Array) -> float:
	var cost: float = 0.0
	if side_axis != Vector3.ZERO:
		cost = maxf(midline_clearance - side_axis.dot(point - anchor), 0.0)
	var nearest: float = INF
	for i: int in spine_points.size() - 1:
		nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(
			point, spine_points[i], spine_points[i + 1])))
	return cost + maxf(body_radius - nearest, 0.0)


## Devuelve, de 0 a 1, cuánto aprieta el hueco a [param point].
func _get_weight(passage: Passage, point: Vector3) -> float:
	return passage.get_influence(point.z, core, fade) * _gate


## Elige cada cierto tiempo el [Passage] más cercano dentro de [code]search_radius[/code].
func _update_passage(skeleton: Skeleton3D, delta: float) -> void:
	_search_left -= delta
	if _search_left > 0.0 and (_passage == null or is_instance_valid(_passage)):
		return
	_search_left = search_interval
	_passage = null
	var origin: Vector3 = skeleton.global_position
	var best: float = search_radius * search_radius
	for node: Node in skeleton.get_tree().get_nodes_in_group(Passage.GROUP):
		var candidate: Passage = node as Passage
		if not candidate:
			continue
		var distance: float = origin.distance_squared_to(candidate.global_position)
		if distance < best:
			best = distance
			_passage = candidate


## Traduce los nombres de huesos a índices y descarta las patas con huesos inexistentes.
func _resolve(skeleton: Skeleton3D) -> bool:
	if skeleton == _resolved_skeleton and skeleton.get_bone_count() == _resolved_bone_count:
		return not _spine.is_empty() or not _chains.is_empty()
	_resolved_skeleton = skeleton
	_resolved_bone_count = skeleton.get_bone_count()
	_spine = PackedInt32Array()
	_spine_clearances = PackedFloat32Array()
	_chains.clear()
	_tips.clear()
	_planted.clear()
	_tip_parents.clear()
	_anchors = PackedInt32Array()
	_sides = PackedFloat32Array()
	_middle_clearances = PackedFloat32Array()
	_hanging = PackedInt32Array()
	if not hanging_prefix.is_empty():
		for index: int in skeleton.get_bone_count():
			var parent: int = skeleton.get_bone_parent(index)
			if skeleton.get_bone_name(index).begins_with(hanging_prefix) and (parent < 0 \
					or not skeleton.get_bone_name(parent).begins_with(hanging_prefix)):
				_hanging.append(index)

	for bone: StringName in spine_bones:
		var index: int = skeleton.find_bone(bone)
		if index < 0:
			push_warning("SqueezeModifier: no existe el hueso de columna '%s'" % bone)
			continue
		_spine.append(index)
		_spine_clearances.append(top_clearance_overrides.get(bone, top_clearance))
	_lateral = Vector3.ZERO
	_forward = Vector3.ZERO
	if _spine.size() >= 2:
		var up: Vector3 = (skeleton.global_transform.basis.inverse() * Vector3.UP).normalized()
		var forward: Vector3 = skeleton.get_bone_global_rest(_spine[_spine.size() - 1]).origin \
			- skeleton.get_bone_global_rest(_spine[0]).origin
		forward -= up * up.dot(forward)
		if forward.length_squared() > 0.000001:
			_forward = forward.normalized()
			_lateral = up.cross(_forward).normalized()
	for limb: SqueezeLimb in limbs:
		if not limb:
			continue
		var chain: PackedInt32Array = PackedInt32Array([skeleton.find_bone(limb.root_bone),
			skeleton.find_bone(limb.middle_bone), skeleton.find_bone(limb.end_bone)])
		var tips: PackedInt32Array = _find_bones(skeleton, limb.tip_bones)
		var planted: PackedInt32Array = _find_bones(skeleton, limb.planted_bones)
		if chain.has(-1) or tips.has(-1) or planted.has(-1):
			push_warning("SqueezeModifier: pata con huesos inexistentes (%s, %s, %s)"
				% [limb.root_bone, limb.middle_bone, limb.end_bone])
			continue
		_chains.append(chain)
		_tips.append(tips)
		_planted.append(planted)
		var parents: PackedInt32Array = PackedInt32Array()
		for index: int in tips:
			parents.append(skeleton.get_bone_parent(index))
		_tip_parents.append(parents)
		_middle_clearances.append(limb.middle_clearance if limb.middle_clearance >= 0.0
			else middle_clearance)
		var anchor: int = skeleton.get_bone_parent(chain[0])
		while anchor >= 0 and not _spine.has(anchor):
			anchor = skeleton.get_bone_parent(anchor)
		_anchors.append(anchor)
		_sides.append(0.0 if anchor < 0 else signf(_lateral.dot(
			skeleton.get_bone_global_rest(chain[0]).origin
			- skeleton.get_bone_global_rest(anchor).origin)))
	_angles.resize(_chains.size())
	_angles.fill(0.0)
	_chosen.resize(_chains.size())
	_chosen.fill(0.0)
	return not _spine.is_empty() or not _chains.is_empty()


## Devuelve los índices de [param names] en [param skeleton]; -1 donde no exista.
func _find_bones(skeleton: Skeleton3D, names: Array[StringName]) -> PackedInt32Array:
	var indices: PackedInt32Array = PackedInt32Array()
	for bone: StringName in names:
		indices.append(skeleton.find_bone(bone))
	return indices
