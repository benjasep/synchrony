class_name RoleDatabase
extends Resource

## Registro de todos los RoleProfile. Sustituye al match hardcodeado que había
## en Statics.get_role_name(): nombres, iconos y la lista de roles del lobby
## salen de aquí, así que añadir un rol no obliga a editar la UI.

const DATABASE_PATH: String = "res://player/data/role_database.tres"

@export var profiles: Array[RoleProfile] = []

static var _instance: RoleDatabase


static func get_profile(role: Statics.Role) -> RoleProfile:
	var database: RoleDatabase = _get_instance()
	if not database:
		return null
	for profile: RoleProfile in database.profiles:
		if profile and profile.role == role:
			return profile
	return null


## Nombre legible de un rol. Reemplaza a Statics.get_role_name().
static func get_role_name(role: Statics.Role) -> String:
	if role == Statics.Role.NONE:
		return "None"
	var profile: RoleProfile = get_profile(role)
	if profile and profile.display_name:
		return profile.display_name
	return "Unknown"


## Roles seleccionables, en orden de registro. La UI del lobby debe iterar esto
## en vez de asumir el orden del enum.
static func get_selectable_roles() -> Array[Statics.Role]:
	var roles: Array[Statics.Role] = []
	var database: RoleDatabase = _get_instance()
	if not database:
		return roles
	for profile: RoleProfile in database.profiles:
		if profile and profile.role != Statics.Role.NONE:
			roles.append(profile.role)
	return roles


static func reload() -> void:
	_instance = null


static func _get_instance() -> RoleDatabase:
	if _instance:
		return _instance
	if not ResourceLoader.exists(DATABASE_PATH):
		push_error("RoleDatabase no encontrada en %s" % DATABASE_PATH)
		return null
	_instance = ResourceLoader.load(DATABASE_PATH) as RoleDatabase
	return _instance
