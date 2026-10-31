extends CanvasLayer
## Gus's smithy: buy tools and weapons from the blacksmith.
## Opened by talking to Gus (E) at his anvil. Built in code in the pack's pixel style.
## Click Buy (or arrow keys + Enter). Esc or E closes it.

signal closed

const UIStyle := preload("res://scripts/ui_style.gd")
const UI := "res://assets/Sunnyside_World_Assets/UI/"
const DARK_TEXT := Color(0.24, 0.16, 0.12)
const SOFT_TEXT := Color(0.42, 0.3, 0.24)
const CREAM := Color(1.0, 0.94, 0.82)

## What Gus makes. tool = the player's Tool it gives (-1 = not ready yet)
const WARES := [
	{"name": "Iron Sword", "icon": "sword.png", "price": 60, "tool": 4, # Tool.SWORD
		"text": "Slashes bushes and flowers, and keeps goblins at bay."},
	{"name": "Pickaxe", "icon": "pickaxe.png", "price": 0, "tool": -1,
		"text": "For the old mine... Gus is still working on it."},
]

var player: Node ## set by the player when it opens the window

var _coins: Label
var _rows: VBoxContainer


func _ready() -> void:
	layer = 10
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

	var header := HBoxContainer.new()
	var title := _label("Gus's Smithy", 24, CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_coins = _label("", 16, Color(1, 0.85, 0.35))
	header.add_child(_coins)
	column.add_child(header)
	column.add_child(_label("Gus: \"Need something forged? Best steel on the island.\"", 8, Color(1, 0.9, 0.75)))

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	column.add_child(_rows)

	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(close_shop)
	column.add_child(close)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("use"):
		get_viewport().set_input_as_handled()
		close_shop()


func close_shop() -> void:
	closed.emit()
	queue_free()


func _refresh() -> void:
	_coins.text = "%d coins" % player.coins
	for child in _rows.get_children():
		child.queue_free()
	for ware in WARES:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIStyle.nine("lt", 3, 10))
		row.custom_minimum_size = Vector2(560, 0)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		row.add_child(line)

		var icon := TextureRect.new()
		icon.texture = load(UI + ware["icon"])
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		line.add_child(icon)

		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 6)
		texts.add_child(_label(ware["name"], 16, DARK_TEXT))
		texts.add_child(_label(ware["text"], 8, SOFT_TEXT))
		line.add_child(texts)

		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 0)
		var owned: bool = ware["tool"] >= 0 and player.owned_tools.has(ware["tool"])
		if ware["tool"] < 0:
			button.text = "Soon"
			button.disabled = true
		elif owned:
			button.text = "Owned"
			button.disabled = true
		else:
			button.text = "%dc" % ware["price"]
			button.disabled = player.coins < ware["price"]
			button.pressed.connect(_buy.bind(ware))
		line.add_child(button)
		_rows.add_child(row)


func _buy(ware: Dictionary) -> void:
	if player.coins < ware["price"]:
		return
	player.coins -= ware["price"]
	player.give_tool(ware["tool"])
	player.notify("Gus hands you the %s!" % ware["name"].to_lower())
	_refresh()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
