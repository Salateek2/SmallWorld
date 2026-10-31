extends CanvasLayer
## SmallWorld market window: sell harvested crops, buy seeds.
## Opened by the player at the market counter in the village. Built entirely in code.
## Click the buttons (or use arrow keys + Enter). Esc or E closes it.

signal closed

const Farm := preload("res://scripts/farm.gd")
## Things you can sell that aren't crops
const EXTRA_ITEMS := {
	"fish": {"sell": 35, "icon": "res://assets/Sunnyside_World_Assets/Elements/Crops/fish.png"},
}

var player: Node ## the player opening the shop (has coins, crops, seeds)

var _coins_label: Label
var _sell_list: VBoxContainer
var _buy_list: VBoxContainer


func _ready() -> void:
	layer = 10 # above the HUD
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.32, 0.2, 0.12), Color(0.85, 0.65, 0.35), 4, 14))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("Willowbrook Market", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_coins_label = _label("", 16, Color(1, 0.85, 0.35))
	header.add_child(_coins_label)

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 24)
	column.add_child(sides)
	_sell_list = _side(sides, "Sell crops")
	_buy_list = _side(sides, "Buy seeds")

	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(close_shop)
	column.add_child(close)

	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("use"):
		get_viewport().set_input_as_handled()
		close_shop()


func close_shop() -> void:
	closed.emit()
	queue_free()


## Rebuilds both lists (after every sale or purchase).
func refresh() -> void:
	_coins_label.text = "%d coins" % player.coins
	for child in _sell_list.get_children() + _buy_list.get_children():
		if child is HBoxContainer:
			child.queue_free()

	var anything := false
	for crop in Farm.CROP_TYPES + EXTRA_ITEMS.keys():
		var count: int = player.crops.get(crop, 0)
		if count <= 0:
			continue
		anything = true
		var row := _row(_sell_list, _icon(crop),
				"%s x%d" % [crop.capitalize(), count], "%dc each" % _price(crop))
		_button(row, "Sell 1", _sell.bind(crop, 1))
		_button(row, "Sell all", _sell.bind(crop, count))
	if not anything:
		var row := HBoxContainer.new()
		row.add_child(_label("Nothing to sell yet.\nHarvest some crops!", 8, Color(0.9, 0.85, 0.75)))
		_sell_list.add_child(row)

	for crop in Farm.CROP_TYPES:
		var data: Dictionary = Farm.CROP_DATA[crop]
		var row := _row(_buy_list, Farm.crop_texture(crop, 0),
				"%s seeds" % crop.capitalize(),
				"%dc - ripe in %d days - you have %d" % [data["seed"], data["nights"], player.seeds.get(crop, 0)])
		_button(row, "Buy 1", _buy.bind(crop, 1), player.coins >= data["seed"])
		_button(row, "Buy 5", _buy.bind(crop, 5), player.coins >= data["seed"] * 5)

	# Keyboard users: put focus on the first button
	await get_tree().process_frame
	var first := _find_button(self)
	if first:
		first.grab_focus()


func _sell(crop: String, amount: int) -> void:
	player.crops[crop] -= amount
	if player.crops[crop] <= 0:
		player.crops.erase(crop)
	player.coins += amount * _price(crop)
	player.refresh_ui()
	refresh()


func _buy(crop: String, amount: int) -> void:
	var cost: int = amount * Farm.CROP_DATA[crop]["seed"]
	if player.coins < cost:
		return
	player.coins -= cost
	player.seeds[crop] = player.seeds.get(crop, 0) + amount
	player.refresh_ui()
	refresh()


func _price(item: String) -> int:
	return EXTRA_ITEMS[item]["sell"] if EXTRA_ITEMS.has(item) else Farm.CROP_DATA[item]["sell"]


func _icon(item: String) -> Texture2D:
	return load(EXTRA_ITEMS[item]["icon"]) if EXTRA_ITEMS.has(item) else Farm.crop_texture(item, Farm.STAGES)


# --- UI helpers --------------------------------------------------------------

func _side(parent: Container, heading: String) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(420, 0)
	list.add_theme_constant_override("separation", 6)
	list.add_child(_label(heading, 16, Color(1, 0.9, 0.7)))
	parent.add_child(list)
	return list


func _row(list: VBoxContainer, icon_texture: Texture2D, text: String, sub: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	texts.add_child(_label(text, 16))
	texts.add_child(_label(sub, 8, Color(0.85, 0.8, 0.7)))
	row.add_child(texts)
	list.add_child(row)
	return row


func _button(row: HBoxContainer, text: String, action: Callable, enabled := true) -> void:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.pressed.connect(action)
	row.add_child(button)


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _box(bg: Color, border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(margin)
	return style


func _find_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and not child.disabled and not child.is_queued_for_deletion():
			return child
		var found := _find_button(child)
		if found:
			return found
	return null
