class_name RoleDatabase
extends Resource

## Registro de todos los [RoleProfile], cargado una sola vez desde [code]DATABASE_PATH[/code].
## Los nombres y la lista de roles del lobby salen de aquí, así que añadir un rol no obliga
## a editar la UI.

const DATABASE_PATH: String = "res://player/data/role_database.tres"

@export var profiles: Array[RoleProfile] = []

static var _instance: RoleDatabase


## Busca el perfil registrado para un rol.
## Recibe: [param role] — rol a buscar.
## Devuelve: el primer [RoleProfile] con ese rol, o [code]null[/code] si no hay ninguno o la
## base no carga.
static func get_profile(role: Statics.Role) -> RoleProfile:
	var database: RoleDatabase = _get_instance()
	if not database:
		return null
	for profile: RoleProfile in database.profiles:
		if profile and profile.role == role:
			return profile
	return null


## Nombre legible de un rol, tomado del [code]display_name[/code] de su perfil.
## Recibe: [param role] — rol a nombrar.
## Devuelve: [code]"None"[/code] para [code]NONE[/code]; [code]"Unknown"[/code] si el rol no
## tiene perfil o su nombre está vacío.
static func get_role_name(role: Statics.Role) -> String:
	if role == Statics.Role.NONE:
		return "None"
	var profile: RoleProfile = get_profile(role)
	if profile and profile.display_name:
		return profile.display_name
	return "Unknown"


## Roles elegibles en el lobby, en orden de registro. La UI debe iterar esto en vez de
## asumir el orden del enum.
## Devuelve: los roles registrados salvo [code]NONE[/code]; vacío si la base no carga.
static func get_selectable_roles() -> Array[Statics.Role]:
	var roles: Array[Statics.Role] = []
	var database: RoleDatabase = _get_instance()
	if not database:
		return roles
	for profile: RoleProfile in database.profiles:
		if profile and profile.role != Statics.Role.NONE:
			roles.append(profile.role)
	return roles


## Olvida la base cacheada; la próxima consulta la vuelve a cargar.
static func reload() -> void:
	_instance = null


## Devuelve: la base cacheada, cargándola de [code]DATABASE_PATH[/code] la primera vez, o
## [code]null[/code] (tras un [code]push_error[/code]) si el archivo no existe.
static func _get_instance() -> RoleDatabase:
	if _instance:
		return _instance
	if not ResourceLoader.exists(DATABASE_PATH):
		push_error("RoleDatabase no encontrada en %s" % DATABASE_PATH)
		return null
	_instance = ResourceLoader.load(DATABASE_PATH) as RoleDatabase
	return _instance
