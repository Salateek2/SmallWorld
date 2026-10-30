extends CanvasLayer
## SmallWorld inventory window (I or Tab). Built in code from the pack's UI art:
## 9-slice boxes for panels and slots, corner brackets for the selection cursor.
## Left: an info card about the selected thing. Right: tabs (Items / Tools / People)
## with a grid of slots. Arrow keys or the mouse select, E / Enter uses (equip a tool,
## pick seeds to plant), Q switches tab, I / Tab / Esc closes.

signal closed

const Farm := preload("res://scripts/farm.gd")
const UIStyle := preload("res://scripts/ui_style.gd")
const SelectCursor := preload("res://scripts/select_cursor.gd")
const UI := "res://assets/Sunnyside_World_Assets/UI/"
const CROPS := "res://assets/Sunnyside_World_Assets/Elements/Crops/"
const PIXEL := 4 # UI art is drawn 4x bigger
const COLUMNS := 5
const ROWS := 3
const SLOT := 64

enum Tab { ITEMS, TOOLS, PEOPLE }
const TABS := [
	{"name": "Items", "icon": "basket.png"},
	{"name": "Tools", "icon": "hand_open_01.png"},
	{"name": "People", "icon": "playercount.png"},
]
const DARK_TEXT := Color(0.24, 0.16, 0.12)
const SOFT_TEXT := Color(0.55, 0.6, 0.7)
const CREAM := Color(1.0, 0.94, 0.82)

var player: Node ## the player (coins, crops, seeds, wood, tools)

var _tab := Tab.ITEMS
var _entries: Array[Dictionary] = [] # what's in the current tab
var _selected := 0
var _page := 0

var _window: Control
var _tab_buttons: Array[Button] = []
var _grid: GridContainer
var _page_label: Label
var _arrow_left: TextureButton
var _arrow_right: TextureButton
var _cursor: Control # gold corner brackets around the selected slot
# info card
var _info_icon: TextureRect
var _info_name: Label
var _info_kind: Label
var _info_text: Label
var _info_count: Label
var _stages: HBoxContainer
var _use_button: Button


func _ready() -> void:
	layer = 10
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_window = HBoxContainer.new()
	_window.add_theme_constant_override("separation", 16)
	add_child(_window)
	_build_left_column()
	_build_right_column()
	_build_cursor()

	_show_tab(Tab.ITEMS)
	await get_tree().process_frame
	# Center the window and pop it in
	_window.position = (get_viewport().get_visible_rect().size - _window.size) / 2
	_window.pivot_offset = _window.size / 2
	_window.scale = Vector2(0.85, 0.85)
	_window.modulate.a = 0.0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_window, "scale", Vector2.ONE, 0.25)
	tween.tween_property(_window, "modulate:a", 1.0, 0.15)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var handled := true
	if event.is_action("inventory") or event.is_action("ui_cancel"):
		close()
	elif event.is_action("next_tool"):
		_show_tab((_tab + 1) % TABS.size())
	elif event.is_action("ui_left") or event.is_action("move_left"):
		_move(-1)
	elif event.is_action("ui_right") or event.is_action("move_right"):
		_move(1)
	elif event.is_action("ui_up") or event.is_action("move_up"):
		_move(-COLUMNS)
	elif event.is_action("ui_down") or event.is_action("move_down"):
		_move(COLUMNS)
	elif event.is_action("use") or event.is_action("ui_accept"):
		_use_selected()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


# --- Content -----------------------------------------------------------------

## Everything shown in a tab, as a list of {name, kind, text, icon, count, ...}.
func _collect(tab: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	match tab:
		Tab.ITEMS:
			for crop in Farm.CROP_TYPES:
				var count: int = player.crops.get(crop, 0)
				if count > 0:
					list.append({"name": crop.capitalize(), "kind": "Crop", "count": count,
						"icon": Farm.crop_texture(crop, Farm.STAGES), "crop": crop,
						"text": "Sells for %dc at the market." % Farm.CROP_DATA[crop]["sell"]})
			if player.crops.get("fish", 0) > 0:
				list.append({"name": "Fish", "kind": "Catch", "count": player.crops["fish"],
					"icon": load(CROPS + "fish.png"), "text": "Fresh from the water. Sells for 35c."})
			if player.wood > 0:
				list.append({"name": "Wood", "kind": "Material", "count": player.wood,
					"icon": load(CROPS + "wood.png"), "text": "From chopping pine trees. Good for building."})
			for crop in Farm.CROP_TYPES:
				var count: int = player.seeds.get(crop, 0)
				if count > 0:
					var data: Dictionary = Farm.CROP_DATA[crop]
					list.append({"name": "%s seeds" % crop.capitalize(), "kind": "Seeds", "count": count,
						"icon": Farm.crop_texture(crop, 0), "seed": crop,
						"text": "Plant on dug soil and water every day.\nRipe in %d days." % data["nights"]})
		Tab.TOOLS:
			for t in player.Tool.size():
				var info := {"name": player.TOOL_NAMES[t], "kind": "Tool  (key %d)" % (t + 1), "tool": t,
					"text": TOOL_TEXT[t], "count": 0}
				if player.TOOL_ICONS.has(t):
					info["icon"] = load(UI + player.TOOL_ICONS[t])
				else:
					info["icon"] = Farm.crop_texture(Farm.CROP_TYPES[player.seed_index], Farm.STAGES)
				list.append(info)
		Tab.PEOPLE:
			list.append({"name": "Merchant", "kind": "Willowbrook Village", "count": 0,
				"icon": load(UI + "playercount.png"),
				"text": "Runs the market south of the statue.\nBuys crops and fish, sells seeds."})
	return list


const TOOL_TEXT := [
	"Chop pine trees for wood. Three hits fell a tree.",
	"Dig grass into soil so you can plant seeds.",
	"Plant seeds on dug soil. Press 3 again to switch seed type.",
	"Water your crops every day so they grow overnight.",
	"Slash flowers, bushes and the odd goblin.",
	"Cast into water, wait for the ! and press E quickly.",
]


func _show_tab(tab: int) -> void:
	_tab = tab
	_entries = _collect(tab)
	_selected = 0
	_page = 0
	for i in _tab_buttons.size():
		var active := i == tab
		_tab_buttons[i].add_theme_stylebox_override("normal", _nine("dt" if active else "lt", 2, 10))
		_tab_buttons[i].add_theme_color_override("font_color", CREAM if active else DARK_TEXT)
	_fill_grid()


func _fill_grid() -> void:
	if _cursor.get_parent() != self:
		_cursor.reparent(self, false) # don't let it be freed with the old slots
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var per_page := COLUMNS * ROWS
	var pages := maxi(1, ceili(_entries.size() / float(per_page)))
	_page = clampi(_page, 0, pages - 1)
	for i in per_page:
		var index := _page * per_page + i
		_grid.add_child(_make_slot(_entries[index] if index < _entries.size() else {}, index))
	_page_label.text = "%d/%d" % [_page + 1, pages]
	_arrow_left.visible = pages > 1
	_arrow_right.visible = pages > 1
	_update_selection()


func _move(step: int) -> void:
	if _entries.is_empty():
		return
	_selected = clampi(_selected + step, 0, _entries.size() - 1)
	var page := _selected / (COLUMNS * ROWS)
	if page != _page:
		_page = page
		_fill_grid()
	else:
		_update_selection()


func _turn_page(step: int) -> void:
	var per_page := COLUMNS * ROWS
	var pages := maxi(1, ceili(_entries.size() / float(per_page)))
	_page = wrapi(_page + step, 0, pages)
	_selected = mini(_page * per_page, maxi(0, _entries.size() - 1))
	_fill_grid()


func _update_selection() -> void:
	var entry: Dictionary = _entries[_selected] if _selected < _entries.size() else {}
	# Cursor brackets around the selected slot
	var slot_index := _selected - _page * COLUMNS * ROWS
	if entry.is_empty() or slot_index < 0 or slot_index >= _grid.get_child_count():
		_cursor.visible = false
	else:
		var slot: Control = _grid.get_child(slot_index)
		_cursor.reparent(slot, false)
		_cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_cursor.visible = true

	# Info card
	if entry.is_empty():
		_info_icon.texture = null
		_info_name.text = "Nothing here yet"
		_info_kind.text = ""
		_info_text.text = "Harvest crops, catch fish\nor chop trees to fill your bag."
		_info_count.text = ""
		_stages.visible = false
		_use_button.visible = false
		return
	_info_icon.texture = entry["icon"]
	_info_name.text = entry["name"]
	_info_kind.text = entry["kind"]
	_info_text.text = entry["text"]
	_info_count.text = "x%d" % entry["count"] if entry["count"] > 0 else ""
	var crop: String = entry.get("seed", entry.get("crop", ""))
	_stages.visible = crop != ""
	if crop != "":
		for i in 3:
			var stage := _stages.get_node("StageBox%d/Stage" % i) as TextureRect
			stage.texture = Farm.crop_texture(crop, [0, 2, Farm.RIPE][i])
	_use_button.visible = entry.has("seed") or entry.has("tool")
	if entry.has("tool"):
		_use_button.text = "Equipped" if player.tool == entry["tool"] else "Equip"
	elif entry.has("seed"):
		var equipped: bool = player.tool == player.Tool.SEEDS \
				and Farm.CROP_TYPES[player.seed_index] == entry["seed"]
		_use_button.text = "In hand" if equipped else "Plant these"


func _use_selected() -> void:
	if _selected >= _entries.size():
		return
	var entry := _entries[_selected]
	if entry.has("tool"):
		player._select_tool(entry["tool"])
	elif entry.has("seed"):
		player.seed_index = Farm.CROP_TYPES.find(entry["seed"])
		player._select_tool(player.Tool.SEEDS)
	else:
		return
	player.refresh_ui()
	_update_selection()


# --- Building the window -----------------------------------------------------

func _build_left_column() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(300, 0)
	_window.add_child(column)

	# Header: basket icon + "Inventory"
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _nine("lt", PIXEL, 10))
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	header_row.add_child(_icon(load(UI + "basket.png"), 40))
	header_row.add_child(_label("Inventory", 28, DARK_TEXT))
	header.add_child(header_row)
	column.add_child(header)

	# Info card about the selected slot
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _nine("w", PIXEL, 16))
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	card.add_child(info)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_info_icon = _icon(null, 56)
	top.add_child(_info_icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_name = _label("", 24, DARK_TEXT)
	_info_kind = _label("", 16, SOFT_TEXT)
	names.add_child(_info_name)
	names.add_child(_info_kind)
	top.add_child(names)
	_info_count = _label("", 22, DARK_TEXT)
	top.add_child(_info_count)
	info.add_child(top)

	# Growth stages: seed > sprout > crop, in little light boxes with arrows between
	_stages = HBoxContainer.new()
	_stages.add_theme_constant_override("separation", 2)
	for i in 3:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _nine("lt", 2, 4))
		box.name = "StageBox%d" % i
		var stage := _icon(null, 36)
		stage.name = "Stage"
		box.add_child(stage)
		_stages.add_child(box)
		if i < 2:
			_stages.add_child(_icon(load(UI + "arrow_right.png"), 20))
	info.add_child(_stages)

	_info_text = _label("", 16, DARK_TEXT)
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_text.custom_minimum_size = Vector2(260, 0)
	info.add_child(_info_text)

	_use_button = Button.new()
	_use_button.focus_mode = Control.FOCUS_NONE
	_use_button.add_theme_stylebox_override("normal", _nine("dt", 2, 8))
	_use_button.add_theme_stylebox_override("hover", _nine("dt", 2, 8))
	_use_button.add_theme_stylebox_override("pressed", _nine("lt", 2, 8))
	_use_button.add_theme_color_override("font_color", CREAM)
	_use_button.add_theme_font_size_override("font_size", 18)
	_use_button.icon = load(UI + "confirm.png")
	_use_button.expand_icon = false
	_use_button.pressed.connect(_use_selected)
	info.add_child(_use_button)
	column.add_child(card)


func _build_right_column() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_window.add_child(row)

	_arrow_left = _arrow("arrow_left.png", -1)
	row.add_child(_arrow_left)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -6) # tabs sit on the panel's edge
	row.add_child(column)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var tab := Button.new()
		tab.text = TABS[i]["name"]
		tab.icon = load(UI + TABS[i]["icon"])
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 20)
		tab.add_theme_stylebox_override("hover", _nine("dt", 2, 10))
		tab.add_theme_stylebox_override("pressed", _nine("dt", 2, 10))
		tab.add_theme_color_override("font_hover_color", CREAM)
		tab.pressed.connect(_show_tab.bind(i))
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	column.add_child(tabs)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _nine("dt", PIXEL, 18))
	column.add_child(panel)
	var inside := VBoxContainer.new()
	panel.add_child(inside)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	inside.add_child(_grid)
	_page_label = _label("1/1", 18, CREAM)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inside.add_child(_page_label)

	_arrow_right = _arrow("arrow_right.png", 1)
	row.add_child(_arrow_right)


func _make_slot(entry: Dictionary, index: int) -> Control:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(SLOT, SLOT)
	slot.focus_mode = Control.FOCUS_NONE
	var style := _nine("lt", PIXEL, 6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		slot.add_theme_stylebox_override(state, style)
	if entry.is_empty():
		slot.modulate = Color(1, 1, 1, 0.55) # empty slots are a bit faded
		slot.disabled = true
		return slot
	var icon := _icon(entry["icon"], 44)
	# Fill the slot minus a 10px border (the slot has no size yet, so set anchors by hand)
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_left = 10
	icon.offset_top = 10
	icon.offset_right = -10
	icon.offset_bottom = -10
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	if entry["count"] > 0:
		slot.add_child(_badge(entry["count"]))
	slot.pressed.connect(func():
		_selected = index
		_update_selection())
	return slot


## Small round number in the slot's top-right corner, like the reference.
func _badge(count: int) -> Control:
	var badge := Label.new()
	badge.text = str(count)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", DARK_TEXT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.97, 1.0)
	style.border_color = DARK_TEXT
	style.set_border_width_all(2)
	style.set_corner_radius_all(11)
	badge.add_theme_stylebox_override("normal", style)
	badge.custom_minimum_size = Vector2(22, 22)
	badge.position = Vector2(SLOT - 16, -8)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


## The pack's gold corner brackets, bouncing around the selected slot.
func _build_cursor() -> void:
	_cursor = SelectCursor.new()
	_cursor.visible = false
	add_child(_cursor)


func _arrow(file: String, step: int) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load(UI + file)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = Vector2(36, 36)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.pressed.connect(_turn_page.bind(step))
	return button


func _icon(texture: Texture2D, size: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(size, size)
	rect.size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _nine(prefix: String, scale: int, margin: int) -> StyleBoxTexture:
	return UIStyle.nine(prefix, scale, margin)
