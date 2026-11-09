class_name MainMenu
extends Control


@onready var host: Button = %Host
@onready var join: Button = %Join
@onready var credits: Button = %Credits
@onready var quit: Button = %Quit
@onready var level_tabs: HBoxContainer = %LevelTabs


## Con [code]Game.multiplayer_test[/code] activo salta al arnés lobby_test; si no, conecta los
## pestañas de mapa y los botones para jugar.
func _ready() -> void:
	if Game.instance.multiplayer_test:
		get_tree().change_scene_to_file.call_deferred("res://lobby/lobby_test.tscn")
		return
	_build_level_tabs()
	quit.pressed.connect(func() -> void: get_tree().quit())
	host.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://lobby/host_screen.tscn"))
	join.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://lobby/join_screen.tscn"))
	credits.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/credits.tscn"))
	
	host.grab_focus()


func _build_level_tabs() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	var previous_selection: StringName = Game.instance.selected_level
	for level_name: StringName in Game.instance.playable_levels:
		var tab: Button = Button.new()
		tab.text = level_name
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		tab.button_group = group
		tab.pressed.connect(func() -> void: Game.instance.selected_level = level_name)
		level_tabs.add_child(tab)
		if not group.get_pressed_button() or level_name == previous_selection:
			tab.button_pressed = true
			Game.instance.selected_level = level_name
