class_name ObjectiveZone
extends Node3D

## Marcador de mapa: un lugar donde la misión puede esconder objetos (una casa, la capilla…).
## Los sitios candidatos son sus hijos [Marker3D] directos, y el reparto lo decide
## [MissionDirector] en el servidor. Se mete sola en su grupo, así que también funciona dentro
## de un prefab: si una casa trae su zona, cada casa que se ponga en el mapa es una zona más.

const GROUP: StringName = &"objective_zone"

## Qué clase de lugar es. [member MissionObjective.allowed_tags] restringe los objetos a
## ciertos tags.
@export var tag: StringName = &""


## Se registra en el grupo [code]objective_zone[/code], que es donde la busca el director.
func _enter_tree() -> void:
	add_to_group(GROUP)


## Devuelve los sitios donde puede aparecer un objeto: sus hijos [Marker3D] directos, en el
## orden del árbol. Funciona aunque la zona aún no esté en el árbol.
func get_sites() -> Array[Marker3D]:
	var sites: Array[Marker3D] = []
	for child: Node in get_children():
		var site: Marker3D = child as Marker3D
		if site:
			sites.append(site)
	return sites
