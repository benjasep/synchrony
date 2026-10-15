extends Node

## Autoload de depuración (sin [code]class_name[/code]; se usa directamente como
## [code]Debug[/code]): mensajes en pantalla replicados a todos los peers, título de la
## ventana marcado con Server / Client N y el modo debug de combate (F9). En builds de release
## casi todo es no-op.

## Se emite en este peer al encender o apagar el modo debug de combate.
signal combat_debug_toggled(enabled: bool)

## Acción de input (F9) que enciende y apaga el modo debug de combate.
const COMBAT_DEBUG_ACTION: StringName = &"debug_combat"

@onready var canvas_layer: CanvasLayer  = CanvasLayer.new()
@onready var container: VBoxContainer = VBoxContainer.new()

var index: int = 0
var window_title: String = ""
## Visuales del modo debug de combate mientras está encendido; [code]null[/code] si está
## apagado. Solo lectura: se cambia con [code]set_combat_debug()[/code].
var combat_debug: CombatDebugOverlay = null


## Monta la capa de mensajes en pantalla (por encima de todo y sin capturar el ratón) y guarda
## el título original de la ventana. En builds de release no hace nada y ni siquiera escucha
## la tecla del modo debug de combate.
func _ready() -> void:
	if not OS.is_debug_build():
		set_process_unhandled_input(false)
		return
	add_child(canvas_layer)
	canvas_layer.layer = 128
	canvas_layer.add_child(container)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window_title = get_window().title


## Muestra un mensaje en pantalla y lo imprime en consola. Con sesión de red conectada le
## antepone Server / Client N y lo envía a todos los peers; si no, solo en local.
## No hace nada en builds de release.
## Recibe: [param message] — cualquier valor, se convierte a texto; [param seconds] — tiempo
## en pantalla, en segundos.
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


## Añade una etiqueta arriba de la pila de mensajes y la borra al cabo de [param seconds]
## segundos. [code]log()[/code] la llama como RPC para que salga en todos los peers, incluido
## el emisor.
## Recibe: [param message] — texto ya formateado; [param seconds] — duración en pantalla.
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


## Pone [param text] como sufijo del título original de la ventana; no se acumula entre
## llamadas. No hace nada en builds de release.
## Recibe: [param text] — p. ej. "Server" o "Client 2".
func add_to_window_title(text: String) -> void:
	if not OS.is_debug_build():
		return
	get_window().title = "%s - %s" % [window_title, text]


## Restaura el título original de la ventana guardado en [code]_ready()[/code]. No comprueba
## si la build es de depuración.
func reset_window_title() -> void:
	get_window().title = window_title


## Devuelve [code]true[/code] si el modo debug de combate está encendido en este peer.
func is_combat_debug_enabled() -> bool:
	return combat_debug != null


## Enciende o apaga el modo debug de combate solo en este peer (no se replica): crea o libera
## el [CombatDebugOverlay], emite [code]combat_debug_toggled[/code] y lo anuncia con
## [code]log()[/code]. No hace nada si ya estaba así o en builds de release.
## Recibe: [param enabled] — [code]true[/code] para encenderlo.
func set_combat_debug(enabled: bool) -> void:
	if not OS.is_debug_build() or enabled == is_combat_debug_enabled():
		return
	if enabled:
		combat_debug = CombatDebugOverlay.new()
		combat_debug.name = "CombatDebug"
		add_child(combat_debug)
	else:
		# Sacarlo del árbol ya dispara su _exit_tree(), que manda borrar los visuales
		# de las hitboxes: todo desaparece al final de este frame.
		remove_child(combat_debug)
		combat_debug.queue_free()
		combat_debug = null
	combat_debug_toggled.emit(enabled)
	# self. obligatorio: sin él, log() es la función matemática global.
	self.log("Debug de combate %s (F9)" % ("activado" if enabled else "desactivado"))


## Alterna el modo debug de combate con [constant COMBAT_DEBUG_ACTION].
## Recibe: [param event] — evento de input no consumido.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(COMBAT_DEBUG_ACTION):
		set_combat_debug(not is_combat_debug_enabled())
		get_viewport().set_input_as_handled()


## Devuelve [code]true[/code] si hay un peer de red real (no [OfflineMultiplayerPeer]) y ya
## está conectado.
func is_online() -> bool:
	return multiplayer.multiplayer_peer and \
		not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and \
		multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Devuelve la etiqueta del peer local para los mensajes: "Server", "Client N" si ya tiene
## índice asignado, o "Client" mientras no lo tenga.
func _get_prefix() -> String:
	if multiplayer.is_server():
		return "Server"
	elif index:
		return "Client %d" % index
	else:
		return "Client"
