class_name FirearmDebugAim
extends Node3D

## Rayo azul del modo debug de combate: de la boca de un [Firearm] al punto al que apunta la
## cámara de su portador, con un marcador pequeño en ese punto si toca algo. Lo crea el arma, y
## solo en el peer de quien la empuña mientras el modo está encendido; al apagarlo o soltar el
## arma se libera, así que apagado no procesa nada. El rayo real del disparo sale de la cámara y
## desde ella se vería como un punto: dibujado desde la boca, converge con él en el punto
## apuntado. No lleva dispersión: marca dónde se apunta, y el trazo rojo del disparo, dónde fue.

var firearm: Firearm = null

var _aim_point: Vector3 = Vector3.ZERO
var _has_aim: bool = false
var _hit_something: bool = false
var _beam: MeshInstance3D = null
var _marker: MeshInstance3D = null


## Recibe: [param aimed_firearm] — el arma cuyo apuntado dibuja.
func _init(aimed_firearm: Firearm) -> void:
	name = "CombatDebugAim"
	firearm = aimed_firearm
	# Coordenadas globales: el rayo no debe heredar la pose del arma.
	top_level = true


## Monta el rayo y el marcador, ocultos hasta el primer cálculo del punto apuntado.
func _ready() -> void:
	_beam = CombatDebugOverlay.make_beam(CombatDebugOverlay.AIM_COLOR, CombatDebugOverlay.AIM_HALF_WIDTH)
	_beam.hide()
	add_child(_beam)
	_marker = CombatDebugOverlay.make_marker(CombatDebugOverlay.AIM_COLOR, CombatDebugOverlay.AIM_MARKER_RADIUS)
	_marker.hide()
	add_child(_marker)


## Devuelve el punto apuntado: lo primero que tocaría el rayo del disparo sin dispersión, o el
## final del alcance si no toca nada.
func get_aim_point() -> Vector3:
	return _aim_point


## Devuelve [code]true[/code] si el último punto apuntado es un impacto y no el final del alcance.
func is_hitting_something() -> bool:
	return _hit_something


## Calcula el punto apuntado con un rayo local igual que el del disparo (misma máscara, con
## áreas y sin el portador), pero sin dispersión y sin aplicar nada. En el frame de física,
## que es donde se puede consultar el espacio.
## Recibe: [param _delta] — sin usar.
func _physics_process(_delta: float) -> void:
	var shooter: Player = firearm.wielder if firearm else null
	if not shooter:
		_has_aim = false
		return
	var origin: Vector3 = shooter.get_aim_origin()
	var far_end: Vector3 = origin + shooter.get_aim_direction() * firearm.range_meters
	var exclude: Array[RID] = [shooter.get_rid()]
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, far_end, Firearm.SHOT_COLLISION_MASK, exclude)
	query.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	_hit_something = not hit.is_empty()
	_aim_point = far_end
	if _hit_something:
		_aim_point = hit["position"]
	_has_aim = true


## Coloca el rayo de la boca del arma al punto apuntado cada frame de render, para que no
## tiemble con la cámara entre dos frames de física.
## Recibe: [param _delta] — sin usar.
func _process(_delta: float) -> void:
	if not _has_aim or not firearm:
		_beam.hide()
		_marker.hide()
		return
	CombatDebugOverlay.place_beam(_beam, firearm.get_muzzle_position(), _aim_point)
	_marker.position = _aim_point
	_marker.visible = _hit_something
