extends StaticBody2D
## SmallWorld villager: a Sunnyside human standing in place (idle animation).
## Created at runtime by map_generator; the merchant at the market is one of these.
## Turns to face the player when they come close.

const HUMAN_DIR := "res://assets/Sunnyside_World_Assets/Characters/Human/IDLE/"
const FRAME_WIDTH := 96

@export var hair := "longhair" ## bowlhair, curlyhair, longhair, mophair, shorthair, spikeyhair
@export var display_name := "Villager"

var _layers: Array[AnimatedSprite2D] = []


func _ready() -> void:
	for prefix in ["base", hair]:
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = _load_idle(prefix)
		sprite.play("idle")
		add_child(sprite)
		_layers.append(sprite)
	_layers[0].frame_changed.connect(func(): _layers[1].frame = _layers[0].frame) # keep in sync

	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 6)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, 5) # feet, like the player
	add_child(collision)

	var label := Label.new()
	label.text = display_name
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-40, -22)
	label.size = Vector2(80, 10)
	add_child(label)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and global_position.distance_to(player.global_position) < 80.0:
		for layer in _layers:
			layer.flip_h = player.global_position.x < global_position.x


func _load_idle(prefix: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 8.0)
	for file in ResourceLoader.list_directory(HUMAN_DIR):
		if file.begins_with(prefix + "_") and file.ends_with(".png"):
			var texture: Texture2D = load(HUMAN_DIR + file)
			for i in texture.get_width() / FRAME_WIDTH:
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(i * FRAME_WIDTH, 0, FRAME_WIDTH, 64)
				frames.add_frame("idle", atlas)
			break
	return frames
