extends CharacterBody2D
## SmallWorld goblin.
## Wanders around, chases the player when close, attacks, gets hurt and dies.
## Spawned automatically by map_generator.gd when the game starts.

@export var max_hp: int = 3
@export var chase_speed: float = 45.0
@export var wander_speed: float = 15.0
@export var sight_range: float = 90.0
@export var attack_range: float = 18.0
@export var damage: int = 1
@export var attack_cooldown: float = 1.8

const GOBLIN_DIR := "res://assets/Sunnyside_World_Assets/Characters/Goblin/PNG/"
const FPS := 10.0
const FRAME_WIDTH := 96
# animation -> name used in the file, e.g. spr_walk_strip8.png
const ANIM_FILES := {
	"idle": "idle",
	"walk": "walk",
	"attack": "attack",
	"hurt": "hurt",
	"death": "death",
}
const ONE_SHOT := ["attack", "hurt", "death"]

var hp: int
var _sprite: AnimatedSprite2D
var _collision: CollisionShape2D
var _player: Node2D
var _busy := false
var _dead := false
var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0
var _cooldown := 0.0
var _knockback := Vector2.ZERO
var _hit_done := false


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _load_frames()
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.frame_changed.connect(_on_frame_changed)
	add_child(_sprite)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 6)
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	_collision.position = Vector2(0, 5)
	add_child(_collision)
	_play("idle")


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_cooldown -= delta

	if _busy:
		# Sliding back from a hit
		velocity = _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 400.0 * delta)
		move_and_slide()
		return

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D

	var to_player := Vector2.ZERO
	var dist := INF
	if _player and not _player.get("dead"):
		to_player = _player.global_position - global_position
		dist = to_player.length()

	if dist <= attack_range and _cooldown <= 0.0:
		_cooldown = attack_cooldown
		_face(to_player.x)
		_start_action("attack")
		return

	if dist <= sight_range:
		velocity = to_player.normalized() * chase_speed if dist > attack_range * 0.7 else Vector2.ZERO
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(1.5, 3.5)
			_wander_dir = Vector2.ZERO if randf() < 0.4 else Vector2.from_angle(randf() * TAU)
		velocity = _wander_dir * wander_speed

	move_and_slide()
	if velocity.length() > 1.0:
		_face(velocity.x)
		_play("walk")
	else:
		_play("idle")


## Called by the player's attack.
func take_damage(amount: int, from_position: Vector2) -> void:
	if _dead:
		return
	hp -= amount
	_knockback = (global_position - from_position).normalized() * 120.0
	if hp <= 0:
		_dead = true
		_collision.set_deferred("disabled", true)
		_start_action("death")
	else:
		_start_action("hurt")


func _start_action(anim: String) -> void:
	_busy = true
	_hit_done = false
	if _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
	else:
		_on_action_done(anim) # animation missing: skip straight to the result


func _on_animation_finished() -> void:
	_on_action_done(_sprite.animation)


func _on_frame_changed() -> void:
	# The club lands about halfway through the swing
	if _sprite.animation == "attack" and not _hit_done \
			and _sprite.frame >= _sprite.sprite_frames.get_frame_count("attack") / 2:
		_hit_done = true
		_hit_player()


func _hit_player() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("take_damage") \
			and global_position.distance_to(_player.global_position) <= attack_range + 6.0:
		_player.take_damage(damage, global_position)


func _on_action_done(anim: String) -> void:
	match anim:
		"attack":
			if not _hit_done:
				_hit_done = true
				_hit_player()
			_busy = false
		"hurt":
			_busy = false
		"death":
			var tween := create_tween()
			tween.tween_property(self, "modulate:a", 0.0, 0.6)
			tween.tween_callback(queue_free)


func _face(x: float) -> void:
	if x != 0.0:
		_sprite.flip_h = x < 0.0


func _play(anim: String) -> void:
	if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)


func _load_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in ANIM_FILES:
		var path := _find_strip(ANIM_FILES[anim])
		if path.is_empty():
			push_warning("Goblin: no '%s' animation found in %s" % [anim, GOBLIN_DIR])
			continue
		var texture: Texture2D = load(path)
		# Every frame is 96 px wide. (Don't trust the "_stripN" in the file name:
		# some goblin files have the wrong number there.)
		var frame_w := FRAME_WIDTH
		var count := maxi(1, texture.get_width() / frame_w)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, FPS)
		frames.set_animation_loop(anim, not ONE_SHOT.has(anim))
		for i in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_w, 0, frame_w, texture.get_height())
			frames.add_frame(anim, atlas)
	return frames


func _find_strip(anim_name: String) -> String:
	# Finds e.g. "spr_walk_strip8.png"
	for file in ResourceLoader.list_directory(GOBLIN_DIR):
		if file.begins_with("spr_" + anim_name + "_strip") and file.ends_with(".png"):
			return GOBLIN_DIR + file
	return ""
