class_name ProficiencyDatabase
extends Resource

## Perfiles de competencia por defecto ("sin entrenamiento") por familia de equipamiento.
## Existe para que un item nuevo no obligue a editar el .tres de cada rol: un rol declara
## solo sus excepciones y el resto cae aquí.

const DATABASE_PATH: String = "res://player/data/proficiency_database.tres"

@export var defaults: Array[ProficiencyProfile] = []

@export var fallback: ProficiencyProfile

static var _instance: ProficiencyDatabase


## Busca el perfil por defecto de una familia de items.
## Recibe: [param tag] — familia del item.
## Devuelve: el primer perfil de [code]defaults[/code] con ese tag; si no hay ninguno,
## [code]fallback[/code], que puede ser [code]null[/code]. También [code]null[/code] si la
## base no carga.
static func get_default(tag: Statics.EquipmentTag) -> ProficiencyProfile:
	var database: ProficiencyDatabase = _get_instance()
	if not database:
		return null
	for profile: ProficiencyProfile in database.defaults:
		if profile and profile.tag == tag:
			return profile
	return database.fallback


## Olvida la base cacheada; la próxima consulta la vuelve a cargar.
static func reload() -> void:
	_instance = null


## Devuelve: la base cacheada, cargándola de [code]DATABASE_PATH[/code] la primera vez, o
## [code]null[/code] (tras un [code]push_error[/code]) si el archivo no existe.
static func _get_instance() -> ProficiencyDatabase:
	if _instance:
		return _instance
	if not ResourceLoader.exists(DATABASE_PATH):
		push_error("ProficiencyDatabase no encontrada en %s" % DATABASE_PATH)
		return null
	_instance = ResourceLoader.load(DATABASE_PATH) as ProficiencyDatabase
	return _instance
