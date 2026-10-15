class_name Enemy
extends CharacterBody3D

## Enemigo físico o etéreo: una sola clase concreta, la diferencia es [code]is_ethereal[/code].
## Lo etéreo es solo de RENDER (capa visual 2, que solo dibuja el vidente): nunca se oculta el
## nodo para eso, que lo borraría también del servidor. Los disparos entran por las [Hitbox] de
## su modelo. Al morir se retira (eso sí lo oculta, para todos) y, si [code]respawns[/code],
## vuelve con la vida llena en otro punto. Lo decide el servidor y lo replica por RPC. Sus
## ataques son componentes hermanos de [code]Health[/code] ([EnemyCombat] y los que use), igual
## que su reacción al daño ([HitReaction]); la anatomía que usan (los rigs) viene en el modelo.

signal retreated
signal returned

## Grupo de los marcadores ([Node3D]) donde puede reaparecer un enemigo tras retirarse.
const SPAWN_POINT_GROUP: StringName = &"enemy_spawn"
## Es una máscara: 8 = capa 4, solo la caja de movimiento. El disparo no la mira nunca:
## envuelve las [Hitbox] del modelo y se tragaría el tiro.
const ENEMY_COLLISION_LAYER: int = 8

@export var is_ethereal: bool = false
@export var model_scene: PackedScene

@export_group("Regreso")
@export var respawns: bool = true
@export var respawn_delay: float = 10.0

@export_group("Nodos")
@export var model: Node3D
@export var model_placeholder: MeshInstance3D
@export var collision: CollisionShape3D
@export var health: HealthComponent

## [Hitbox] cableadas a [code]health[/code], las del modelo instanciado incluidas. Solo lectura.
var hitboxes: Array[Hitbox] = []
## [GrabRig] del modelo instanciado, o [code]null[/code] si no trae ninguno. Solo lectura: lo
## busca [code]_ready()[/code] y lo usa [GrabAttack], que no sabe qué modelo es.
var grab_rig: GrabRig = null
## [MeleeRig] del modelo instanciado, o [code]null[/code]. Solo lectura: lo usa [MeleeAttack].
var melee_rig: MeleeRig = null
## [HitReactionRig] del modelo instanciado, o [code]null[/code]. Solo lectura: lo usa
## [HitReaction].
var hit_reaction_rig: HitReactionRig = null
## [code]true[/code] mientras está retirado (muerto y oculto). Solo lectura.
var is_retreated: bool = false

var _initial_transform: Transform3D = Transform3D.IDENTITY


## Fija la capa de colisión de enemigo, recuerda dónde empezó, instancia el modelo, fuerza todo
## [code]model[/code] a su capa visual, cablea las hitboxes, busca los rigs del modelo y arranca
## con la vida llena.
func _ready() -> void:
	collision_layer = ENEMY_COLLISION_LAYER
	_initial_transform = global_transform
	_spawn_model()
	# Después de instanciar el modelo, y sobre model entero: el cubo de
	# referencia también tiene que quedar en su capa. Un .glb importado llega
	# siempre en la 1, así que para un etéreo esto no es opcional: sin ello lo
	# vería todo el mundo.
	Statics.force_visual_layer(model, get_visual_layer())
	_wire_hitboxes()
	if model:
		_find_rigs(model)
	if health:
		# Nadie más configura la salud de un enemigo: sin esto empezaría con los
		# 100 por defecto de current_health, diga lo que diga max_health.
		health.configure(null)
		health.died.connect(_handle_died)


## Devuelve la capa visual de todo el modelo: la etérea si es etéreo, si no la del mundo. Es lo
## único que decide quién lo ve.
func get_visual_layer() -> int:
	return Statics.ETHEREAL_VISUAL_LAYER if is_ethereal else Statics.WORLD_VISUAL_LAYER


## Devuelve los flags de [enum Statics.DamageType] que le hacen daño: el etéreo si es etéreo,
## si no el físico. Es lo que aceptan sus [Hitbox].
func get_damage_types() -> int:
	return Statics.DamageType.ETHEREAL if is_ethereal else Statics.DamageType.PHYSICAL


## Instancia [code]model_scene[/code] bajo [code]model[/code] y oculta el cubo de referencia,
## liberando sus hitboxes. No hace nada si falta alguno de los dos; si la escena no es un
## [Node3D], registra un error y deja el cubo.
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
		# Las hitboxes del cubo miden el cubo: dentro del modelo, que trae las
		# suyas, rellenarían por ejemplo el hueco entre las patas. Ocultar no
		# basta, la física no mira la visibilidad.
		var cube_hitboxes: Array[Hitbox] = []
		_find_hitboxes(model_placeholder, cube_hitboxes)
		for hitbox: Hitbox in cube_hitboxes:
			hitbox.free()


## Busca las [Hitbox] de todo el enemigo, modelo incluido, y les asigna la salud y los tipos de
## daño que lo afectan. Se hace aquí y no por [code]@export[/code]: las del modelo viven en
## otra escena y no pueden apuntar a la salud de esta.
func _wire_hitboxes() -> void:
	hitboxes.clear()
	_find_hitboxes(self, hitboxes)
	for hitbox: Hitbox in hitboxes:
		hitbox.health = health
		hitbox.accepted_damage_types = get_damage_types()


## Añade a [param found] las [Hitbox] de [param node] y de toda su descendencia. Castea con
## [code]as[/code]: [code]find_children()[/code] filtrando por un [code]class_name[/code] de
## script no es fiable.
func _find_hitboxes(node: Node, found: Array[Hitbox]) -> void:
	var hitbox: Hitbox = node as Hitbox
	if hitbox:
		found.append(hitbox)
	for child: Node in node.get_children():
		_find_hitboxes(child, found)


## Busca en una pasada, en [param node] y su descendencia, los rigs de anatomía del modelo
## ([GrabRig], [MeleeRig], [HitReactionRig]) y guarda el primero de cada clase. Mismo motivo que
## [code]_find_hitboxes()[/code] para castear en vez de filtrar por clase.
func _find_rigs(node: Node) -> void:
	if not grab_rig:
		grab_rig = node as GrabRig
	if not melee_rig:
		melee_rig = node as MeleeRig
	if not hit_reaction_rig:
		hit_reaction_rig = node as HitReactionRig
	for child: Node in node.get_children():
		_find_rigs(child)


## En el servidor, retira al enemigo en todos los peers y, si [code]respawns[/code], programa
## su regreso. En los clientes no hace nada: la retirada les llega por RPC.
func _handle_died() -> void:
	if not multiplayer.is_server():
		return
	_retreat.rpc()
	if respawns:
		_return_after_delay()


## Corrutina del servidor: espera [code]respawn_delay[/code] segundos sin contar la pausa, elige
## el punto de regreso, revive la salud (llena) y hace reaparecer al enemigo allí en todos los
## peers. No hace nada si entretanto salió del árbol o ya no está muerto.
func _return_after_delay() -> void:
	await get_tree().create_timer(respawn_delay, false).timeout
	if not is_inside_tree() or not health or not health.is_dead:
		return
	var spawn_transform: Transform3D = _choose_return_transform()
	health.revive()
	_return_at.rpc(spawn_transform)


## Elige dónde reaparecer: entre los nodos del grupo [constant SPAWN_POINT_GROUP], el que quede
## más lejos de los jugadores vivos (cuenta el más cercano de ellos), descartando el marcador
## más próximo a donde se retiró si hay más de uno. Sin jugadores vivos gana el primero.
## Devuelve: posición y orientación del marcador elegido, o el transform inicial del enemigo
## si no hay marcadores.
func _choose_return_transform() -> Transform3D:
	var points: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(SPAWN_POINT_GROUP):
		var point: Node3D = node as Node3D
		if point:
			points.append(point)
	if points.is_empty():
		return _initial_transform
	# No se mueve mientras está retirado: su posición sigue siendo donde cayó.
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


## Devuelve el punto de [param points] más cercano a [param target]; [param points] no puede
## estar vacío.
func _get_closest_point(points: Array[Node3D], target: Vector3) -> Node3D:
	var closest: Node3D = points[0]
	for point: Node3D in points:
		if point.global_position.distance_squared_to(target) \
				< closest.global_position.distance_squared_to(target):
			closest = point
	return closest


## Devuelve la distancia de [param target] a la más cercana de [param positions], o
## [code]INF[/code] si está vacía.
func _get_distance_to_closest(target: Vector3, positions: Array[Vector3]) -> float:
	var closest: float = INF
	for candidate: Vector3 in positions:
		closest = minf(closest, target.distance_to(candidate))
	return closest


## Devuelve la posición global de cada jugador vivo que conoce [PlayerSpawner]; vacío si no hay
## spawner. Salta las entradas ya liberadas: el spawner no las quita al desconectarse nadie.
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


## Retira al enemigo en todos los peers para que no bloquee el paso ni reciba tiros y emite
## [code]retreated[/code]. Lo difunde el servidor al morir.
@rpc("authority", "call_local", "reliable")
func _retreat() -> void:
	_set_present(false)
	retreated.emit()


## Hace reaparecer al enemigo en todos los peers en [param spawn_transform] y emite
## [code]returned[/code]. Lo difunde el servidor después de revivir su salud.
## Recibe: [param spawn_transform] — transform global donde reaparece.
@rpc("authority", "call_local", "reliable")
func _return_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	_set_present(true)
	returned.emit()


## Muestra u oculta el modelo y enciende o apaga la caja de movimiento y las hitboxes.
## Recibe: [param present] — [code]false[/code] al retirarse, [code]true[/code] al volver.
func _set_present(present: bool) -> void:
	is_retreated = not present
	if model:
		model.visible = present
	if collision:
		# Diferido: si la muerte llegase desde un callback de física, cambiar la
		# forma en ese momento está prohibido.
		collision.set_deferred(&"disabled", not present)
	for hitbox: Hitbox in hitboxes:
		hitbox.set_active(present)
