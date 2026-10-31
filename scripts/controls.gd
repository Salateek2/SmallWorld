extends Node
## SmallWorld controls (autoload singleton "Controls", loaded first).
## Creates the game's input actions when the game starts, so every screen
## (title, menus, the game itself) knows them. Change keys here.

const KEYS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"use": [KEY_E, KEY_SPACE],
	"tool_1": [KEY_1, KEY_KP_1],
	"tool_2": [KEY_2, KEY_KP_2],
	"tool_3": [KEY_3, KEY_KP_3],
	"tool_4": [KEY_4, KEY_KP_4],
	"tool_5": [KEY_5, KEY_KP_5],
	"tool_6": [KEY_6, KEY_KP_6],
	"next_tool": [KEY_Q],
	"inventory": [KEY_I, KEY_TAB],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
}


func _ready() -> void:
	# Actions already set up in Project Settings > Input Map are left alone
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
