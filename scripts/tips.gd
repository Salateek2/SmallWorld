extends CanvasLayer
## SmallWorld tips: short notes in the bottom-left corner that explain the controls the
## first time you need them (walking, zooming, tools, the bag...). Each one shows once
## per game: it's remembered as a story flag ("tip_zoom"), so it's saved with the game.
## Created by the player.

const UIStyle := preload("res://scripts/ui_style.gd")
const DARK_TEXT := Color(0.24, 0.16, 0.12)
const SHOW_FOR := 8.0 # seconds a tip stays up
const GAP := 4.0 # seconds between two tips

## [id, text]: checked in this order; _ready_to_show() says when each one is due.
const TIPS := [
	["walk", "Walk with WASD or the arrow keys.\nKeep walking and you'll start to run."],
	["quest", "Your current goal is shown in the top right corner."],
	["zoom", "Zoom in and out with the mouse wheel\n(or the + and - keys)."],
	["tools", "Pick a tool with the number keys (or Q),\nthen press E to use it."],
	["grow", "Crops only grow in wet (dark) soil. Face one to see\nhow long it needs. Soil dries after a few hours."],
	["bag", "Press I (or Tab) to open your bag.\nPress J for your journal: people, clues and quests."],
	["forage", "Mushrooms, fruit bushes and seashells can be picked\nwith E. They come back after a few days."],
	["friends", "Chat with people every day and bring them\npresents to become friends."],
	["night", "It's getting late! Sleep in your bed to start\na new day. The game saves every morning."],
]

var player: Node ## set by the player

var _panel: PanelContainer
var _label: Label
var _played := 0.0 # seconds of play (not counting menus)
var _wait := 2.0 # until the next tip may show


func _ready() -> void:
	layer = 9 # under menus and dialogue
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIStyle.nine("w", 3, 14))
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 16
	_panel.offset_bottom = -20
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Tip"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.75, 0.42, 0.2))
	box.add_child(title)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", DARK_TEXT)
	box.add_child(_label)
	_panel.modulate.a = 0.0
	add_child(_panel)


func _process(delta: float) -> void:
	if player == null or player._in_menu:
		return # nothing while a menu, the intro or a conversation is open
	_played += delta
	_wait -= delta
	if _wait > 0.0:
		return
	for tip in TIPS:
		if not Story.flags.has("tip_" + tip[0]) and _ready_to_show(tip[0]):
			_show(tip)
			return


func _ready_to_show(id: String) -> bool:
	match id:
		"walk":
			return true
		"quest":
			return Story.current_quest() != ""
		"zoom":
			return _played > 25.0
		"tools":
			return player.owned_tools.size() > 2
		"grow":
			var farm: Node = player.get_parent().get_node_or_null("Farm")
			return farm != null and farm.has_crops()
		"bag":
			return player.wood > 0 or not player.crops.is_empty()
		"forage":
			return not player.forage_in_reach().is_empty()
		"friends":
			return not Story.friendship.is_empty()
		"night":
			var clock: Node = player.get_parent().get_node_or_null("DayNight")
			return clock != null and clock.minutes >= 21 * 60
	return false


func _show(tip: Array) -> void:
	Story.flags["tip_" + tip[0]] = true
	_label.text = tip[1]
	_wait = SHOW_FOR + GAP
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 1.0, 0.4)
	tween.tween_interval(SHOW_FOR)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.6)
