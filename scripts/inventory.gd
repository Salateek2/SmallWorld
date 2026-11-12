extends CanvasLayer
## SmallWorld bag and journal windows. Built in code from the pack's UI art:
## 9-slice boxes for panels and slots, corner brackets for the selection cursor.
## Left: an info card about the selected thing. Right: labelled groups of slots.
##   The bag (I or Tab): what you carry, as "Harvest" and "Seeds".
##   The journal (J): what you know, as three pages: People, Clues and Quests (Q turns the page).
## Arrow keys or the mouse select, E / Enter plants the selected seeds, I / Tab / J / Esc closes.

signal closed

const Farm := preload("res://scripts/farm.gd")
const UIStyle := preload("res://scripts/ui_style.gd")
const SelectCursor := preload("res://scripts/select_cursor.gd")
const UI := "res://assets/Sunnyside_World_Assets/UI/"
const CROPS := "res://assets/Sunnyside_World_Assets/Elements/Crops/"
const PIXEL := 4 # UI art is drawn 4x bigger
const COLUMNS := 6
const SLOT := 64

const DARK_TEXT := Color(0.24, 0.16, 0.12)
const SOFT_TEXT := Color(0.55, 0.6, 0.7)
const CREAM := Color(1.0, 0.94, 0.82)

var player: Node ## the player (coins, crops, seeds, wood)
var journal := false ## true = the journal (people, clues, quests), false = the bag

## What the window shows: [{name, icon, empty: [title, text],
##   groups: [{title, rows (at least this many), entries: [{name, kind, text, icon, count, ...}]}]}]
## The bag has one page, the journal three (with tabs to pick one).
var _pages: Array = []
var _page := 0
var _entries: Array = [] # everything on the current page, in reading order
var _slots: Array[Control] = [] # the slot of each entry
var _rows: Array = [] # rows of slots, as lists of indexes into _entries (for up / down)
var _selected := 0

var _window: Control
var _tab_buttons: Array[Button] = []
var _groups: VBoxContainer # the titles and grids of the current page
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

	_pages = _journal_pages() if journal else _bag_pages()
	var center := CenterContainer.new() # keeps the window in the middle, whatever its size
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_window = HBoxContainer.new()
	_window.add_theme_constant_override("separation", 16)
	center.add_child(_window)
	_build_left_column()
	_build_right_column()
	_build_cursor()

	_show_page(0)
	_window.modulate.a = 0.0
	await get_tree().process_frame
	# Pop it in
	_window.pivot_offset = _window.size / 2
	_window.scale = Vector2(0.85, 0.85)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_window, "scale", Vector2.ONE, 0.25)
	tween.tween_property(_window, "modulate:a", 1.0, 0.15)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var handled := true
	if event.is_action("inventory") or event.is_action("journal") or event.is_action("ui_cancel"):
		close()
	elif event.is_action("next_tool"):
		_show_page((_page + 1) % _pages.size())
	elif event.is_action("ui_left") or event.is_action("move_left"):
		_move(-1)
	elif event.is_action("ui_right") or event.is_action("move_right"):
		_move(1)
	elif event.is_action("ui_up") or event.is_action("move_up"):
		_move_row(-1)
	elif event.is_action("ui_down") or event.is_action("move_down"):
		_move_row(1)
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

## The bag: what you've gathered, and the seeds you can plant.
func _bag_pages() -> Array:
	var harvest := []
	for crop in Farm.CROP_TYPES:
		var count: int = player.crops.get(crop, 0)
		if count > 0:
			harvest.append({"name": crop.capitalize(), "kind": "Crop", "count": count,
				"icon": Farm.crop_texture(crop, Farm.STAGES), "crop": crop,
				"text": "Sells for %dc at the market." % Farm.CROP_DATA[crop]["sell"]})
	for item in OTHER_ITEMS:
		if player.crops.get(item, 0) > 0:
			var info: Dictionary = OTHER_ITEMS[item]
			harvest.append({"name": item.capitalize(), "kind": info["kind"], "count": player.crops[item],
				"icon": load(CROPS + item + ".png"), "text": info["text"]})
	if player.wood > 0:
		harvest.append({"name": "Wood", "kind": "Material", "count": player.wood,
			"icon": load(CROPS + "wood.png"), "text": "From chopping pine trees. Good for building."})
	var seeds := []
	for crop in Farm.CROP_TYPES:
		var count: int = player.seeds.get(crop, 0)
		if count > 0:
			var data: Dictionary = Farm.CROP_DATA[crop]
			seeds.append({"name": "%s seeds" % crop.capitalize(), "kind": "Seeds", "count": count,
				"icon": Farm.crop_texture(crop, 0), "seed": crop,
				"text": "Plant on dug soil and keep it watered.\nRipe in %d hours." % data["hours"]})
	return [{"name": "Bag", "icon": "basket.png",
		"empty": ["Nothing here yet", "Harvest crops, catch fish\nor chop trees to fill your bag."],
		"groups": [
			{"title": "Harvest", "rows": 2, "entries": harvest},
			{"title": "Seeds", "rows": 2, "entries": seeds},
		]}]


## The journal: the people you've met, the clues you've found and your quests.
func _journal_pages() -> Array:
	var people := []
	for id in Story.Text.NPCS:
		var npc: Dictionary = Story.Text.NPCS[id]
		var info := {"name": npc["name"], "kind": "Willowbrook", "count": 0,
			"icon": _portrait(npc["hair"], npc.get("hair_color", Color.WHITE)),
			"text": Story.Text.ABOUT.get(id, "")}
		if Story.can_befriend(id):
			info["kind"] = "%d / %d hearts" % [Story.hearts(id), Story.MAX_HEARTS]
			info["text"] += _known_gifts(id)
		people.append(info)
	people.append({"name": "Merchant", "kind": "Willowbrook Village", "count": 0,
		"icon": _portrait("curlyhair", Color.WHITE),
		"text": "Runs the market south of the statue.\nBuys crops and fish, sells seeds."})

	var clues := []
	for id in Story.clues:
		var clue: Dictionary = Story.Text.CLUES[id]
		clues.append({"name": clue["title"], "kind": "Clue", "count": 0,
			"icon": load(UI + "search.png"), "text": clue["text"]})

	# Quests you're on first, then the ones you've finished
	var quests := []
	for state in ["active", "done"]:
		for id in Story.quests:
			if Story.quests[id] != state:
				continue
			var quest: Dictionary = Story.Text.QUESTS[id]
			quests.append({"name": quest["title"], "count": 0,
				"kind": "Quest" if state == "active" else "Finished",
				"icon": load(UI + ("expression_alerted.png" if state == "active" else "confirm.png")),
				"text": Story.quest_goal_text(id) if state == "active" else quest["goal"]})

	return [
		{"name": "People", "icon": "playercount.png", "empty": ["Nobody yet", ""],
			"groups": [{"title": "People of Willowbrook", "rows": 4, "entries": people}]},
		{"name": "Clues", "icon": "search.png",
			"empty": ["No clues yet", "Talk to people and look around.\nWhat you find out is written here."],
			"groups": [{"title": "What you've found out", "rows": 4, "entries": clues}]},
		{"name": "Quests", "icon": "expression_alerted.png",
			"empty": ["No quests yet", "People will ask you for help."],
			"groups": [{"title": "Things to do", "rows": 4, "entries": quests}]},
	]


## A head-and-shoulders picture of a villager: the idle frame's body with their hair on top.
func _portrait(hair: String, hair_color: Color) -> Texture2D:
	var human := "res://assets/Sunnyside_World_Assets/Characters/Human/IDLE/"
	var image: Image = load(human + "base_idle_strip9.png").get_image().get_region(Rect2i(36, 16, 24, 24))
	image.convert(Image.FORMAT_RGBA8)
	var hair_image: Image = load(human + "%s_idle_strip9.png" % hair).get_image().get_region(Rect2i(36, 16, 24, 24))
	hair_image.convert(Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			var c := hair_image.get_pixel(x, y)
			if c.a > 0.0:
				image.set_pixel(x, y, c * hair_color)
	return ImageTexture.create_from_image(image)


## "Loves: Fish. Likes: Egg." for the presents you've already seen them react to.
func _known_gifts(id: String) -> String:
	var known: Dictionary = Story.gift_known.get(id, {})
	var lines := ""
	for taste in ["love", "like", "dislike"]:
		var items := []
		for item in known:
			if known[item] == taste:
				items.append(item.capitalize())
		if not items.is_empty():
			lines += "\n%s: %s" % [{"love": "Loves", "like": "Likes", "dislike": "Dislikes"}[taste], ", ".join(items)]
	return lines if lines != "" else "\nGive them presents to learn what they like."


## Items that aren't crops: name -> what the info card says
const OTHER_ITEMS := {
	"fish": {"kind": "Catch", "text": "Fresh from the water. Sells for 5c."},
	"egg": {"kind": "Animal product", "text": "Laid by a well-fed chicken. Sells for 12c."},
	"milk": {"kind": "Animal product", "text": "From a well-fed cow. Sells for 30c."},
}


# --- Pages and selection ------------------------------------------------------

## Fills the right side with a page's groups: a title and a grid of slots for each.
func _show_page(page: int) -> void:
	_page = page
	for i in _tab_buttons.size():
		var active := i == page
		_tab_buttons[i].add_theme_stylebox_override("normal", _nine("dt" if active else "lt", 2, 10))
		_tab_buttons[i].add_theme_color_override("font_color", CREAM if active else DARK_TEXT)
	if _cursor.get_parent() != self:
		_cursor.reparent(self, false) # don't let it be freed with the old slots
	for child in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	_entries.clear()
	_slots.clear()
	_rows.clear()
	for group in _pages[page]["groups"]:
		_groups.add_child(_label(group["title"], 16, CREAM))
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		_groups.add_child(grid)
		var list: Array = group["entries"]
		var rows := maxi(group["rows"], ceili(list.size() / float(COLUMNS)))
		for i in rows * COLUMNS:
			if i >= list.size():
				grid.add_child(_make_slot({}, -1))
				continue
			if i % COLUMNS == 0:
				_rows.append([])
			var slot := _make_slot(list[i], _entries.size())
			_rows.back().append(_entries.size())
			_entries.append(list[i])
			_slots.append(slot)
			grid.add_child(slot)
	_selected = 0
	_update_selection()


## Left / right: the next thing in reading order (runs on into the next group).
func _move(step: int) -> void:
	if _entries.is_empty():
		return
	_selected = clampi(_selected + step, 0, _entries.size() - 1)
	_update_selection()


## Up / down: the same column in the row above or below (also across groups).
func _move_row(step: int) -> void:
	for r in _rows.size():
		var column: int = _rows[r].find(_selected)
		if column < 0:
			continue
		var target := r + step
		if target >= 0 and target < _rows.size():
			_selected = _rows[target][mini(column, _rows[target].size() - 1)]
			_update_selection()
		return


func _update_selection() -> void:
	var entry: Dictionary = _entries[_selected] if _selected < _entries.size() else {}
	# Cursor brackets around the selected slot
	_cursor.visible = not entry.is_empty()
	if not entry.is_empty():
		_cursor.reparent(_slots[_selected], false)
		_cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Info card
	_stages.visible = false
	_use_button.visible = false
	if entry.is_empty():
		_info_icon.texture = null
		_info_name.text = _pages[_page]["empty"][0]
		_info_kind.text = ""
		_info_text.text = _pages[_page]["empty"][1]
		_info_count.text = ""
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
	_use_button.visible = entry.has("seed") and player.owned_tools.has(player.Tool.SEEDS)
	if _use_button.visible:
		var in_hand: bool = player.tool == player.Tool.SEEDS \
				and Farm.CROP_TYPES[player.seed_index] == entry["seed"]
		_use_button.text = "In hand" if in_hand else "Plant these"


## E on seeds: put them in your hand, ready to plant.
func _use_selected() -> void:
	if _selected >= _entries.size() or not _use_button.visible:
		return
	player.seed_index = Farm.CROP_TYPES.find(_entries[_selected]["seed"])
	player._select_tool(player.Tool.SEEDS)
	player.refresh_ui()
	_update_selection()


# --- Building the window -----------------------------------------------------

func _build_left_column() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(320, 0)
	_window.add_child(column)

	# Header: basket icon + "Bag" (or the journal's)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _nine("lt", PIXEL, 10))
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	header_row.add_child(_icon(load(UI + ("search.png" if journal else "basket.png")), 40))
	header_row.add_child(_label("Journal" if journal else "Bag", 24, DARK_TEXT))
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
	names.add_theme_constant_override("separation", 6)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_name = _label("", 16, DARK_TEXT)
	_info_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # long quest and clue names
	_info_kind = _label("", 8, SOFT_TEXT)
	names.add_child(_info_name)
	names.add_child(_info_kind)
	top.add_child(names)
	_info_count = _label("", 16, DARK_TEXT)
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

	_info_text = _label("", 8, DARK_TEXT)
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_text.custom_minimum_size = Vector2(280, 0)
	info.add_child(_info_text)

	_use_button = Button.new()
	_use_button.focus_mode = Control.FOCUS_NONE
	_use_button.add_theme_stylebox_override("normal", _nine("dt", 2, 8))
	_use_button.add_theme_stylebox_override("hover", _nine("dt", 2, 8))
	_use_button.add_theme_stylebox_override("pressed", _nine("lt", 2, 8))
	_use_button.add_theme_color_override("font_color", CREAM)
	_use_button.add_theme_font_size_override("font_size", 16)
	_use_button.icon = load(UI + "confirm.png")
	_use_button.expand_icon = false
	_use_button.pressed.connect(_use_selected)
	info.add_child(_use_button)
	column.add_child(card)


func _build_right_column() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -6) # tabs sit on the panel's edge
	_window.add_child(column)

	if _pages.size() > 1: # the journal's pages
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 4)
		for i in _pages.size():
			var tab := Button.new()
			tab.text = _pages[i]["name"]
			tab.icon = load(UI + _pages[i]["icon"])
			tab.focus_mode = Control.FOCUS_NONE
			tab.add_theme_font_size_override("font_size", 16)
			tab.add_theme_stylebox_override("hover", _nine("dt", 2, 10))
			tab.add_theme_stylebox_override("pressed", _nine("dt", 2, 10))
			tab.add_theme_color_override("font_hover_color", CREAM)
			tab.pressed.connect(_show_page.bind(i))
			tabs.add_child(tab)
			_tab_buttons.append(tab)
		column.add_child(tabs)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _nine("dt", PIXEL, 18))
	column.add_child(panel)
	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", 10)
	panel.add_child(inside)
	_groups = VBoxContainer.new()
	_groups.add_theme_constant_override("separation", 8)
	inside.add_child(_groups)
	var keys := "Q  next page      J / Esc  close" if journal else "E  plant the selected seeds      I / Esc  close"
	var hint := _label(keys, 8, CREAM)
	hint.modulate.a = 0.7
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inside.add_child(hint)


## index = the slot's place in _entries (-1 for an empty slot).
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
	badge.add_theme_font_size_override("font_size", 8)
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
