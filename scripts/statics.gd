class_name Statics
extends Node

## Constantes, enums y tipos compartidos por todo el proyecto. No depende de ninguna otra
## clase a propósito: [RoleProfile] y [RoleDatabase] la referencian, y una referencia de
## vuelta crearía una dependencia cíclica.

const MAX_CLIENTS: int = 3
const PORT: int = 5409 # Number between 1024 and 65535.
const SERVER_ID: int = 1

const WORLD_VISUAL_LAYER: int = 1      ## Máscara de la capa 1: mundo y enemigos físicos.
const ETHEREAL_VISUAL_LAYER: int = 2   ## Máscara de la capa 2: enemigos etéreos.
const VIEWMODEL_VISUAL_LAYER: int = 4  ## Máscara de la capa 3: item empuñado.
const BODY_VISUAL_LAYER: int = 8       ## Máscara de la capa 4: cuerpos de otros jugadores.


## Mueve [param node] y toda su descendencia a una capa visual. Existe porque un .glb siempre
## se importa en la capa 1, que el vidente solo ve como eco, y reexportar desde Blender
## deshace los cambios hechos en el editor. Solo toca [GeometryInstance3D] a propósito: la
## capa de una [Light3D] decide a qué ilumina.
## Recibe: [param node] — raíz a mover (no hace nada si es [code]null[/code]);
## [param layer] — máscara, una de las constantes [code]*_VISUAL_LAYER[/code].
static func force_visual_layer(node: Node, layer: int) -> void:
	if not node:
		return
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry:
		geometry.layers = layer
	for child: Node in node.get_children():
		force_visual_layer(child, layer)


enum Role {
	NONE,
	SEER,
	TECHNICIAN,
	SOLDIER,
}


enum EquipmentTag {
	NONE,
	FIREARM,
	LIGHT_SOURCE,
	LOCKPICK,
	MAP,
	RITUAL_TOOL,
}


## Flags: cada valor nuevo debe ser potencia de dos (un arma puede dañar a varios tipos).
enum DamageType {
	PHYSICAL = 1,
	ETHEREAL = 2,
}


class PlayerData:
	var id: int
	var name: String
	# Position relative to other players
	var index: int = -1
	var role: Role
	var vote: bool = false
	
	## Crea los datos de un jugador.
	## Recibe: [param new_id] — su peer id; [param new_name] — nombre visible;
	## [param new_index] — posición en la lista ([code]-1[/code] = aún sin asignar);
	## [param new_role] — rol elegido.
	func _init(new_id: int, new_name: String, new_index: int = -1, new_role: Role = Role.NONE) -> void:
		id = new_id
		name = new_name
		index = new_index
		role = new_role
	
	## Devuelve una representación legible para depurar (no incluye el voto).
	func _to_string() -> String:
		return "Player: {id: %d, name: %s, index: %d, role: %d}" % [id, name, index, role]
	
	## Serializa los datos para enviarlos por RPC o como datos de spawn.
	## Devuelve: un diccionario con id, nombre, índice, rol y voto.
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"index": index,
			"role": role,
			"vote": vote
		}
	
	## Reconstruye un [code]PlayerData[/code] a partir de [code]to_dict()[/code].
	## Recibe: [param data] — diccionario con todas las claves de [code]to_dict()[/code].
	## Devuelve: una instancia nueva.
	static func from_dict(data: Dictionary) -> PlayerData:
		var player: PlayerData = PlayerData.new(data.id, data.name, data.index, data.role)
		player.vote = data.vote
		return player
	
	## Copia nombre, índice, rol y voto de [param player_data]; no hace nada si su id no
	## coincide con el de este jugador.
	func update(player_data: PlayerData) -> void:
		if id != player_data.id:
			return
		name = player_data.name
		index = player_data.index
		role = player_data.role
		vote = player_data.vote
