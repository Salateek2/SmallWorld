extends CharacterBody2D
## SmallWorld player.
## Builds the layered Sunnyside character (body + hair + tools), a collision
## shape and a following camera from code, so the scene only needs this node.

enum Hair { NONE, BOWL, CURLY, LONG, MOP, SHORT, SPIKEY }

@export var hair: Hair = Hair.SHORT
@export var show_tools: bool = true
@export var walk_speed: float = 70.0
@export var run_speed: float = 120.0
@export var camera_zoom: float = 3.0

const HUMAN_DIR := "res://assets/Sunnyside_World_Assets/Characters/Human/"
const FRAME_SIZE := Vector2i(96, 64)
const FPS := 10.0

# animation name -> folder inside Characters/Human
const ANIMATIONS := {
	"idle": "IDLE",
	"walk": "WALKING",
	"run": "RUN",
}

const HAIR_PREFIX := {
	Hair.BOWL: "bowlhair", Hair.CURLY: "curlyhair", Hair.LONG: "longhair",
	Hair.MOP: "mophair", Hair.SHORT: "shorthair", Hair.SPIKEY: "spikeyhair",
}

var _layers: Array[AnimatedSprite2D] = []


func _ready() -> void:
	_setup_input()
	_build_sprite_layers()
	_build_collision()
	_build_camera()
	if global_position == Vector2.ZERO:
		global_position = Vector2(80, 330) # near the road of the generated map
	_play("idle")


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running := Input.is_action_pressed("run")
	velocity = direction * (run_speed if running else walk_speed)
	move_and_slide()

	if direction == Vector2.ZERO:
		_play("idle")
	else:
		_play("run" if running else "walk")
		if direction.x != 0.0:
			for layer in _layers:
				layer.flip_h = direction.x < 0.0


func _play(anim: String) -> void:
	for layer in _layers:
		if layer.sprite_frames.has_animation(anim) and layer.animation != anim:
			layer.play(anim)


# --- Setup -----------------------------------------------------------------

func _setup_input() -> void:
	# Creates the input actions if they aren't in Project Settings > Input Map yet.
	var keys := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)


func _build_sprite_layers() -> void:
	var prefixes: Array[String] = ["base"]
	if hair != Hair.NONE:
		prefixes.append(HAIR_PREFIX[hair])
	if show_tools:
		prefixes.append("tools")

	for prefix in prefixes:
		var sprite := AnimatedSprite2D.new()
		sprite.name = prefix.capitalize()
		sprite.sprite_frames = _load_frames(prefix)
		add_child(sprite)
		_layers.append(sprite)


func _load_frames(prefix: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in ANIMATIONS:
		var path := _find_strip(ANIMATIONS[anim], prefix)
		if path.is_empty():
			continue
		var texture: Texture2D = load(path)
		var count := texture.get_width() / FRAME_SIZE.x
		frames.add_animation(anim)
		frames.set_animation_speed(anim, FPS)
		frames.set_animation_loop(anim, true)
		for i in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y)
			frames.add_frame(anim, atlas)
	return frames


func _find_strip(folder: String, prefix: String) -> String:
	# Finds e.g. "base_walk_strip8.png" without needing to know the exact name.
	var dir := HUMAN_DIR + folder + "/"
	for file in ResourceLoader.list_directory(dir):
		if file.begins_with(prefix + "_") and file.ends_with(".png"):
			return dir + file
	push_warning("No '%s' sprite found in %s" % [prefix, dir])
	return ""


func _build_collision() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 6)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, 5) # at the character's feet
	add_child(collision)


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	camera.position_smoothing_enabled = true
	add_child(camera)
	camera.make_current()
