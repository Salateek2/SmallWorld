extends Node2D
## SmallWorld water life: little sparkles that twinkle on the water and ducks that
## paddle around the lake. Created at runtime by map_generator with the list of
## open-water cells (no edges), in world positions.

const GLINT := "res://assets/Sunnyside_World_Assets/Elements/VFX/Glint/spr_deco_glint_01_strip6.png"
const DUCK := "res://assets/Sunnyside_World_Assets/Elements/Animals/spr_deco_duck_01_strip4.png"
const GLINT_COUNT := 14
const DUCK_SPEED := 8.0 # pixels per second, a lazy paddle

var water_spots: Array[Vector2] = [] ## centers of open-water tiles (set before adding to the tree)
var lake_spots: Array[Vector2] = [] ## open water in the big lake, where the ducks live
var duck_count := 3

var _ducks: Array[Dictionary] = [] # {sprite, target}


func _ready() -> void:
	if water_spots.is_empty():
		return
	var glint_frames := _frames(GLINT, 7, 12.0, false)
	for i in GLINT_COUNT:
		var glint := AnimatedSprite2D.new()
		glint.sprite_frames = glint_frames
		add_child(glint)
		glint.animation_finished.connect(_twinkle_again.bind(glint))
		_twinkle_again(glint)

	if lake_spots.is_empty():
		return
	var duck_frames := _frames(DUCK, 16, 6.0, true)
	for i in duck_count:
		var duck := AnimatedSprite2D.new()
		duck.sprite_frames = duck_frames
		duck.position = lake_spots.pick_random()
		duck.play()
		duck.frame = randi() % 4
		add_child(duck)
		_ducks.append({"sprite": duck, "target": lake_spots.pick_random()})


func _process(delta: float) -> void:
	for duck in _ducks:
		var sprite: AnimatedSprite2D = duck["sprite"]
		var target: Vector2 = duck["target"]
		sprite.position = sprite.position.move_toward(target, DUCK_SPEED * delta)
		if absf(target.x - sprite.position.x) > 0.5:
			sprite.flip_h = target.x < sprite.position.x # duck art faces right
		if sprite.position.distance_to(target) < 1.0:
			# Paddle somewhere nearby next (straight lines over open water only)
			duck["target"] = _nearby(lake_spots, sprite.position, 64.0)


## Waits a moment, then sparkles somewhere else on the water.
func _twinkle_again(glint: AnimatedSprite2D) -> void:
	glint.visible = false
	await get_tree().create_timer(randf_range(0.5, 3.0)).timeout
	if not is_instance_valid(glint):
		return
	glint.position = water_spots.pick_random() + Vector2(randf_range(-6, 6), randf_range(-6, 6))
	glint.visible = true
	glint.play()


func _nearby(spots: Array[Vector2], from: Vector2, radius: float) -> Vector2:
	for attempt in 20:
		var spot: Vector2 = spots.pick_random()
		if spot.distance_to(from) < radius:
			return spot
	return from


func _frames(path: String, frame_width: int, fps: float, loop: bool) -> SpriteFrames:
	var strip: Texture2D = load(path)
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", fps)
	frames.set_animation_loop("default", loop)
	for i in strip.get_width() / frame_width:
		var atlas := AtlasTexture.new()
		atlas.atlas = strip
		atlas.region = Rect2(i * frame_width, 0, frame_width, strip.get_height())
		frames.add_frame("default", atlas)
	return frames
