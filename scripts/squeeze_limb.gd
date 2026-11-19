class_name SqueezeLimb
extends Resource

## Una pata para [SqueezeModifier]: su cadena de dos huesos, sus puntas y los huesos con que pisa.

## Hueso raíz de la cadena.
@export var root_bone: StringName
## Hueso medio de la cadena: el codo o la rodilla.
@export var middle_bone: StringName
## Hueso final de la cadena.
@export var end_bone: StringName
## Puntas de dedos y garras que no pueden asomar del hueco.
@export var tip_bones: Array[StringName] = []
## Metros de radio de malla alrededor del codo o la rodilla; negativo, el del modificador.
@export var middle_clearance: float = -1.0
## Huesos que pisan, hijos del hueso final.
@export var planted_bones: Array[StringName] = []
