extends CanvasLayer
## SmallWorld pause menu (Esc in the game): Resume, or save and go back to the title screen.
## Opened by the player like the other menus, so time stands still while it's open.

signal closed

const MenuList := preload("res://scripts/menu_list.gd")
const UIStyle := preload("res://scripts/ui_style.gd")

var player: Node ## set by the player


func _ready() -> void:
	layer = 10
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.nine("w", 4, 28))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", MenuList.DARK_TEXT)
	column.add_child(title)

	var menu := MenuList.new()
	menu.add_option("resume", "Resume")
	menu.add_option("quit", "Save & quit to title")
	menu.chosen.connect(_on_chosen)
	column.add_child(menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _on_chosen(id: String) -> void:
	match id:
		"resume":
			_close()
		"quit":
			SaveGame.save_game()
			get_tree().change_scene_to_file("res://title.tscn")


func _close() -> void:
	closed.emit()
	queue_free()
