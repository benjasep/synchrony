class_name Statics
extends Node

## Constantes, enums y tipos compartidos por todo el proyecto.

const MAX_CLIENTS: int = 3
const PORT: int = 5409
const SERVER_ID: int = 1

const WORLD_VISUAL_LAYER: int = 1
const ETHEREAL_VISUAL_LAYER: int = 2
const VIEWMODEL_VISUAL_LAYER: int = 4
const BODY_VISUAL_LAYER: int = 8
const PHYSICAL_ENEMY_VISUAL_LAYER: int = 16
const PICKUP_ECHO_VISUAL_LAYER: int = 32
const PICKUP_MODEL_VISUAL_LAYER: int = 64
const PERCEPTION_MASK_VISUAL_LAYER: int = 524288


## Mueve [param node] y toda su descendencia a la capa visual [param layer].
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
	EVIDENCE,
	CARD_DECK,
}


enum DamageType {
	PHYSICAL = 1,
	ETHEREAL = 2,
}


enum HitZone {
	CUERPO,
	CABEZA,
	PUNTO_DEBIL,
}


enum StimulusKind {
	NOISE,
	PULSE,
	UNSTABLE_LIGHT,
}


## Datos de sesión de un jugador.
class PlayerData:
	var id: int
	var name: String
	var index: int = -1
	var role: Role
	var vote: bool = false

	## Crea los datos de un jugador.
	func _init(new_id: int, new_name: String, new_index: int = -1, new_role: Role = Role.NONE) -> void:
		id = new_id
		name = new_name
		index = new_index
		role = new_role

	## Devuelve una representación legible para depurar.
	func _to_string() -> String:
		return "Player: {id: %d, name: %s, index: %d, role: %d}" % [id, name, index, role]

	## Serializa los datos para enviarlos por la red.
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"index": index,
			"role": role,
			"vote": vote
		}

	## Reconstruye un [code]PlayerData[/code] a partir de [code]to_dict()[/code].
	static func from_dict(data: Dictionary) -> PlayerData:
		var player: PlayerData = PlayerData.new(data.id, data.name, data.index, data.role)
		player.vote = data.vote
		return player

	## Copia nombre, índice, rol y voto de [param player_data] si es el mismo jugador.
	func update(player_data: PlayerData) -> void:
		if id != player_data.id:
			return
		name = player_data.name
		index = player_data.index
		role = player_data.role
		vote = player_data.vote
