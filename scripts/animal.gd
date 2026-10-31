extends Node2D
## SmallWorld farm animal: a chicken or cow that potters around inside its pen.
## Created by ranch.gd. Uses the pack's 4-frame animal animations (Elements/Animals).

const FRAME_SIZE := 32
const MILK_ICON := "res://assets/Sunnyside_World_Assets/Elements/Crops/milk.png"

var strip: Texture2D ## the animal's animation strip
var pen: Rect2 ## where it may walk (world pixels)
var speed := 10.0

var _sprite: AnimatedSprite2D
var _target: Vector2
var _rest := 0.0 # seconds left standing still
var _milk: Sprite2D # shown above a cow that's ready to be milked


func _ready() -> void:
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 5.0)
	for i in strip.get_width() / FRAME_SIZE:
		var atlas := AtlasTexture.new()
		atlas.atlas = strip
		atlas.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		frames.add_frame("default", atlas)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.offset = Vector2(0, -8) # feet at the node's position
	_sprite.play()
	_sprite.frame = randi() % 4
	add_child(_sprite)
	_target = position
	_rest = randf_range(0.5, 3.0)


func _process(delta: float) -> void:
	if _rest > 0.0:
		_rest -= delta
		return
	position = position.move_toward(_target, speed * delta)
	if absf(_target.x - position.x) > 0.5:
		_sprite.flip_h = _target.x > position.x # animal art faces left
	if position.distance_to(_target) < 1.0:
		_rest = randf_range(1.0, 4.0) # stop and look around for a bit
		_target = Vector2(randf_range(pen.position.x, pen.end.x), randf_range(pen.position.y, pen.end.y))


## Little milk bottle bobbing above a cow that can be milked.
func show_milk(ready: bool) -> void:
	if ready and _milk == null:
		_milk = Sprite2D.new()
		_milk.texture = load(MILK_ICON)
		_milk.position = Vector2(0, -26)
		add_child(_milk)
		var bob := _milk.create_tween().set_loops()
		bob.tween_property(_milk, "position:y", -29.0, 0.4).set_trans(Tween.TRANS_SINE)
		bob.tween_property(_milk, "position:y", -26.0, 0.4).set_trans(Tween.TRANS_SINE)
	elif not ready and _milk:
		_milk.queue_free()
		_milk = null
