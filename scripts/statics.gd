class_name Statics
extends Node


const MAX_CLIENTS: int = 3
const PORT: int = 5409 # Number between 1024 and 65535.
## Peer id del servidor. Autoridad de todo lo que es estado del mundo.
const SERVER_ID: int = 1


## Statics no depende de nada a propósito: RoleProfile y RoleDatabase la
## referencian, así que si ella los referenciara de vuelta habría dependencia
## cíclica. Por eso get_role_name() vive ahora en RoleDatabase.
enum Role {
	NONE,
	SEER,        ## Vidente: ciego al mundo físico, ve entidades etéreas.
	TECHNICIAN,  ## Técnico: linterna, y a futuro mapa y ganzúas.
	SOLDIER,     ## Militar: armas contra enemigos físicos y etéreos.
}


## Familia de equipamiento. Un item declara su tag; un rol declara su
## competencia por tag. Ninguno de los dos conoce al otro.
enum EquipmentTag {
	NONE,
	FIREARM,
	LIGHT_SOURCE,
	LOCKPICK,     ## Fuera de scope por ahora; el tag no cuesta nada.
	MAP,          ## Idem.
	RITUAL_TOOL,
}


## Flags, no enum secuencial: un arma puede dañar a ambos tipos a la vez.
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
	
	func _init(new_id: int, new_name: String, new_index: int = -1, new_role: Role = Role.NONE) -> void:
		id = new_id
		name = new_name
		index = new_index
		role = new_role
	
	func _to_string() -> String:
		return "Player: {id: %d, name: %s, index: %d, role: %d}" % [id, name, index, role]
	
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"index": index,
			"role": role,
			"vote": vote
		}
	
	static func from_dict(data: Dictionary) -> PlayerData:
		var player: PlayerData = PlayerData.new(data.id, data.name, data.index, data.role)
		player.vote = data.vote
		return player
	
	func update(player_data: PlayerData) -> void:
		if id != player_data.id:
			return
		name = player_data.name
		index = player_data.index
		role = player_data.role
		vote = player_data.vote
