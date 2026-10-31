extends Node
## SmallWorld title screen (the game's first scene, title.tscn).
## Behind the menu, the real island slowly drifts by at golden hour: the game world is
## loaded without the player and a camera pans across it.
## Continue loads the save, New Game starts over (asks first if there's a save), Quit closes.

const MenuList := preload("res://scripts/menu_list.gd")
const GAME_SCENE := "res://main.tscn"
const CREAM := Color(1.0, 0.94, 0.82)
const BROWN := Color(0.24, 0.16, 0.12)
const PAN_TIME := 40.0 # seconds for the camera to glide from the farm to the village

var _camera: Camera2D
var _menu: MenuList
var _fade: ColorRect
var _confirm_new := false # New Game pressed once while a save exists
var _leaving := false


func _ready() -> void:
	_build_background()
	_build_ui()
	# Fade in from black
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 1.0)


func _build_background() -> void:
	# The real world, minus the player (so no HUD, no input)
	var world: Node2D = load(GAME_SCENE).instantiate()
	world.get_node("Player").free()
	add_child(world)
	var clock := world.get_node_or_null("DayNight")
	if clock:
		clock.minutes = 17.6 * 60.0 # warm late-afternoon light
		clock.paused = true
	_camera = Camera2D.new()
	_camera.zoom = Vector2(2, 2)
	var start: Vector2 = world.cell_to_world(world.location_center("farm") + Vector2i(-6, -2))
	var end: Vector2 = world.cell_to_world(world.location_center("village") + Vector2i(4, 2))
	_camera.position = start
	world.add_child(_camera)
	_camera.make_current()
	# Glide farm -> village and back, forever
	var pan := _camera.create_tween().set_loops()
	pan.tween_property(_camera, "position", end, PAN_TIME).set_trans(Tween.TRANS_SINE)
	pan.tween_property(_camera, "position", start, PAN_TIME).set_trans(Tween.TRANS_SINE)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	# Soft dark band behind the menu so the text is easy to read
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.06, 0.04, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(shade)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	ui.add_child(column)

	# Logo: big title that gently floats up and down
	var logo_holder := Control.new()
	logo_holder.custom_minimum_size = Vector2(0, 80)
	column.add_child(logo_holder)
	var logo := Label.new()
	logo.text = "SmallWorld"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Stretch across the holder (set by hand: the holder has no size yet)
	logo.anchor_right = 1.0
	logo.anchor_bottom = 1.0
	logo.offset_right = 0.0
	logo.offset_bottom = 0.0
	logo.add_theme_font_size_override("font_size", 64)
	logo.add_theme_color_override("font_color", CREAM)
	logo.add_theme_color_override("font_outline_color", BROWN)
	logo.add_theme_constant_override("outline_size", 16)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	logo.add_theme_constant_override("shadow_offset_x", 0)
	logo.add_theme_constant_override("shadow_offset_y", 8)
	logo_holder.add_child(logo)
	# Float by shifting the top and bottom edges together (keeps the label full width)
	var float_to := func(y: float):
		logo.offset_top = y
		logo.offset_bottom = y
	var bob := logo.create_tween().set_loops()
	bob.tween_method(float_to, 0.0, -6.0, 1.2).set_trans(Tween.TRANS_SINE)
	bob.tween_method(float_to, -6.0, 0.0, 1.2).set_trans(Tween.TRANS_SINE)

	var subtitle := _text("A cozy island mystery", 16, CREAM)
	column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	column.add_child(spacer)

	_menu = MenuList.new()
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu.add_option("continue", "Continue", SaveGame.has_save())
	_menu.add_option("new", "New Game")
	_menu.add_option("quit", "Quit")
	_menu.chosen.connect(_on_chosen)
	column.add_child(_menu)

	var credits := _text("Art: Sunnyside World by Daniel Diggle   Font: Press Start 2P", 8, Color(1, 1, 1, 0.7))
	credits.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	credits.offset_top = -24
	credits.offset_bottom = -12
	credits.offset_left = -400
	credits.offset_right = 400
	ui.add_child(credits)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_fade)


func _on_chosen(id: String) -> void:
	if _leaving:
		return
	match id:
		"continue":
			SaveGame.continue_game()
			_start_game()
		"new":
			if SaveGame.has_save() and not _confirm_new:
				_confirm_new = true
				_menu.set_option_text("new", "Erase save? Press again")
				return
			SaveGame.new_game()
			_start_game()
		"quit":
			get_tree().quit()


## Fades to black, then opens the game.
func _start_game() -> void:
	_leaving = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.6)
	await tween.finished
	get_tree().change_scene_to_file(GAME_SCENE)


func _text(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", BROWN)
	label.add_theme_constant_override("outline_size", 6)
	return label
