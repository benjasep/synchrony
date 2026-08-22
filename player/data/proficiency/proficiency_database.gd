class_name ProficiencyDatabase
extends Resource

## Perfiles de competencia por defecto ("sin entrenamiento") para cada familia
## de equipamiento.
##
## Existe para que añadir un item nuevo NO obligue a editar el .tres de todos
## los roles: un rol declara solo sus excepciones y el resto cae aquí.

const DATABASE_PATH: String = "res://player/data/proficiency_database.tres"

## Un perfil por EquipmentTag. El primero que coincida gana.
@export var defaults: Array[ProficiencyProfile] = []

## Último recurso si un tag no tiene default declarado.
@export var fallback: ProficiencyProfile

static var _instance: ProficiencyDatabase


static func get_default(tag: Statics.EquipmentTag) -> ProficiencyProfile:
	var database: ProficiencyDatabase = _get_instance()
	if not database:
		return null
	for profile: ProficiencyProfile in database.defaults:
		if profile and profile.tag == tag:
			return profile
	return database.fallback


static func reload() -> void:
	_instance = null


static func _get_instance() -> ProficiencyDatabase:
	if _instance:
		return _instance
	if not ResourceLoader.exists(DATABASE_PATH):
		push_error("ProficiencyDatabase no encontrada en %s" % DATABASE_PATH)
		return null
	_instance = ResourceLoader.load(DATABASE_PATH) as ProficiencyDatabase
	return _instance
