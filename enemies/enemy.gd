class_name Enemy
extends CharacterBody3D

## Enemigo físico o etéreo: una sola clase concreta, la diferencia es [code]is_ethereal[/code].
## Lo etéreo es solo de RENDER (capa visual 2, que solo dibuja el vidente): nunca se oculta el
## nodo, que lo borraría también del servidor.

const ENEMY_COLLISION_LAYER: int = 8

@export var is_ethereal: bool = false
@export var model_scene: PackedScene

@export_group("Nodos")
@export var model: Node3D
@export var model_placeholder: MeshInstance3D
@export var health: HealthComponent


## Fija la capa de colisión de enemigo, instancia el modelo y fuerza todo [code]model[/code],
## cubo de referencia incluido, a su capa visual.
func _ready() -> void:
	collision_layer = ENEMY_COLLISION_LAYER
	_spawn_model()
	# Después de instanciar el modelo, y sobre model entero: el cubo de
	# referencia también tiene que quedar en su capa. Un .glb importado llega
	# siempre en la 1, así que para un etéreo esto no es opcional: sin ello lo
	# vería todo el mundo.
	Statics.force_visual_layer(model, get_visual_layer())


## Devuelve la capa visual de todo el modelo: la etérea si es etéreo, si no la del mundo. Es lo
## único que decide quién lo ve.
func get_visual_layer() -> int:
	return Statics.ETHEREAL_VISUAL_LAYER if is_ethereal else Statics.WORLD_VISUAL_LAYER


## Instancia [code]model_scene[/code] bajo [code]model[/code] y oculta el cubo de referencia.
## No hace nada si falta alguno de los dos; si la escena no es un [Node3D], registra un error y
## deja el cubo.
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
