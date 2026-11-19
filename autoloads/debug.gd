extends Node

## Autoload de depuración: mensajes en pantalla, título de la ventana por peer y las vistas de
## depuración de combate (F9) y de la IA (F10).

signal combat_debug_toggled(enabled: bool)
signal ai_debug_toggled(enabled: bool)

const COMBAT_DEBUG_ACTION: StringName = &"debug_combat"
const AI_DEBUG_ACTION: StringName = &"debug_ai"

@onready var canvas_layer: CanvasLayer  = CanvasLayer.new()
@onready var container: VBoxContainer = VBoxContainer.new()

var index: int = 0
var window_title: String = ""
var combat_debug: CombatDebugOverlay = null
var ai_debug: AIDebugOverlay = null


## Monta la capa de mensajes en pantalla y guarda el título original de la ventana.
func _ready() -> void:
	if not OS.is_debug_build():
		set_process_unhandled_input(false)
		return
	add_child(canvas_layer)
	canvas_layer.layer = 128
	canvas_layer.add_child(container)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window_title = get_window().title


## Muestra un mensaje en pantalla en todos los peers y lo imprime en consola.
func log(message: Variant, seconds: float = 2) -> void:
	if not OS.is_debug_build():
		return
	if is_online():
		var prefix: String = _get_prefix()
		print_rich("[b]%s:[/b] " % prefix, message)
		add_message.rpc("%s: %s" % [prefix, str(message)], seconds)
	else:
		add_message(str(message), seconds)
		print(message)


## Añade un mensaje arriba de la pila y lo borra pasados [param seconds] segundos.
@rpc("any_peer", "reliable", "call_local")
func add_message(message: String, seconds: float) -> void:
	var label: Label = Label.new()
	label.text = message
	label.set("theme_override_constants/outline_size", 2)
	label.set("theme_override_colors/font_outline_color", Color.BLACK)
	container.add_child(label)
	container.move_child(label, 0)
	await get_tree().create_timer(seconds).timeout
	container.remove_child(label)
	label.queue_free()


## Añade [param text] al título original de la ventana.
func add_to_window_title(text: String) -> void:
	if not OS.is_debug_build():
		return
	get_window().title = "%s - %s" % [window_title, text]


## Restaura el título original de la ventana.
func reset_window_title() -> void:
	get_window().title = window_title


## Devuelve [code]true[/code] si el modo debug de combate está encendido en este peer.
func is_combat_debug_enabled() -> bool:
	return combat_debug != null


## Enciende o apaga el modo debug de combate en este peer.
func set_combat_debug(enabled: bool) -> void:
	if not OS.is_debug_build() or enabled == is_combat_debug_enabled():
		return
	if enabled:
		combat_debug = CombatDebugOverlay.new()
		combat_debug.name = "CombatDebug"
		add_child(combat_debug)
	else:
		remove_child(combat_debug)
		combat_debug.queue_free()
		combat_debug = null
	combat_debug_toggled.emit(enabled)
	self.log("Debug de combate %s (F9)" % ("activado" if enabled else "desactivado"))


## Devuelve [code]true[/code] si la vista de depuración de la IA está encendida en este peer.
func is_ai_debug_enabled() -> bool:
	return ai_debug != null


## Enciende o apaga la vista de depuración de la IA en este peer.
func set_ai_debug(enabled: bool) -> void:
	if not OS.is_debug_build() or enabled == is_ai_debug_enabled():
		return
	if enabled:
		ai_debug = AIDebugOverlay.new()
		ai_debug.name = "AIDebug"
		add_child(ai_debug)
	else:
		remove_child(ai_debug)
		ai_debug.queue_free()
		ai_debug = null
	ai_debug_toggled.emit(enabled)
	self.log("Debug de IA %s (F10)" % ("activado" if enabled else "desactivado"))


## Alterna las vistas de depuración con sus teclas.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(COMBAT_DEBUG_ACTION):
		set_combat_debug(not is_combat_debug_enabled())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(AI_DEBUG_ACTION):
		set_ai_debug(not is_ai_debug_enabled())
		get_viewport().set_input_as_handled()


## Devuelve [code]true[/code] si hay un peer de red real conectado.
func is_online() -> bool:
	return multiplayer.multiplayer_peer and \
		not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and \
		multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Devuelve la etiqueta del peer local para los mensajes.
func _get_prefix() -> String:
	if multiplayer.is_server():
		return "Server"
	elif index:
		return "Client %d" % index
	else:
		return "Client"
