class_name EtherealEntity
extends CharacterBody3D

## Enemigo etéreo. Vive en la capa visual 2, así que solo lo dibuja la segunda
## pasada del vidente: para el técnico y el militar (cull_mask 13) sencillamente
## no está en pantalla, aunque su colisión y su salud sí existan para todos.
##
## Ahí está la asimetría del juego: el enemigo es real para los tres, pero solo
## uno puede decir dónde. Esa es la razón de que la invisibilidad se resuelva
## por capa de render y no ocultando el nodo, que lo borraría también del
## servidor.
##
## Placeholder deliberado: hoy es un cubo. Cuando llegue el modelo de Blender se
## asigna en model_scene y el cubo se oculta solo, igual que hace Player con
## body_scene. No hay que tocar nada más.
##
## Todavía no hay IA ni forma de hacerle daño: HealthComponent está aquí porque
## es genérico a propósito (no extiende PlayerComponent), así que cuando Firearm
## resuelva su impacto ya tiene a quién aplicárselo.

## Capa de colisión 4. La 1 es el mundo, la 2 los jugadores y la 3 los
## Interactable; tener capa propia es lo que permitirá que un disparo distinga a
## quién puede dañar.
const ENEMY_COLLISION_LAYER: int = 8

## Modelo definitivo. Si es null se ve el cubo de referencia.
@export var model_scene: PackedScene

@export_group("Nodos")
@export var model: Node3D
@export var model_placeholder: MeshInstance3D
@export var health: HealthComponent


func _ready() -> void:
	collision_layer = ENEMY_COLLISION_LAYER
	_spawn_model()
	# Después de instanciar el modelo, y sobre model entero: el cubo de
	# referencia también tiene que quedar en la capa etérea, o lo vería todo el
	# mundo. Un .glb importado llega siempre en la capa 1.
	Statics.force_visual_layer(model, Statics.ETHEREAL_VISUAL_LAYER)


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
