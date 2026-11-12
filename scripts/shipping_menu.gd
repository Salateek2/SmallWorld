extends CanvasLayer
## The shipping bin's window: move things from your bag into the bin (and back).
## Opened by the player with E at the crate outside the house. Built in code in the
## pack's pixel style, like Gus's smithy. Click the buttons (or arrow keys + Enter).
## Esc or E closes it.

signal closed

const Farm := preload("res://scripts/farm.gd")
const UIStyle := preload("res://scripts/ui_style.gd")
const DARK_TEXT := Color(0.24, 0.16, 0.12)
const SOFT_TEXT := Color(0.42, 0.3, 0.24)
const CREAM := Color(1.0, 0.94, 0.82)

var player: Node ## set by the player when it opens the window

var _bin: Node
var _bag_list: VBoxContainer
var _bin_list: VBoxContainer
var _total: Label


func _ready() -> void:
	layer = 10
	_bin = player.get_parent().get_node("ShippingBin")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.nine("dt", 4, 20))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	column.add_child(_label("Shipping Bin", 24, CREAM))
	column.add_child(_label("Whatever is in the bin is sold overnight. You're paid in the morning.", 8, Color(1, 0.9, 0.75)))

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 16)
	column.add_child(sides)
	_bag_list = _side(sides, "Your bag")
	_bin_list = _side(sides, "In the bin")

	_total = _label("", 16, Color(1, 0.85, 0.35))
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_total)

	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(close_menu)
	column.add_child(close)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("use"):
		get_viewport().set_input_as_handled()
		close_menu()


func close_menu() -> void:
	closed.emit()
	queue_free()


## Rebuilds both lists (after every move).
func _refresh() -> void:
	for child in _bag_list.get_children() + _bin_list.get_children():
		child.queue_free()

	var anything := false
	for item in Farm.sellable_items():
		var count: int = player.crops.get(item, 0)
		if count <= 0:
			continue
		anything = true
		var line := _row(_bag_list, item, count)
		_button(line, "Ship 1", _ship.bind(item, 1))
		_button(line, "All", _ship.bind(item, count))
	if not anything:
		_bag_list.add_child(_label("Nothing to ship.\nHarvest some crops!", 8, CREAM))

	if _bin.contents.is_empty():
		_bin_list.add_child(_label("The bin is empty.", 8, CREAM))
	for item in Farm.sellable_items():
		var count: int = _bin.contents.get(item, 0)
		if count > 0:
			var line := _row(_bin_list, item, count)
			_button(line, "Take back", _take_back.bind(item, count))
	_total.text = "Tomorrow morning: +%d coins" % _bin.value()

	# Keyboard users: put focus on the first button
	await get_tree().process_frame
	var first := _find_button(self)
	if first:
		first.grab_focus()


func _ship(item: String, amount: int) -> void:
	player.crops[item] -= amount
	if player.crops[item] <= 0:
		player.crops.erase(item)
	_bin.add(item, amount)
	Juice.sound("pop")
	player.refresh_ui()
	_refresh()


func _take_back(item: String, amount: int) -> void:
	_bin.take(item, amount)
	player.crops[item] = player.crops.get(item, 0) + amount
	Juice.sound("tick")
	player.refresh_ui()
	_refresh()


# --- UI helpers --------------------------------------------------------------

## One of the two columns: a heading over a list that scrolls when it gets long.
func _side(parent: Container, heading: String) -> VBoxContainer:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.add_child(_label(heading, 16, CREAM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	side.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	parent.add_child(side)
	return list


## A light box with the item's icon, name, count and price; returns the row to add buttons to.
func _row(list: VBoxContainer, item: String, count: int) -> HBoxContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIStyle.nine("lt", 3, 8))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.texture = Farm.item_icon(item)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	texts.add_child(_label("%s x%d" % [item.capitalize(), count], 16, DARK_TEXT))
	texts.add_child(_label("%dc each" % Farm.item_price(item), 8, SOFT_TEXT))
	line.add_child(texts)
	list.add_child(row)
	return line


func _button(line: HBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	line.add_child(button)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _find_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and not child.disabled and not child.is_queued_for_deletion():
			return child
		var found := _find_button(child)
		if found:
			return found
	return null
