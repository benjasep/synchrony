class_name Enemy
extends CharacterBody3D

## Enemigo físico o etéreo: una sola clase concreta, la diferencia es [code]is_ethereal[/code].

signal retreated
signal returned

const SPAWN_POINT_GROUP: StringName = &"enemy_spawn"
const ENEMY_COLLISION_LAYER: int = 8

## Si es etéreo: solo lo ve el vidente y solo le hace daño lo etéreo.
@export var is_ethereal: bool = false
## Escena del modelo; sin ella es un cubo de referencia.
@export var model_scene: PackedScene

@export_group("Regreso")
## Si vuelve tras retirarse.
@export var respawns: bool = true
## Segundos que tarda en volver tras retirarse.
@export var respawn_delay: float = 10.0

@export_group("Nodos")
@export var model: Node3D
@export var model_placeholder: MeshInstance3D
@export var collision: CollisionShape3D
@export var squeeze_collision: CollisionShape3D
@export var health: HealthComponent
@export var synchronizer: MultiplayerSynchronizer

var hitboxes: Array[Hitbox] = []
var grab_rig: GrabRig = null
var melee_rig: MeleeRig = null
var hit_reaction_rig: HitReactionRig = null
var is_retreated: bool = false
var is_squeezing: bool = false

var _initial_transform: Transform3D = Transform3D.IDENTITY


## Prepara la colisión, el modelo, las hitboxes, los rigs, la salud y el filtro de réplica.
func _ready() -> void:
	collision_layer = ENEMY_COLLISION_LAYER
	_initial_transform = global_transform
	_spawn_model()
	Statics.force_visual_layer(model, get_visual_layer())
	_wire_hitboxes()
	if model:
		_find_rigs(model)
	if health:
		health.configure(null)
		health.died.connect(_handle_died)
	if synchronizer:
		synchronizer.add_visibility_filter(can_sync_to)


## Devuelve [code]true[/code] si el servidor puede sincronizar con [param peer_id].
func can_sync_to(peer_id: int) -> bool:
	var spawner: PlayerSpawner = PlayerSpawner.instance
	return spawner == null or spawner.has_peer_loaded_level(peer_id)


## Devuelve la capa visual del modelo.
func get_visual_layer() -> int:
	return Statics.ETHEREAL_VISUAL_LAYER if is_ethereal else Statics.PHYSICAL_ENEMY_VISUAL_LAYER


## Devuelve los tipos de daño ([enum Statics.DamageType]) que le afectan.
func get_damage_types() -> int:
	return Statics.DamageType.ETHEREAL if is_ethereal else Statics.DamageType.PHYSICAL


## Instancia [code]model_scene[/code] y oculta el cubo de referencia con sus hitboxes.
func _spawn_model() -> void:
	if not model or not model_scene:
		return
	var instance: Node3D = model_scene.instantiate() as Node3D
	if not instance:
		push_error("model_scene de %s no es un Node3D" % name)
		return
	model.add_child(instance)
	if model_placeholder:
		model_placeholder.hide()
		var cube_hitboxes: Array[Hitbox] = []
		_find_hitboxes(model_placeholder, cube_hitboxes)
		for hitbox: Hitbox in cube_hitboxes:
			hitbox.free()


## Asigna la salud y los tipos de daño a todas sus [Hitbox].
func _wire_hitboxes() -> void:
	hitboxes.clear()
	_find_hitboxes(self, hitboxes)
	for hitbox: Hitbox in hitboxes:
		hitbox.health = health
		hitbox.accepted_damage_types = get_damage_types()


## Añade a [param found] las [Hitbox] de [param node] y de su descendencia.
func _find_hitboxes(node: Node, found: Array[Hitbox]) -> void:
	var hitbox: Hitbox = node as Hitbox
	if hitbox:
		found.append(hitbox)
	for child: Node in node.get_children():
		_find_hitboxes(child, found)


## Busca en [param node] y su descendencia los rigs de anatomía del modelo.
func _find_rigs(node: Node) -> void:
	if not grab_rig:
		grab_rig = node as GrabRig
	if not melee_rig:
		melee_rig = node as MeleeRig
	if not hit_reaction_rig:
		hit_reaction_rig = node as HitReactionRig
	for child: Node in node.get_children():
		_find_rigs(child)


## Cambia entre la caja de movimiento normal y la de colarse.
func set_squeezing(active: bool) -> void:
	if is_squeezing == active:
		return
	is_squeezing = active
	_update_collision()


## Retira al enemigo en todos los peers y programa su regreso; solo en el servidor.
func retreat() -> bool:
	if not multiplayer.is_server() or is_retreated:
		return false
	_retreat.rpc()
	if respawns:
		_return_after_delay()
	return true


## Se retira al quedarse sin vida.
func _handle_died() -> void:
	retreat()


## Espera [code]respawn_delay[/code], le llena la vida y lo hace reaparecer en todos los peers.
func _return_after_delay() -> void:
	await get_tree().create_timer(respawn_delay, false).timeout
	if not is_inside_tree() or not is_retreated:
		return
	var spawn_transform: Transform3D = _choose_return_transform()
	if health:
		if health.is_dead:
			health.revive()
		else:
			health.heal(health.max_health)
	_return_at.rpc(spawn_transform)


## Elige dónde reaparecer: el punto de regreso más lejos de los jugadores vivos.
func _choose_return_transform() -> Transform3D:
	var points: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(SPAWN_POINT_GROUP):
		var point: Node3D = node as Node3D
		if point:
			points.append(point)
	if points.is_empty():
		return _initial_transform
	if points.size() > 1:
		points.erase(_get_closest_point(points, global_position))

	var player_positions: Array[Vector3] = _get_living_player_positions()
	var best: Node3D = points[0]
	var best_distance: float = -INF
	for point: Node3D in points:
		var distance: float = _get_distance_to_closest(point.global_position, player_positions)
		if distance > best_distance:
			best = point
			best_distance = distance
	return best.global_transform.orthonormalized()


## Devuelve el punto de [param points] más cercano a [param target].
func _get_closest_point(points: Array[Node3D], target: Vector3) -> Node3D:
	var closest: Node3D = points[0]
	for point: Node3D in points:
		if point.global_position.distance_squared_to(target) \
				< closest.global_position.distance_squared_to(target):
			closest = point
	return closest


## Devuelve la distancia de [param target] a la más cercana de [param positions].
func _get_distance_to_closest(target: Vector3, positions: Array[Vector3]) -> float:
	var closest: float = INF
	for candidate: Vector3 in positions:
		closest = minf(closest, target.distance_to(candidate))
	return closest


## Devuelve la posición global de cada jugador vivo.
func _get_living_player_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if not PlayerSpawner.instance:
		return positions
	for value: Variant in PlayerSpawner.instance.players.values():
		if not is_instance_valid(value):
			continue
		var player: Player = value as Player
		if player and player.is_inside_tree() and player.health and not player.health.is_dead:
			positions.append(player.global_position)
	return positions


## Retira al enemigo en este peer y emite [code]retreated[/code].
@rpc("authority", "call_local", "reliable")
func _retreat() -> void:
	_set_present(false)
	retreated.emit()


## Hace reaparecer al enemigo en [param spawn_transform] y emite [code]returned[/code].
@rpc("authority", "call_local", "reliable")
func _return_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	is_squeezing = false
	_set_present(true)
	returned.emit()


## Muestra u oculta el modelo y activa o desactiva la colisión y las hitboxes.
func _set_present(present: bool) -> void:
	is_retreated = not present
	if model:
		model.visible = present
	_update_collision()
	for hitbox: Hitbox in hitboxes:
		hitbox.set_active(present)


## Activa la caja de movimiento que corresponde: ninguna, la de colarse o la normal.
func _update_collision() -> void:
	var squeezed: bool = is_squeezing and squeeze_collision != null
	if collision:
		collision.set_deferred(&"disabled", is_retreated or squeezed)
	if squeeze_collision:
		squeeze_collision.set_deferred(&"disabled", is_retreated or not squeezed)
