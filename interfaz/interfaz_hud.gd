class_name InventoryHUD
extends Control

## Barra de ranuras del inventario, abajo y al centro de la pantalla del dueño. Dibuja una
## ranura por cada [code]InventoryComponent.max_slots[/code]: un cuadrado negro semitransparente
## que, si el inventario tiene un item en esa posición, muestra su [code]icon[/code]. La ranura
## del item que se empuña se resalta con un borde. No sabe nada del rol: [Player] la instancia
## en [code]_spawn_hud()[/code], solo en el peer dueño, y le pasa el inventario con
## [code]setup()[/code].

@export_group("Ranuras")
@export var slot_size: Vector2 = Vector2(72.0, 72.0)
@export var slot_spacing: int = 12
@export var bottom_margin: int = 24
@export var icon_padding: int = 8
@export var corner_radius: int = 6

@export_group("Colores")
## Negro con alfa 0.6; sube el alfa a 1.0 para ranuras totalmente opacas.
@export var slot_color: Color = Color(0.0, 0.0, 0.0, 0.6)
@export var active_border_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var active_border_width: int = 3

var _inventory: InventoryComponent
var _panels: Array[PanelContainer] = []
var _icons: Array[TextureRect] = []
var _normal_style: StyleBoxFlat
var _active_style: StyleBoxFlat


## Ocupa toda la pantalla pero no intercepta el ratón.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Construye las ranuras, las pinta con lo que ya lleva el inventario (el loadout inicial se
## entrega antes de que exista el HUD) y se suscribe a sus cambios. Solo actúa la primera vez.
## Recibe: [param inventory] — inventario del jugador dueño de este HUD.
func setup(inventory: InventoryComponent) -> void:
	if _inventory or not inventory:
		return
	_inventory = inventory
	_build_styles()
	_build_layout(inventory.max_slots)
	inventory.item_added.connect(_on_inventory_changed)
	inventory.item_removed.connect(_on_inventory_changed)
	inventory.item_equipped.connect(_on_inventory_changed)
	_refresh()


## Crea el estilo normal y el de la ranura activa; solo difieren en el borde.
func _build_styles() -> void:
	_normal_style = _make_style(0, Color.TRANSPARENT)
	_active_style = _make_style(active_border_width, active_border_color)


## Devuelve un estilo de ranura. El margen interior es el mismo con y sin borde, para que el
## ícono no se mueva al resaltar la ranura.
## Recibe: [param border_width] — grosor del borde; [param border_color] — su color.
func _make_style(border_width: int, border_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = slot_color
	style.set_border_width_all(border_width)
	style.border_color = border_color
	style.set_corner_radius_all(corner_radius)
	style.set_content_margin_all(icon_padding)
	return style


## Crea la fila de ranuras pegada al borde inferior y centrada.
## Recibe: [param slot_count] — cuántas ranuras dibujar.
func _build_layout(slot_count: int) -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_bottom", bottom_margin)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_theme_constant_override(&"separation", slot_spacing)
	margin.add_child(row)

	for i: int in slot_count:
		var panel: PanelContainer = PanelContainer.new()
		panel.custom_minimum_size = slot_size
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override(&"panel", _normal_style)
		row.add_child(panel)

		var icon: TextureRect = TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(icon)

		_panels.append(panel)
		_icons.append(icon)


## Redibuja todas las ranuras desde [code]inventory.items[/code]: el ícono del item de esa
## posición (o nada si está vacía) y el borde en la del item que se empuña.
func _refresh() -> void:
	for i: int in _icons.size():
		var item: Equipment = null
		if i < _inventory.items.size():
			item = _inventory.items[i]
		_icons[i].texture = item.icon if item else null
		var is_active: bool = item != null and item == _inventory.active_item
		_panels[i].add_theme_stylebox_override(&"panel", _active_style if is_active else _normal_style)


## Cualquier cambio del inventario (item añadido, quitado o empuñado) redibuja la barra.
## Recibe: [param _item] — el item afectado; no hace falta, se relee todo el inventario.
func _on_inventory_changed(_item: Equipment) -> void:
	_refresh()
