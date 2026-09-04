class_name RoleProfile
extends Resource

## Todo lo que distingue a un rol de otro, como datos.
##
## Es el único punto de variación entre roles: Player es una clase concreta sin
## subclases. Añadir un rol es crear un .tres y registrarlo en RoleDatabase; no
## debería requerir tocar código.

@export var role: Statics.Role = Statics.Role.NONE
@export var display_name: String = ""
@export var icon: Texture2D

@export_group("Movimiento")
@export var move_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var jump_velocity: float = 4.5

@export_group("Cuerpo")
## Modelo visible del cuerpo. Player lo instancia bajo su nodo Body, así que el
## dueño no se lo ve a sí mismo (primera persona) pero los demás sí.
##
## Apunta a una .tscn envoltorio, no al .glb directo: ahí es donde se ajustan
## escala y posición del modelo sin tocar código, y reexportar desde Blender no
## se lleva por delante el ajuste. Hoy los tres roles comparten envoltorio;
## darle cuerpo propio a un rol es cambiar esta línea en su .tres.
@export var body_scene: PackedScene
## Altura de la cámara sobre los pies. Va aquí y no en player.tscn porque tiene
## que cuadrar con la altura de body_scene: si un rol estrena modelo, la cámara
## se ajusta en su .tres sin tocar la escena compartida.
@export var eye_height: float = 1.6
## Cápsula de colisión, también atada al modelo. El alto es el total (Godot ya
## cuenta los dos casquetes) y nunca puede ser menor que el diámetro.
@export var body_height: float = 1.8
@export var body_radius: float = 0.4

@export_group("Salud")
@export var max_health: float = 100.0

@export_group("Percepción")
@export var vision_mode: VisionMode

@export_group("Equipamiento")
## Items con los que aparece. Son objetos normales: se pueden soltar y recoger.
@export var starting_equipment: Array[PackedScene] = []
## Excepciones de competencia. Lo no declarado cae a ProficiencyDatabase.
@export var proficiencies: Array[ProficiencyProfile] = []

@export_group("Escenas")
## Habilidad innata. A diferencia del equipamiento, NO es transferible.
@export var ability_scene: PackedScene
@export var hud_scene: PackedScene


## Competencia de este rol con una familia de items. Nunca devuelve null salvo
## que la base de datos esté mal configurada.
func get_proficiency(tag: Statics.EquipmentTag) -> ProficiencyProfile:
	for profile: ProficiencyProfile in proficiencies:
		if profile and profile.tag == tag:
			return profile
	return ProficiencyDatabase.get_default(tag)
