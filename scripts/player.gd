extends CharacterBody2D
## SmallWorld player.
## Builds the layered Sunnyside character (body + hair + tools), a collision
## shape, a following camera and a small HUD from code.
## E / Space: attack a goblin in front of you, otherwise swing the axe at a tree.

enum Hair { NONE, BOWL, CURLY, LONG, MOP, SHORT, SPIKEY }

@export var hair: Hair = Hair.SHORT
@export var show_tools: bool = true
@export var walk_speed: float = 70.0
@export var run_speed: float = 120.0
@export var camera_zoom: float = 3.0
@export var max_hp: int = 5
@export var attack_damage: int = 1
@export var attack_range: float = 24.0

const HUMAN_DIR := "res://assets/Sunnyside_World_Assets/Characters/Human/"
const FRAME_SIZE := Vector2i(96, 64)
const FPS := 10.0
const WOOD_PER_TREE := 3
const INVINCIBLE_TIME := 1.0
const ANIM_FPS := {"attack": 16.0, "axe": 14.0} # faster than the default FPS

# animation name -> folder inside Characters/Human
const ANIMATIONS := {
	"idle": "IDLE",
	"walk": "WALKING",
	"run": "RUN",
	"axe": "AXE",
	"attack": "ATTACK",
	"hurt": "HURT",
	"death": "DEATH",
}
const ONE_SHOT := ["axe", "attack", "hurt", "death"] # play once instead of looping

const HAIR_PREFIX := {
	Hair.BOWL: "bowlhair", Hair.CURLY: "curlyhair", Hair.LONG: "longhair",
	Hair.MOP: "mophair", Hair.SHORT: "shorthair", Hair.SPIKEY: "spikeyhair",
}

var hp: int
var wood := 0
var dead := false

var _layers: Array[AnimatedSprite2D] = []
var _facing := 1.0 # 1 = right, -1 = left
var _busy := false # true during axe / attack / hurt animations
var _invincible := 0.0
var _target_enemy: Node2D
var _hud_label: Label
var _hit_done := false # the current attack already landed


func _ready() -> void:
	hp = max_hp
	add_to_group("player")
	_setup_input()
	_build_sprite_layers()
	_build_collision()
	_build_camera()
	_build_hud()
	_layers[0].animation_finished.connect(_on_animation_finished)
	_layers[0].frame_changed.connect(_on_frame_changed)
	if global_position == Vector2.ZERO:
		global_position = Vector2(80, 330) # near the road of the generated map
	_play("idle")


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _invincible > 0.0:
		_invincible -= delta
		modulate.a = 0.5 if int(_invincible * 10) % 2 == 0 else 1.0 # blink
		if _invincible <= 0.0:
			modulate.a = 1.0

	if _busy:
		velocity = Vector2.ZERO
		return

	if Input.is_action_just_pressed("use"):
		_target_enemy = _enemy_in_front()
		_start_action("attack" if _target_enemy else "axe")
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running := Input.is_action_pressed("run")
	velocity = direction * (run_speed if running else walk_speed)
	move_and_slide()

	if direction == Vector2.ZERO:
		_play("idle")
	else:
		_play("run" if running else "walk")
		if direction.x != 0.0:
			_face(direction.x)


## Called by goblins when their attack lands.
func take_damage(amount: int, from_position: Vector2) -> void:
	if dead or _invincible > 0.0:
		return
	hp -= amount
	_update_hud()
	_face(from_position.x - global_position.x) # turn toward the attacker
	_invincible = INVINCIBLE_TIME
	if hp <= 0:
		dead = true
		modulate.a = 1.0
		_start_action("death")
	elif not (_busy and _layers[0].animation == "attack"):
		_start_action("hurt") # getting hit mid-swing doesn't cancel your attack


# --- Actions ---------------------------------------------------------------

func _start_action(anim: String) -> void:
	_busy = true
	_hit_done = false
	if _layers[0].sprite_frames.has_animation(anim):
		_play(anim)
	else:
		_on_action_done(anim) # animation missing: skip straight to the result


func _on_animation_finished() -> void:
	_on_action_done(_layers[0].animation)


func _on_frame_changed() -> void:
	# The sword hits halfway through the swing, not at the very end
	var sprite := _layers[0]
	if sprite.animation == "attack" and not _hit_done \
			and sprite.frame >= sprite.sprite_frames.get_frame_count("attack") / 2:
		_hit_done = true
		_hit_enemy()


func _hit_enemy() -> void:
	if _target_enemy and is_instance_valid(_target_enemy) \
			and global_position.distance_to(_target_enemy.global_position) <= attack_range + 8.0:
		_target_enemy.take_damage(attack_damage, global_position)


func _on_action_done(anim: String) -> void:
	match anim:
		"axe":
			_chop()
		"attack":
			if not _hit_done: # animation missing or skipped: still hit
				_hit_done = true
				_hit_enemy()
		"death":
			_hud_label.text = "You died... restarting"
			await get_tree().create_timer(2.0).timeout
			get_tree().reload_current_scene()
			return
	_busy = false
	_play("idle")


func _chop() -> void:
	# The spot just in front of the character, at foot level
	var target := global_position + Vector2(_facing * 12.0, 4.0)
	var world := get_parent()
	if world.has_method("try_chop"):
		var result: int = world.try_chop(target)
		if result == 2: # tree felled
			wood += WOOD_PER_TREE
			_update_hud()


func _enemy_in_front() -> Node2D:
	var best: Node2D = null
	var best_dist := attack_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset: Vector2 = enemy.global_position - global_position
		var d := offset.length()
		# close enough, and on the side we're facing (or right on top of us)
		if d <= best_dist and offset.x * _facing > -4.0:
			best = enemy
			best_dist = d
	return best


func _face(x: float) -> void:
	if x == 0.0:
		return
	_facing = signf(x)
	for layer in _layers:
		layer.flip_h = _facing < 0.0


func _play(anim: String) -> void:
	for layer in _layers:
		if layer.sprite_frames.has_animation(anim) and (layer.animation != anim or not layer.is_playing()):
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
		"use": [KEY_E, KEY_SPACE],
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
		frames.set_animation_speed(anim, ANIM_FPS.get(anim, FPS))
		frames.set_animation_loop(anim, not ONE_SHOT.has(anim))
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


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	_hud_label = Label.new()
	_hud_label.position = Vector2(16, 12)
	_hud_label.add_theme_font_size_override("font_size", 24)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_hud_label)
	add_child(hud)
	_update_hud()


func _update_hud() -> void:
	_hud_label.text = "HP: %d / %d    Wood: %d" % [maxi(hp, 0), max_hp, wood]
