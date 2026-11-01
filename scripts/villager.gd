extends StaticBody2D
## SmallWorld villager: a Sunnyside human. Created at runtime by map_generator.
## Some stand in one place playing one animation (Mira idles behind her bar, Gus hammers).
## Villagers with a routine walk the roads through the day: home in the morning, off to
## work, to the tavern in the evening and home again at night (see NPCS in story_text.gd).
## Turns to face the player when they come close (unless busy working). Characters with an
## npc_id can be talked to (E) and show a bobbing "!" when they have quest news;
## characters with a shop open it instead.

const HUMAN_DIR := "res://assets/Sunnyside_World_Assets/Characters/Human/"
const FRAME_WIDTH := 96
const WALK_SPEED := 40.0 # pixels per second (the player walks faster)

@export var hair := "longhair" ## bowlhair, curlyhair, longhair, mophair, shorthair, spikeyhair
@export var hair_color := Color.WHITE ## tints the hair
@export var display_name := "Villager"
@export var npc_id := "" ## key in story_text.gd (NPCS / TALK); empty = can't talk
@export var animation_folder := "IDLE" ## Characters/Human folder to play, e.g. HAMMERING
@export var turn_to_player := true ## false = keeps facing their work
@export var face_right := false ## start facing right
@export var frame_range := Vector2i(-1, -1) ## only play these frames of the animation (first, last)
@export var shop := "" ## script of a shop window to open when you press E (empty = talk)
@export var talk_reach := 28.0 ## how close the player must be to talk (Mira: across her counter)
## Daily routine, filled in by map_generator: "schedule" ([[hour, stop], ...]) and "stops"
## (stop -> {"cell", "anim", "wander"}). Empty = stands still.
var routine := {}

var _layers: Array[AnimatedSprite2D] = []
var _news: Sprite2D # the "!" above the head
var _name_tag: Label # only shown when the player is close
var _collision: CollisionShape2D
var _world: Node # map_generator
var _clock: Node
var _stop := "" # where the routine says to be right now
var _route := PackedVector2Array() # world points still to walk; INF = go through a door
var _wait := 0.0 # wanderers pause between strolls


func _ready() -> void:
	var folders := {"idle": animation_folder}
	if not routine.is_empty():
		folders = {"idle": "IDLE", "walk": "WALKING"}
		for stop in routine["stops"].values():
			if stop.get("anim", "IDLE") != "IDLE":
				folders[stop["anim"].to_lower()] = stop["anim"]
	var prefixes: Array[String] = ["base", hair, "tools"]
	for prefix in prefixes:
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = SpriteFrames.new()
		sprite.sprite_frames.remove_animation("default")
		for anim in folders:
			_load_animation(sprite.sprite_frames, prefix, anim, folders[anim])
		sprite.flip_h = face_right # the art faces left
		if prefix == hair:
			sprite.modulate = hair_color
		add_child(sprite)
		_layers.append(sprite)
	_play("idle")
	_layers[0].frame_changed.connect(func(): # keep the layers in sync
		for layer in _layers:
			layer.frame = _layers[0].frame)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 6)
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	_collision.position = Vector2(0, 5) # feet, like the player
	add_child(_collision)

	var label := Label.new()
	label.text = display_name
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-40, -22)
	label.size = Vector2(80, 10)
	label.modulate.a = 0.0
	add_child(label)
	_name_tag = label

	if npc_id != "" or shop != "":
		add_to_group("npc")
		_news = Sprite2D.new()
		_news.texture = load("res://assets/Sunnyside_World_Assets/UI/expression_alerted.png")
		_news.position = Vector2(0, -30)
		add_child(_news)
		var bob := _news.create_tween().set_loops()
		bob.tween_property(_news, "position:y", -33.0, 0.4).set_trans(Tween.TRANS_SINE)
		bob.tween_property(_news, "position:y", -30.0, 0.4).set_trans(Tween.TRANS_SINE)

	if not routine.is_empty():
		_world = get_parent()
		_clock = _world.get_node_or_null("DayNight")
		if _clock:
			_clock.new_day.connect(func(_day): snap())
		snap.call_deferred() # once the map has built its walking grid


func _process(delta: float) -> void:
	if _news:
		_news.visible = Story.has_news(npc_id)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var distance := global_position.distance_to(player.global_position) if player else INF
	if not routine.is_empty() and _clock:
		_follow_routine(delta)
	var idle := _layers[0].animation == "idle" # sitting folk keep facing their table
	if distance < 80.0 and turn_to_player and idle:
		_face(player.global_position.x - global_position.x)
	# Name fades in when you walk up to them
	var target := 1.0 if distance < 48.0 else 0.0
	_name_tag.modulate.a = move_toward(_name_tag.modulate.a, target, delta * 4.0)


## Jumps straight to where the routine says to be (game start, a loaded save, a new day).
func snap() -> void:
	if routine.is_empty() or _clock == null:
		return
	_stop = _stop_now()
	_route.clear()
	global_position = _world.cell_to_world(_target_cell())
	_arrive()


func _follow_routine(delta: float) -> void:
	var stop := _stop_now()
	if stop != _stop:
		_stop = stop
		_set_route()
	if _route.is_empty():
		if routine["stops"][_stop].get("wander", 0) > 0:
			_wait -= delta
			if _wait <= 0.0:
				_set_route() # stroll somewhere else nearby
		return
	var next := _route[0]
	if next == Vector2.INF: # through a door: appear on the other side
		_route.remove_at(0)
		global_position = _route[0]
		_route.remove_at(0)
		return
	var step := next - global_position
	if step.length() <= WALK_SPEED * delta:
		global_position = next
		_route.remove_at(0)
		if _route.is_empty():
			_arrive()
		return
	global_position += step.normalized() * WALK_SPEED * delta
	if absf(step.x) > 0.5:
		_face(step.x)
	_play("walk")
	_lift(0.0)
	_collision.set_deferred("disabled", true) # don't get stuck on the player


func _set_route() -> void:
	_route = _world.villager_route(global_position, _target_cell())
	_wait = randf_range(3.0, 8.0)
	if _route.is_empty():
		_arrive()


func _arrive() -> void:
	_collision.set_deferred("disabled", false)
	var stop: Dictionary = routine["stops"][_stop]
	_play(stop.get("anim", "IDLE").to_lower())
	_lift(stop.get("lift", 0.0)) # up onto a stool or the sofa
	if stop.has("face"):
		_face(stop["face"])


## Which stop of the schedule we're in at this time of day.
func _stop_now() -> String:
	var hour: float = _clock.minutes / 60.0
	var stop: String = routine["schedule"][0][1]
	for entry in routine["schedule"]:
		if hour >= entry[0]:
			stop = entry[1]
	return stop


func _target_cell() -> Vector2i:
	var info: Dictionary = routine["stops"][_stop]
	var radius: int = info.get("wander", 0)
	if radius > 0:
		return _world.random_walkable_near(info["cell"], radius)
	return info["cell"]


func _play(anim: String) -> void:
	for layer in _layers:
		layer.visible = layer.sprite_frames.has_animation(anim)
		if layer.visible and layer.animation != anim:
			layer.play(anim)


func _lift(height: float) -> void:
	for layer in _layers:
		layer.position.y = height


func _face(dx: float) -> void:
	for layer in _layers:
		layer.flip_h = dx < 0.0


func _load_animation(frames: SpriteFrames, prefix: String, anim: String, folder: String) -> void:
	if prefix == "tools" and folder in ["IDLE", "WALKING"]:
		return # empty-handed
	var path := HUMAN_DIR + folder + "/"
	for file in ResourceLoader.list_directory(path):
		if file.begins_with(prefix + "_") and file.ends_with(".png"):
			frames.add_animation(anim)
			frames.set_animation_speed(anim, 8.0 if folder == "IDLE" else 12.0)
			var texture: Texture2D = load(path + file)
			for i in texture.get_width() / FRAME_WIDTH:
				if frame_range.x >= 0 and (i < frame_range.x or i > frame_range.y):
					continue # e.g. Gus: just the lift-and-strike part of hammering
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(i * FRAME_WIDTH, 0, FRAME_WIDTH, 64)
				frames.add_frame(anim, atlas)
			return
