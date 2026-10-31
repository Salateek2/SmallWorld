extends StaticBody2D
## SmallWorld villager: a Sunnyside human standing in place (idle animation).
## Created at runtime by map_generator; the merchant at the market is one of these.
## Turns to face the player when they come close. Characters with an npc_id can be
## talked to (E) and show a bobbing "!" when they have a new quest or a quest to hand in.

const HUMAN_DIR := "res://assets/Sunnyside_World_Assets/Characters/Human/IDLE/"
const FRAME_WIDTH := 96

@export var hair := "longhair" ## bowlhair, curlyhair, longhair, mophair, shorthair, spikeyhair
@export var display_name := "Villager"
@export var npc_id := "" ## key in story_text.gd (NPCS / TALK); empty = can't talk

var _layers: Array[AnimatedSprite2D] = []
var _news: Sprite2D # the "!" above the head
var _name_tag: Label # only shown when the player is close


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
	label.modulate.a = 0.0
	add_child(label)
	_name_tag = label

	if npc_id != "":
		add_to_group("npc")
		_news = Sprite2D.new()
		_news.texture = load("res://assets/Sunnyside_World_Assets/UI/expression_alerted.png")
		_news.position = Vector2(0, -30)
		add_child(_news)
		var bob := _news.create_tween().set_loops()
		bob.tween_property(_news, "position:y", -33.0, 0.4).set_trans(Tween.TRANS_SINE)
		bob.tween_property(_news, "position:y", -30.0, 0.4).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if _news:
		_news.visible = Story.has_news(npc_id)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var distance := global_position.distance_to(player.global_position) if player else INF
	if distance < 80.0:
		for layer in _layers:
			layer.flip_h = player.global_position.x < global_position.x
	# Name fades in when you walk up to them
	var target := 1.0 if distance < 48.0 else 0.0
	_name_tag.modulate.a = move_toward(_name_tag.modulate.a, target, delta * 4.0)


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
