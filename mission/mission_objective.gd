class_name MissionObjective
extends Resource

## Un tipo de objeto que la misión esconde en el mapa: qué escena, cuántas copias y en qué
## clase de [ObjectiveZone] puede caer.

## Escena del [Equipment] que hay que encontrar (normalmente una [Evidence]).
@export var item_scene: PackedScene
## Copias que se reparten por el mapa; cada una va a un sitio distinto.
@export var count: int = 1
## Tags de [ObjectiveZone] donde puede aparecer; vacío = en cualquier zona.
@export var allowed_tags: Array[StringName] = []
