class_name Evidence
extends Equipment

## Objeto de misión (informe, carnet…): se recoge con E y se lleva en el inventario como
## cualquier [Equipment], así que si muere quien lo lleva cae al suelo con el resto. No tiene
## uso propio: lo que cuenta es llevarlo encima al llegar a la zona final, y eso lo comprueba
## [MissionDirector]. Su competencia cae al [code]fallback[/code] de [ProficiencyDatabase],
## que lo deja usable para cualquier rol.

## Texto del documento, para cuando exista una forma de leerlo. Todavía no se usa.
@export_multiline var description: String = ""


## Fija el [code]tag[/code] de evidencia como valor por defecto: una escena que herede de este
## script no tiene que acordarse de ponerlo.
func _init() -> void:
	tag = Statics.EquipmentTag.EVIDENCE
