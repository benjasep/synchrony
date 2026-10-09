class_name Credits
extends Control

@onready var back_button: Button = %BackButton

## Conecta «Atrás» para volver al menú principal.
func _ready() -> void:
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/main_menu.tscn"))
