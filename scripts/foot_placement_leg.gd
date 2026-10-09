class_name FootPlacementLeg
extends Resource

## Una pata para [FootPlacement]: la cadena de dos huesos que resuelve el IK (raíz, medio y
## final) más el hueso que pisa el suelo, bajo el que se lanza el raycast.

@export var root_bone: StringName
@export var middle_bone: StringName
@export var end_bone: StringName
@export var contact_bone: StringName
@export var is_front: bool = false
