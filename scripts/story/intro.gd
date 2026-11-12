extends CanvasLayer
## SmallWorld intro (New Game only): white lines of text on black, one after another,
## then the black fades away and you wake up outside your farmhouse. Any key skips it.
## The lines are INTRO in story_text.gd; when it's over the "intro" dialogue's actions
## run (the locket clue, the first quest).

signal closed

const Text := preload("res://scripts/story/story_text.gd")
## Turn this on while testing to jump straight into the game (the story still starts).
const SKIP_FOR_TESTING := false
const LINE_TIME := 2.6 # seconds each line stays up
const FADE := 0.8

var player: Node ## set by the player like the other menus

var _black: ColorRect
var _label: Label
var _done := false


func _ready() -> void:
	layer = 60
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_black)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	_label.modulate.a = 0.0
	add_child(_label)
	if SKIP_FOR_TESTING:
		_finish()
		return
	_play()


func _play() -> void:
	for line in Text.INTRO:
		if _done:
			return
		_label.text = line
		var tween := create_tween()
		tween.tween_property(_label, "modulate:a", 1.0, FADE)
		tween.tween_interval(LINE_TIME - FADE * 2)
		tween.tween_property(_label, "modulate:a", 0.0, FADE)
		await tween.finished
	_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
		_finish() # skip


## Fade the black away and start the story.
func _finish() -> void:
	if _done:
		return
	_done = true
	_label.visible = false
	var tween := create_tween()
	tween.tween_property(_black, "color:a", 0.0, 1.5)
	await tween.finished
	Story.run("intro")
	closed.emit()
	queue_free()
