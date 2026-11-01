extends CanvasLayer
## SmallWorld dialogue box: shows one conversation from story_text.gd, line by line.
## Text types itself out; E / Space shows the whole line, then goes to the next one.
## When the last line is done, the story actions run (Story.run) and the box closes,
## or, if there's something to answer (Story.choices_for), a list of answers pops up:
## picking one runs the actions and carries on with the conversation it leads to.
## Villagers you can befriend show their hearts next to their name.

signal closed

const Text := preload("res://scripts/story/story_text.gd")
const UIStyle := preload("res://scripts/ui_style.gd")
const MenuList := preload("res://scripts/menu_list.gd")
const UI := "res://assets/Sunnyside_World_Assets/UI/"
const LETTERS_PER_SECOND := 45.0
const DARK_TEXT := Color(0.24, 0.16, 0.12)
const CREAM := Color(1.0, 0.94, 0.82)

var player: Node ## not used yet, set by the player like the other menus
var dialogue_key := "" ## which DIALOGUE entry to show

var _lines: Array = []
var _index := 0
var _shown := 0.0 # letters visible so far (typewriter)
var _name_label: Label
var _text: Label
var _next_arrow: TextureRect
var _hearts: HBoxContainer # beside the name
var _choices: Control # the answers, while you're picking one


func _ready() -> void:
	layer = 10
	_lines = Story.lines_for(dialogue_key)

	# Box along the bottom of the screen, above the hotbar
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -360
	box.offset_right = 360
	box.offset_bottom = -24
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", -8) # name tag overlaps the box edge
	add_child(box)

	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UIStyle.nine("dt", 3, 10))
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.z_index = 1
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 12)
	tag.add_child(tag_row)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", CREAM)
	tag_row.add_child(_name_label)
	_hearts = HBoxContainer.new()
	_hearts.add_theme_constant_override("separation", 2)
	_hearts.alignment = BoxContainer.ALIGNMENT_CENTER
	tag_row.add_child(_hearts)
	box.add_child(tag)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.nine("w", 4, 22))
	panel.custom_minimum_size = Vector2(0, 130)
	box.add_child(panel)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 16)
	_text.add_theme_color_override("font_color", DARK_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(_text)

	# Little arrow in the corner when the line is finished, bobbing up and down
	_next_arrow = TextureRect.new()
	_next_arrow.texture = load(UI + "indicator.png")
	_next_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_next_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_next_arrow.custom_minimum_size = Vector2(24, 18)
	_next_arrow.size_flags_horizontal = Control.SIZE_SHRINK_END
	_next_arrow.size_flags_vertical = Control.SIZE_SHRINK_END
	panel.add_child(_next_arrow)
	var bob := _next_arrow.create_tween().set_loops()
	bob.tween_property(_next_arrow, "position:y", 4.0, 0.35).as_relative().set_trans(Tween.TRANS_SINE)
	bob.tween_property(_next_arrow, "position:y", -4.0, 0.35).as_relative().set_trans(Tween.TRANS_SINE)

	if _lines.is_empty():
		close()
		return
	_show_line(0)


func _process(delta: float) -> void:
	if _shown < _text.text.length():
		_shown += delta * LETTERS_PER_SECOND
		_text.visible_characters = int(_shown)
	_next_arrow.visible = _is_line_done() and _choices == null


func _unhandled_input(event: InputEvent) -> void:
	if _choices or not (event.is_action_pressed("use") or event.is_action_pressed("ui_accept")):
		return # (while answering, the list handles the keys)
	get_viewport().set_input_as_handled()
	if not _is_line_done():
		_shown = _text.text.length() # skip the typing, show the whole line
		_text.visible_characters = -1
	elif _index + 1 < _lines.size():
		_show_line(_index + 1)
	elif not Story.choices_for(dialogue_key).is_empty():
		_show_choices()
	else:
		close()


## The answers you can pick, in a list above the box's right end.
func _show_choices() -> void:
	var choices := Story.choices_for(dialogue_key)
	var list := MenuList.new()
	for i in choices.size():
		list.add_option(str(i), choices[i][0], choices[i][2])
	var holder := MarginContainer.new()
	holder.anchor_left = 1.0
	holder.anchor_right = 1.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_right = -(get_viewport().get_visible_rect().size.x / 2 - 360) # line up with the box
	holder.offset_bottom = -196
	holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.add_child(list)
	add_child(holder)
	_choices = holder
	_next_arrow.visible = false
	list.chosen.connect(func(id: String): _pick(choices[int(id)][1]))


func _pick(next_key: String) -> void:
	_choices.queue_free()
	_choices = null
	Story.run(dialogue_key) # this part's actions (flags, the present you picked...)
	if next_key == "":
		closed.emit()
		queue_free()
		return
	dialogue_key = next_key
	_lines = Story.lines_for(dialogue_key)
	if _lines.is_empty():
		close()
	else:
		_show_line(0)


func close() -> void:
	Story.run(dialogue_key) # set flags, start or finish quests
	closed.emit()
	queue_free()


func _show_line(index: int) -> void:
	_index = index
	_name_label.text = _lines[index][0]
	_show_hearts(_lines[index][0])
	_text.text = _lines[index][1]
	_shown = 0.0
	_text.visible_characters = 0


## Hearts beside the speaker's name, if they're someone you can befriend.
func _show_hearts(speaker: String) -> void:
	for child in _hearts.get_children():
		child.queue_free()
	for id in Text.NPCS:
		if Text.NPCS[id]["name"] == speaker and Story.can_befriend(id):
			for i in Story.MAX_HEARTS:
				var heart := TextureRect.new()
				heart.texture = UIStyle.heart(i < Story.hearts(id), 2)
				heart.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				_hearts.add_child(heart)


func _is_line_done() -> bool:
	return _shown >= _text.text.length()
