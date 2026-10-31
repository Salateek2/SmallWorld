extends Node
## SmallWorld save file (autoload singleton, reachable from any script as `SaveGame`).
## One save slot, stored as JSON in user://savegame.json
## (on Windows: %APPDATA%/Godot/app_userdata/SmallWorld/savegame.json).
## The game saves when you sleep, when you quit to the title, and when you close the window.

const PATH := "user://savegame.json"
const VERSION := 1

## Set by the title screen's "Continue": the map applies the save once it has loaded.
var load_requested := false


func has_save() -> bool:
	return FileAccess.file_exists(PATH)


## Writes the current game to disk. Returns false if no game is running.
func save_game() -> bool:
	var world := _world()
	if world == null:
		return false
	var data := {
		"version": VERSION,
		"player": world.get_node("Player").get_state(),
		"farm": world.get_node("Farm").get_state(),
		"clock": {"day": world.get_node("DayNight").day, "minutes": world.get_node("DayNight").minutes},
		"map": world.get_changes(),
		"story": Story.get_state(),
	}
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not save the game: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


## Loads the save into a freshly started world (called by map_generator._ready).
func apply(world: Node) -> void:
	load_requested = false
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_error("The save file is damaged, starting a new game instead.")
		return
	world.apply_changes(data.get("map", []))
	world.get_node("Farm").set_state(data.get("farm", []))
	var clock := world.get_node("DayNight")
	clock.day = int(data["clock"]["day"])
	clock.minutes = float(data["clock"]["minutes"])
	Story.set_state(data.get("story", {}))
	world.get_node("Player").set_state(data["player"])


## Starts fresh: forget the story. (The old save is replaced the next time the game saves.)
func new_game() -> void:
	load_requested = false
	Story.reset()


func continue_game() -> void:
	load_requested = true
	Story.reset()


## The running game world (main.tscn), or null on the title screen.
func _world() -> Node:
	var scene := get_tree().current_scene
	if scene and scene.has_method("get_changes") and scene.has_node("Player"):
		return scene
	return null


func _notification(what: int) -> void:
	# Closing the window saves too
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
