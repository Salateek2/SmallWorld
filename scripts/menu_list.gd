extends VBoxContainer
## A vertical list of menu options in the pack's pixel style (title screen, pause menu).
## The selected option is dark brown with the bouncing gold brackets around it.
## Up/Down (or W/S) moves, Enter/E/Space picks; the mouse can hover and click too.

signal chosen(id: String)

const UIStyle := preload("res://scripts/ui_style.gd")
const SelectCursor := preload("res://scripts/select_cursor.gd")
const DARK_TEXT := Color(0.24, 0.16, 0.12)
const CREAM := Color(1.0, 0.94, 0.82)
const PADDING := 14

var _options: Array[Dictionary] = [] # {id, panel, label, enabled}
var _selected := 0
var _cursor: Control


func _init() -> void: # _init, not _ready, so options can be added before it's in the scene
	add_theme_constant_override("separation", 14)
	_cursor = SelectCursor.new()
	_cursor.outset = PADDING + 6 # the box's padding + 6 px outside its edge


func add_option(id: String, text: String, enabled := true) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	panel.add_child(label)
	add_child(panel)
	var index := _options.size()
	_options.append({"id": id, "panel": panel, "label": label, "enabled": enabled})
	panel.mouse_entered.connect(func():
		if _options[index]["enabled"]:
			_select(index))
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_pick(index))
	if _options.size() == 1 or (not _options[_selected]["enabled"] and enabled):
		_select(index)
	else:
		_restyle()


func set_option_text(id: String, text: String) -> void:
	for option in _options:
		if option["id"] == id:
			option["label"].text = text


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		_step(-1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		_step(1)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("use"):
		_pick(_selected)
	else:
		return
	get_viewport().set_input_as_handled()


## Moves the selection, skipping options that are switched off (e.g. Continue with no save).
func _step(direction: int) -> void:
	var i := _selected
	for n in _options.size():
		i = wrapi(i + direction, 0, _options.size())
		if _options[i]["enabled"]:
			_select(i)
			return


func _select(index: int) -> void:
	_selected = index
	var panel: PanelContainer = _options[index]["panel"]
	if _cursor.get_parent():
		_cursor.reparent(panel, false)
	else:
		panel.add_child(_cursor)
	_restyle()


func _pick(index: int) -> void:
	if _options[index]["enabled"]:
		_select(index)
		chosen.emit(_options[index]["id"])


func _restyle() -> void:
	for i in _options.size():
		var option: Dictionary = _options[i]
		var active := i == _selected
		option["panel"].add_theme_stylebox_override("panel", UIStyle.nine("dt" if active else "lt", 3, PADDING))
		option["label"].add_theme_color_override("font_color", CREAM if active else DARK_TEXT)
		option["panel"].modulate.a = 1.0 if option["enabled"] else 0.45
