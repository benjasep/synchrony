class_name InventoryHUD
extends Control

## Barra de ranuras del inventario, abajo y al centro de la pantalla del dueño. Dibuja una
## ranura por cada [code]InventoryComponent.max_slots[/code]: un cuadrado negro semitransparente
## que, si el inventario tiene un item en esa posición, muestra su [code]icon[/code]. La ranura
## del item que se empuña se resalta con un borde. Encima de las ranuras hay hasta dos barras:
## la de enfriamiento de la habilidad del rol, que se vacía al usarla y se rellena con el
## tiempo, y la de carga del item empuñado, que solo se ve si ese item tiene carga
## ([code]Equipment.get_charge_ratio()[/code] >= 0). No conoce ningún item ni rol concretos:
## [Player] la instancia en [code]_spawn_hud()[/code], solo en el peer dueño, y le pasa el
## inventario y la habilidad con [code]setup()[/code].

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

@export_group("Barras")
@export var bar_height: int = 8
## Separación entre las barras y las ranuras.
@export var bar_gap: int = 8
@export var bar_background_color: Color = Color(0.0, 0.0, 0.0, 0.6)
## Color de la barra de carga del item empuñado.
@export var charge_color: Color = Color(0.945, 0.851, 0.765, 1.0)
## Color de la barra de enfriamiento de la habilidad.
@export var cooldown_color: Color = Color(0.4, 0.7, 1.0)
## Ancho en píxeles de la barra de enfriamiento (la de carga ocupa todo el ancho de las ranuras).
@export var cooldown_bar_width: int = 60
## Píxeles extra que se sube la barra de enfriamiento sobre lo demás.
@export var cooldown_bar_lift: int = 12
## Píxeles que se corre la barra de enfriamiento a la derecha desde el centro (negativo = a la
## izquierda). Nunca sale del ancho de las ranuras.
@export var cooldown_bar_shift: int = 200

var _inventory: InventoryComponent
var _charge_source: Equipment = null
var _panels: Array[PanelContainer] = []
var _icons: Array[TextureRect] = []
var _charge_bar: ProgressBar
var _cooldown_bar: ProgressBar = null
var _normal_style: StyleBoxFlat
var _active_style: StyleBoxFlat


## Ocupa toda la pantalla pero no intercepta el ratón.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Construye las ranuras y las barras, las pinta con lo que ya hay (el loadout inicial se
## entrega antes de que exista el HUD) y se suscribe a los cambios del inventario y de la
## habilidad. Solo actúa la primera vez.
## Recibe: [param inventory] — inventario del jugador dueño de este HUD; [param ability] — su
## habilidad, o [code]null[/code] si el rol no tiene y entonces no se dibuja la barra de
## enfriamiento.
func setup(inventory: InventoryComponent, ability: PlayerAbility = null) -> void:
	if _inventory or not inventory:
		return
	_inventory = inventory
	_build_styles()
	_build_layout(inventory.max_slots, ability != null)
	inventory.item_added.connect(_on_inventory_changed)
	inventory.item_removed.connect(_on_inventory_changed)
	inventory.item_equipped.connect(_on_inventory_changed)
	if ability:
		ability.cooldown_changed.connect(_on_cooldown_changed)
		_cooldown_bar.value = ability.get_cooldown_ratio()
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


## Devuelve un estilo liso con esquinas redondeadas para el fondo o el relleno de una barra.
## Recibe: [param color] — color del estilo.
func _make_bar_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style


## Devuelve una barra delgada de 0 a 1 sin porcentaje, con el fondo común y el relleno dado.
## Recibe: [param fill_color] — color del relleno.
func _make_bar(fill_color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.custom_minimum_size = Vector2(0.0, bar_height)
	bar.add_theme_stylebox_override(&"background", _make_bar_style(bar_background_color))
	bar.add_theme_stylebox_override(&"fill", _make_bar_style(fill_color))
	return bar


## Crea una columna pegada al borde inferior y centrada: de arriba abajo, la barra de
## enfriamiento (si hay habilidad), la de carga (oculta hasta que haga falta) y la fila de
## ranuras. La barra de carga se estira al ancho de la fila; la de enfriamiento es más corta,
## va un poco más arriba y corrida respecto al centro.
## Recibe: [param slot_count] — cuántas ranuras dibujar; [param with_ability] — si hay que
## crear la barra de enfriamiento.
func _build_layout(slot_count: int, with_ability: bool) -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_bottom", bottom_margin)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_theme_constant_override(&"separation", bar_gap)
	margin.add_child(column)

	if with_ability:
		_cooldown_bar = _make_bar(cooldown_color)
		_cooldown_bar.custom_minimum_size = Vector2(cooldown_bar_width, bar_height)
		_cooldown_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		# Margen inferior: la sube. Margen izquierdo: la coloca desde el borde izquierdo de las
		# ranuras (centro más el corrimiento), sin dejarla salir por ningún lado.
		var row_width: float = slot_count * slot_size.x + maxi(slot_count - 1, 0) * slot_spacing
		var free_width: int = maxi(roundi(row_width) - cooldown_bar_width, 0)
		var left_margin: int = clampi(roundi(free_width / 2.0) + cooldown_bar_shift, 0, free_width)
		var cooldown_holder: MarginContainer = MarginContainer.new()
		cooldown_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cooldown_holder.add_theme_constant_override(&"margin_left", left_margin)
		cooldown_holder.add_theme_constant_override(&"margin_bottom", cooldown_bar_lift)
		cooldown_holder.add_child(_cooldown_bar)
		column.add_child(cooldown_holder)

	_charge_bar = _make_bar(charge_color)
	_charge_bar.visible = false
	column.add_child(_charge_bar)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", slot_spacing)
	column.add_child(row)

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


## Devuelve: el item que ocupa la ranura [param index] del inventario, o [code]null[/code]
## si está vacía.
func _get_item(index: int) -> Equipment:
	if index < _inventory.items.size():
		return _inventory.items[index]
	return null


## Redibuja todas las ranuras desde [code]inventory.items[/code]: el ícono del item de esa
## posición (o nada si está vacía) y el borde en la del item que se empuña. Luego apunta la
## barra de carga al item empuñado.
func _refresh() -> void:
	for i: int in _icons.size():
		var item: Equipment = _get_item(i)
		_icons[i].texture = item.icon if item else null
		var is_active: bool = item != null and item == _inventory.active_item
		_panels[i].add_theme_stylebox_override(&"panel", _active_style if is_active else _normal_style)
	_bind_charge_source(_inventory.active_item)


## Cambia el item cuya carga muestra la barra: se desuscribe del anterior, se suscribe al nuevo
## y repinta la barra con su carga actual.
## Recibe: [param source] — el item empuñado, o [code]null[/code] si hay manos vacías.
func _bind_charge_source(source: Equipment) -> void:
	if source != _charge_source:
		if is_instance_valid(_charge_source) and _charge_source.charge_changed.is_connected(_on_charge_changed):
			_charge_source.charge_changed.disconnect(_on_charge_changed)
		_charge_source = source
		if _charge_source:
			_charge_source.charge_changed.connect(_on_charge_changed)
	_update_charge_bar(_charge_source.get_charge_ratio() if _charge_source else -1.0)


## Muestra u oculta la barra de carga y la llena.
## Recibe: [param ratio] — carga de 0.0 a 1.0; un valor negativo oculta la barra.
func _update_charge_bar(ratio: float) -> void:
	_charge_bar.visible = ratio >= 0.0
	if _charge_bar.visible:
		_charge_bar.value = ratio


## Cualquier cambio del inventario (item añadido, quitado o empuñado) redibuja la barra.
## Recibe: [param _item] — el item afectado; no hace falta, se relee todo el inventario.
func _on_inventory_changed(_item: Equipment) -> void:
	_refresh()


## La carga del item empuñado cambió.
## Recibe: [param ratio] — carga de 0.0 a 1.0.
func _on_charge_changed(ratio: float) -> void:
	_update_charge_bar(ratio)


## El enfriamiento de la habilidad avanzó: 0.0 recién usada, 1.0 lista.
## Recibe: [param ratio] — fracción de enfriamiento recuperada.
func _on_cooldown_changed(ratio: float) -> void:
	_cooldown_bar.value = ratio
