extends Node
## SmallWorld music (autoload singleton "Music"): background music and ambience that
## follow where you are and what time it is, fading smoothly from one to the next.
##
## It plays whatever sound files it finds in these folders (.ogg, .mp3 or .wav):
##   assets/music/title/    the title screen
##   assets/music/day/      daytime
##   assets/music/night/    after 8 PM
##   assets/music/tavern/   inside the tavern
##   assets/ambience/day/   birds, wind...   (plays quietly under the music)
##   assets/ambience/night/ crickets...
##   assets/ambience/tavern/ fireplace, chatter...
## Several files in one folder play one after another in a random order.
## An empty music folder borrows the daytime music; an empty ambience folder is just quiet.
## So to change the music, drop files in a folder: no code needed.
## Music.muted switches it all off and on (the pause and title menus have a button for it);
## the choice is remembered in user://settings.cfg.

const MUSIC_DIR := "res://assets/music/"
const AMBIENCE_DIR := "res://assets/ambience/"
const MOODS: Array[String] = ["title", "day", "night", "tavern"]
const MUSIC_DB := -10.0 # how loud the music is
const AMBIENCE_DB := -16.0 # how loud the birds / crickets are
const FADE := 2.0 # seconds to fade from one track to another
const NIGHT_FROM := 20.0 # 8 PM (the clock runs past midnight as hour 24, 25...)
const BUS := "Music" # its own volume slider, separate from the sound effects
const SETTINGS := "user://settings.cfg"

## True = no music or ambience (sound effects still play).
var muted := false:
	set(value):
		muted = value
		AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS), muted)
		var settings := ConfigFile.new()
		settings.load(SETTINGS) # keep anything else stored there
		settings.set_value("audio", "music_muted", muted)
		settings.save(SETTINGS)

var _music: Channel
var _ambience: Channel
var _music_lists := {} # mood -> its tracks
var _ambience_lists := {}
var _mood := ""
var _check_in := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps playing in menus
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS) == OK:
		muted = settings.get_value("audio", "music_muted", false)
	for mood in MOODS:
		_music_lists[mood] = _load_folder(MUSIC_DIR + mood + "/")
		_ambience_lists[mood] = _load_folder(AMBIENCE_DIR + mood + "/")
	_music = Channel.new(MUSIC_DB, FADE)
	_ambience = Channel.new(AMBIENCE_DB, FADE)
	add_child(_music)
	add_child(_ambience)


func _process(delta: float) -> void:
	_check_in -= delta
	if _check_in > 0.0:
		return
	_check_in = 0.5 # twice a second is plenty
	var mood := _mood_now()
	if mood == _mood:
		return
	_mood = mood
	var music: Array = _music_lists[mood]
	_music.play_list(music if not music.is_empty() else _music_lists["day"])
	# Outdoor sounds on the title screen too (it shows the island at golden hour)
	_ambience.play_list(_ambience_lists["day" if mood == "title" else mood])


## Text for the menu button that switches the music on and off.
func button_text() -> String:
	return "Music: Off" if muted else "Music: On"


## Which music fits right now: "title", "tavern", "night" or "day".
func _mood_now() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return _mood
	if scene.scene_file_path.ends_with("title.tscn"):
		return "title"
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return _mood
	var world := player.get_parent()
	if world.get("_in_hall"):
		return "tavern"
	var clock := world.get_node_or_null("DayNight")
	if clock and clock.minutes / 60.0 >= NIGHT_FROM:
		return "night"
	return "day"


## Every sound file in a folder (none if the folder is empty or missing).
func _load_folder(folder: String) -> Array:
	var tracks := []
	if not DirAccess.dir_exists_absolute(folder):
		return tracks
	for file in ResourceLoader.list_directory(folder):
		if file.get_extension().to_lower() in ["ogg", "mp3", "wav"]:
			var track := load(folder + file) as AudioStream
			if track:
				tracks.append(track)
	return tracks


## One layer of sound (the music, or the ambience). It has two speakers so the old
## track can fade out while the new one fades in.
class Channel extends Node:
	const SILENT_DB := -60.0

	var _volume_db: float
	var _fade: float
	var _speakers: Array[AudioStreamPlayer] = []
	var _fades: Array = [null, null] # the running fade of each speaker
	var _current := 0 # which speaker is the one playing now
	var _list: Array = []
	var _track := 0

	func _init(volume_db: float, fade: float) -> void:
		_volume_db = volume_db
		_fade = fade
		for i in 2:
			var speaker := AudioStreamPlayer.new()
			speaker.volume_db = SILENT_DB
			speaker.bus = Music.BUS
			speaker.finished.connect(_on_finished.bind(i))
			add_child(speaker)
			_speakers.append(speaker)

	## Fades over to this list of tracks (an empty list fades to silence).
	## Asking for the list that's already playing changes nothing.
	func play_list(list: Array) -> void:
		if list == _list:
			return
		_list = list
		_fade_to(_current, SILENT_DB, true)
		if list.is_empty():
			return
		_current = 1 - _current
		_track = randi() % list.size()
		_start()

	func _start() -> void:
		var speaker := _speakers[_current]
		speaker.stream = _list[_track]
		speaker.play()
		_fade_to(_current, _volume_db, false)

	## A track ended: play the next one in the list (or the same one again).
	func _on_finished(index: int) -> void:
		if index != _current or _list.is_empty():
			return
		_track = (_track + 1) % _list.size()
		_start()

	func _fade_to(index: int, volume_db: float, then_stop: bool) -> void:
		if _fades[index]:
			_fades[index].kill()
		var speaker := _speakers[index]
		var tween := create_tween()
		tween.tween_property(speaker, "volume_db", volume_db, _fade)
		if then_stop:
			tween.tween_callback(speaker.stop)
		_fades[index] = tween
