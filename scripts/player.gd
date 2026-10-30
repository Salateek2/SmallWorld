extends CharacterBody2D
## SmallWorld player.
## Builds the layered Sunnyside character (body + hair + tools), a collision
## shape, a following camera and a small HUD from code.
## E / Space: pick a ripe crop in front of you, otherwise use the selected tool.
## 1-6 pick a tool (axe, hoe, seeds, watering can, sword, fishing rod), Q cycles.
## Press 3 again to change the seed type.
## Fishing: face water, press E to cast, wait for the "!" and press E quickly to reel in.
## Tools always work on the tile in front of the character (left or right, the way it faces).
## Mouse wheel or +/- zooms the camera in and out.
## E at the market counter opens the shop; E next to your bed sleeps until morning.
## I or Tab opens the inventory.

enum Hair { NONE, BOWL, CURLY, LONG, MOP, SHORT, SPIKEY }
enum Tool { AXE, HOE, SEEDS, WATER, SWORD, ROD }

const Farm := preload("res://scripts/farm.gd")

@export var hair: Hair = Hair.SHORT
@export var show_tools: bool = true
@export var walk_speed: float = 70.0
@export var run_speed: float = 120.0
@export var camera_zoom: float = 3.0
@export var min_zoom: float = 1.5
@export var max_zoom: float = 6.0
@export var max_hp: int = 5
@export var attack_damage: int = 1
@export var attack_range: float = 24.0

const HUMAN_DIR := "res://assets/Sunnyside_World_Assets/Characters/Human/"
const FRAME_SIZE := Vector2i(96, 64)
const FPS := 10.0
const WOOD_PER_TREE := 3
const INVINCIBLE_TIME := 1.0
const ANIM_FPS := {
	"attack": 16.0, "axe": 14.0, "dig": 20.0, "water": 8.0, "doing": 16.0,
	"cast": 15.0, "reel": 16.0, "caught": 12.0,
}

# animation name -> folder inside Characters/Human
const ANIMATIONS := {
	"idle": "IDLE",
	"walk": "WALKING",
	"run": "RUN",
	"axe": "AXE",
	"attack": "ATTACK",
	"hurt": "HURT",
	"death": "DEATH",
	"dig": "DIG",
	"water": "WATERING",
	"doing": "DOING",
	"cast": "CASTING",
	"reel": "REELING",
	"caught": "CAUGHT",
}
const ONE_SHOT := ["axe", "attack", "hurt", "death", "dig", "water", "doing", "cast", "reel", "caught"]

const UI_DIR := "res://assets/Sunnyside_World_Assets/UI/"
const TOOL_NAMES := {
	Tool.AXE: "Axe", Tool.HOE: "Hoe", Tool.SEEDS: "Seeds", Tool.WATER: "Watering can",
	Tool.SWORD: "Sword", Tool.ROD: "Fishing rod",
}
const TOOL_ICONS := {
	Tool.AXE: "axe.png", Tool.HOE: "shovel.png", Tool.WATER: "water.png", Tool.SWORD: "sword.png",
	Tool.ROD: "rod.png",
}
const TOOL_ANIMS := {
	Tool.AXE: "axe", Tool.HOE: "dig", Tool.SEEDS: "doing", Tool.WATER: "water", Tool.SWORD: "attack",
	Tool.ROD: "cast",
}

# Fishing
enum Fishing { NONE, WAITING, BITE, REELING }
const BITE_WINDOW := 0.9 # seconds you have to press E after the "!"
const FISH_ICON := "res://assets/Sunnyside_World_Assets/Elements/Crops/fish.png"
const ALERT_ICON := "res://assets/Sunnyside_World_Assets/UI/expression_alerted.png"
# Where the cast line lands, relative to the character (matches the CASTING animation);
# mirrored when facing left. Any of these spots being water is enough to fish.
const CAST_SPOTS: Array[Vector2] = [Vector2(28, 26), Vector2(20, 20), Vector2(32, 16), Vector2(24, 32)]
# Frame where the tool touches the ground / target: the effect happens there, not at the end
const IMPACT_FRAME := {"dig": 4, "water": 2, "doing": 4, "attack": 5}

const HAIR_PREFIX := {
	Hair.BOWL: "bowlhair", Hair.CURLY: "curlyhair", Hair.LONG: "longhair",
	Hair.MOP: "mophair", Hair.SHORT: "shorthair", Hair.SPIKEY: "spikeyhair",
}

var hp: int
var wood := 0
var crops := {} # crop name -> how many harvested
var coins := 50
var seeds := {"carrot": 6} # crop name -> seeds owned
var dead := false
var tool := Tool.AXE
var seed_index := 0 # which of Farm.CROP_TYPES the seeds slot plants

var _layers: Array[AnimatedSprite2D] = []
var _facing := 1.0 # 1 = right, -1 = left
var _busy := false # true during axe / attack / hurt animations
var _invincible := 0.0
var _target_enemy: Node2D
var _hud_label: Label
var _hit_done := false # the current attack already landed
var _hotbar_slots: Array[PanelContainer] = []
var _tool_label: Label
var _camera: Camera2D
var _location_label: Label
var _location := "" # name of the place we're in, for the banner
var _banner_tween: Tween
var _target_zoom := 3.0 # the camera glides toward this zoom
var _clock_label: Label
var _fade: ColorRect # black screen for sleeping
var _message: Label # big centered text ("Day 2", "You passed out...")
var _in_menu := false # shop open or sleeping: no moving or tools
var _fishing := Fishing.NONE
var _fish_timer := 0.0
var _fish_caught := false
var _above_head: Sprite2D # "!" when a fish bites, the fish when you catch it
var _toast: Label # short message above the hotbar ("It got away...")
var _toast_tween: Tween


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

	_update_zoom(delta)
	_update_clock()
	if _in_menu:
		velocity = Vector2.ZERO
		_play("idle")
		return

	if Input.is_action_just_pressed("inventory") and not _busy and _fishing == Fishing.NONE:
		_open_menu("res://scripts/inventory.gd")
		return

	_handle_tool_keys()
	_update_aim_highlight()
	_check_location()

	if _fishing != Fishing.NONE:
		velocity = Vector2.ZERO
		_update_fishing(delta)
		return

	if _busy:
		velocity = Vector2.ZERO
		return

	if Input.is_action_just_pressed("use"):
		var farm := _farm()
		var world := get_parent()
		if world.has_method("is_near_market") and world.is_near_market(global_position):
			_open_shop()
		elif world.has_method("is_near_bed") and world.is_near_bed(global_position):
			_sleep(false)
		elif tool == Tool.ROD:
			_start_fishing()
		elif tool != Tool.SWORD and farm and farm.is_ripe(_aim_point()):
			_start_action("doing") # picking a ripe crop works with any tool but the sword
		else:
			_target_enemy = _enemy_in_front() if tool == Tool.SWORD else null
			_start_action(TOOL_ANIMS[tool])
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
	# Sword, hoe, can and hands take effect mid-animation, when they touch the target
	var sprite := _layers[0]
	if IMPACT_FRAME.has(sprite.animation) and not _hit_done \
			and sprite.frame >= IMPACT_FRAME[sprite.animation]:
		_hit_done = true
		_apply_tool(sprite.animation)


## What each action does to the world. Runs once per action.
func _apply_tool(anim: String) -> void:
	var farm := _farm()
	match anim:
		"dig":
			if farm:
				farm.till(_aim_point())
		"water":
			if farm:
				farm.water(_aim_point())
		"doing":
			_harvest_or_plant()
		"attack":
			_swing_sword()


func _swing_sword() -> void:
	if _target_enemy and is_instance_valid(_target_enemy) \
			and global_position.distance_to(_target_enemy.global_position) <= attack_range + 8.0:
		_target_enemy.take_damage(attack_damage, global_position)
	elif get_parent().has_method("try_cut"):
		get_parent().try_cut(_aim_point()) # slash flowers, small bushes and mushrooms


func _on_action_done(anim: String) -> void:
	if IMPACT_FRAME.has(anim) and not _hit_done: # animation missing or too short: still apply
		_hit_done = true
		_apply_tool(anim)
	match anim:
		"axe":
			_chop()
		"cast":
			# The line is in the water: hold the last frame and wait for a bite
			_fishing = Fishing.WAITING
			_fish_timer = randf_range(2.0, 6.0)
			return
		"reel":
			_start_action("caught")
			return
		"caught":
			_finish_fishing()
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


func _harvest_or_plant() -> void:
	var farm := _farm()
	if farm == null:
		return
	var picked := farm.harvest(_aim_point())
	if picked != "":
		crops[picked] = crops.get(picked, 0) + 1
		_update_hud()
	elif tool == Tool.SEEDS:
		var seed_type: String = Farm.CROP_TYPES[seed_index]
		if seeds.get(seed_type, 0) > 0 and farm.plant(_aim_point(), seed_type):
			seeds[seed_type] -= 1
			_update_hotbar()


# --- Fishing ---------------------------------------------------------------

func _start_fishing() -> void:
	if not _can_fish():
		_show_toast("Face some water to fish (stand on the shore)")
		return
	_fish_caught = false
	_start_action("cast")


func _can_fish() -> bool:
	var world := get_parent()
	if not world.has_method("is_water"):
		return false
	for spot in CAST_SPOTS:
		if world.is_water(global_position + Vector2(spot.x * _facing, spot.y)):
			return true
	return false


func _update_fishing(delta: float) -> void:
	var pressed := Input.is_action_just_pressed("use")
	var moving := Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO
	match _fishing:
		Fishing.WAITING:
			_fish_timer -= delta
			if pressed:
				_reel_in(false, "Too early! Wait for the !")
			elif moving:
				_reel_in(false, "")
			elif _fish_timer <= 0.0:
				_fishing = Fishing.BITE
				_fish_timer = BITE_WINDOW
				_show_above_head(ALERT_ICON)
		Fishing.BITE:
			_fish_timer -= delta
			if pressed:
				_fishing = Fishing.REELING
				_fish_caught = true
				_above_head.visible = false
				_start_action("reel") # then "caught", then _finish_fishing
			elif _fish_timer <= 0.0:
				_reel_in(false, "It got away...")


func _reel_in(success: bool, message: String) -> void:
	_fishing = Fishing.REELING
	_fish_caught = success
	_above_head.visible = false
	if message != "":
		_show_toast(message)
	_start_action("caught")


func _finish_fishing() -> void:
	_fishing = Fishing.NONE
	if _fish_caught:
		crops["fish"] = crops.get("fish", 0) + 1
		_update_hud()
		_show_toast("You caught a fish!")
		_show_above_head(FISH_ICON)
		await get_tree().create_timer(1.2).timeout
		if _fishing == Fishing.NONE:
			_above_head.visible = false


func _show_above_head(path: String) -> void:
	_above_head.texture = load(path)
	_above_head.visible = true


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


# --- Day, night, sleep and shop ----------------------------------------------

func _clock() -> Node:
	return get_parent().get_node_or_null("DayNight")


func _update_clock() -> void:
	var clock := _clock()
	if clock:
		_clock_label.text = clock.time_text()


## Called by the clock at 2 AM.
func on_passed_out() -> void:
	_sleep(true)


## Fades to black, starts the next day, wakes up next to the bed.
func _sleep(passed_out: bool) -> void:
	var clock := _clock()
	if clock == null or _in_menu:
		return
	_in_menu = true
	clock.paused = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 1.0)
	await tween.finished
	clock.start_new_day()
	hp = max_hp
	if passed_out or not get_parent().is_near_bed(global_position):
		global_position = get_parent().bed_side_position()
		_camera.reset_smoothing()
	_update_hud()
	_message.text = "You passed out...\nDay %d" % clock.day if passed_out else "Day %d" % clock.day
	_message.modulate.a = 1.0
	await get_tree().create_timer(1.2).timeout
	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 1.0)
	tween.parallel().tween_property(_message, "modulate:a", 0.0, 1.0)
	await tween.finished
	_in_menu = false


func _open_shop() -> void:
	_open_menu("res://scripts/shop.gd")


## Opens a menu window (shop, inventory). Time stands still while it's open.
func _open_menu(script_path: String) -> void:
	var clock := _clock()
	if clock:
		clock.paused = true
	_in_menu = true
	var menu := CanvasLayer.new()
	menu.set_script(load(script_path))
	menu.player = self
	menu.closed.connect(_on_menu_closed)
	add_child(menu)


func _on_menu_closed() -> void:
	var clock := _clock()
	if clock:
		clock.paused = false
	# Wait a moment so the key that closed the menu doesn't open it again
	await get_tree().create_timer(0.2).timeout
	_in_menu = false


## Updates the HUD and hotbar after coins, crops or seeds change (used by the shop).
func refresh_ui() -> void:
	_update_hud()
	_update_hotbar()


func _farm() -> Farm:
	return get_parent().get_node_or_null("Farm") as Farm


## The spot tools work on: the tile in front of the feet, on the side the character faces.
func _aim_point() -> Vector2:
	return global_position + Vector2(_facing * 16.0, 6.0)


func _update_aim_highlight() -> void:
	var farm := _farm()
	if farm == null:
		return
	var p := _aim_point()
	farm.highlight_cell = farm.cell_at(p)
	farm.show_highlight = not dead and tool in [Tool.HOE, Tool.WATER, Tool.SEEDS]
	# Green outline = the tool will do something there, red = it won't
	match tool:
		Tool.HOE:
			farm.highlight_ok = farm.can_till(p)
		Tool.WATER:
			farm.highlight_ok = farm.can_water(p)
		Tool.SEEDS:
			farm.highlight_ok = farm.can_plant(p) or farm.is_ripe(p)


# --- Tools / hotbar --------------------------------------------------------

func _handle_tool_keys() -> void:
	for i in Tool.size():
		if Input.is_action_just_pressed("tool_%d" % (i + 1)):
			if i == Tool.SEEDS and tool == Tool.SEEDS:
				_next_seed_type()
			_select_tool(i)
	if Input.is_action_just_pressed("next_tool"):
		_select_tool((tool + 1) % Tool.size())


## Pressing 3 again: switch to the next seed type (all of them, even ones you have 0 of).
func _next_seed_type() -> void:
	seed_index = (seed_index + 1) % Farm.CROP_TYPES.size()


func _select_tool(t: int) -> void:
	tool = t as Tool
	_update_hotbar()


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
		"tool_1": [KEY_1, KEY_KP_1],
		"tool_2": [KEY_2, KEY_KP_2],
		"tool_3": [KEY_3, KEY_KP_3],
		"tool_4": [KEY_4, KEY_KP_4],
		"tool_5": [KEY_5, KEY_KP_5],
		"tool_6": [KEY_6, KEY_KP_6],
		"next_tool": [KEY_Q],
		"inventory": [KEY_I, KEY_TAB],
		"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
		"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
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
	_camera = Camera2D.new()
	_target_zoom = camera_zoom
	_camera.zoom = Vector2(camera_zoom, camera_zoom)
	_camera.position_smoothing_enabled = true
	add_child(_camera)
	_camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.15)


func _zoom_by(factor: float) -> void:
	_target_zoom = clampf(_target_zoom * factor, min_zoom, max_zoom)


func _update_zoom(delta: float) -> void:
	if Input.is_action_just_pressed("zoom_in"):
		_zoom_by(1.25)
	if Input.is_action_just_pressed("zoom_out"):
		_zoom_by(1.0 / 1.25)
	var z := lerpf(_camera.zoom.x, _target_zoom, minf(1.0, delta * 10.0))
	_camera.zoom = Vector2(z, z)


## Called by the map: keep the camera inside the map so the edge never shows.
func set_camera_limits(rect: Rect2) -> void:
	_camera.limit_left = int(rect.position.x)
	_camera.limit_top = int(rect.position.y)
	_camera.limit_right = int(rect.end.x)
	_camera.limit_bottom = int(rect.end.y)
	_camera.reset_smoothing() # jump straight to the spawn point instead of gliding there


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	_hud_label = Label.new()
	_hud_label.position = Vector2(16, 12)
	_hud_label.add_theme_font_size_override("font_size", 24)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_hud_label)

	_clock_label = Label.new()
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clock_label.offset_left = -320
	_clock_label.offset_right = -16
	_clock_label.offset_top = 12
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.add_theme_font_size_override("font_size", 24)
	_clock_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_clock_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_clock_label)

	_build_location_banner(hud)
	_build_hotbar(hud)

	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = -150
	_toast.offset_bottom = -120
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	hud.add_child(_toast)

	_above_head = Sprite2D.new()
	_above_head.position = Vector2(0, -18)
	_above_head.visible = false
	add_child(_above_head)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_fade)
	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 40)
	_message.modulate.a = 0.0
	hud.add_child(_message)

	add_child(hud)
	_update_hud()
	_update_hotbar()


func _build_location_banner(hud: CanvasLayer) -> void:
	# Big centered text near the top, e.g. "~ Willowbrook Village ~", that fades in and out
	_location_label = Label.new()
	_location_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_location_label.offset_top = 60
	_location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_label.add_theme_font_size_override("font_size", 36)
	_location_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_location_label.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.05))
	_location_label.add_theme_constant_override("outline_size", 10)
	_location_label.modulate.a = 0.0
	hud.add_child(_location_label)


## Shows the location banner when walking into a new named place.
func _check_location() -> void:
	var world := get_parent()
	if not world.has_method("location_name_at"):
		return
	var place: String = world.location_name_at(global_position)
	if place == _location:
		return
	_location = place
	if place == "":
		return # open countryside: no banner
	_location_label.text = "~ %s ~" % place
	if _banner_tween:
		_banner_tween.kill() # a new place interrupts the previous banner
	_banner_tween = create_tween()
	_banner_tween.tween_property(_location_label, "modulate:a", 1.0, 0.6)
	_banner_tween.tween_interval(2.0)
	_banner_tween.tween_property(_location_label, "modulate:a", 0.0, 1.0)


func _build_hotbar(hud: CanvasLayer) -> void:
	# A column at the bottom center: tool name above a row of 4 slots
	var column := VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 1.0
	column.anchor_bottom = 1.0
	column.offset_top = -12
	column.offset_bottom = -12
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_child(column)

	_tool_label = Label.new()
	_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tool_label.add_theme_font_size_override("font_size", 20)
	_tool_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_tool_label.add_theme_constant_override("outline_size", 6)
	column.add_child(_tool_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for i in Tool.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(64, 64)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if TOOL_ICONS.has(i):
			icon.texture = load(UI_DIR + TOOL_ICONS[i])
		slot.add_child(icon)
		var number := Label.new()
		number.text = str(i + 1)
		number.add_theme_font_size_override("font_size", 14)
		number.add_theme_color_override("font_outline_color", Color.BLACK)
		number.add_theme_constant_override("outline_size", 4)
		number.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		number.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		slot.add_child(number)
		row.add_child(slot)
		_hotbar_slots.append(slot)


func _update_hotbar() -> void:
	var seed_type: String = Farm.CROP_TYPES[seed_index]
	var seed_count: int = seeds.get(seed_type, 0)
	# The seeds slot shows the crop it grows into
	var seed_icon := _hotbar_slots[Tool.SEEDS].get_node("Icon") as TextureRect
	seed_icon.texture = Farm.crop_texture(seed_type, Farm.STAGES)
	seed_icon.modulate.a = 1.0 if seed_count > 0 else 0.35 # faded when you have none
	for i in _hotbar_slots.size():
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.1, 0.08, 0.75)
		style.set_corner_radius_all(6)
		style.set_border_width_all(3)
		style.border_color = Color(1.0, 0.85, 0.4) if i == tool else Color(0.4, 0.32, 0.25)
		style.set_content_margin_all(8)
		_hotbar_slots[i].add_theme_stylebox_override("panel", style)
	if tool == Tool.SEEDS:
		if seed_count > 0:
			_tool_label.text = "%s seeds x%d  (press 3 to change)" % [seed_type.capitalize(), seed_count]
		else:
			_tool_label.text = "%s seeds x0 - buy some at the market  (press 3 to change)" % seed_type.capitalize()
	else:
		_tool_label.text = TOOL_NAMES[tool]


func _update_hud() -> void:
	# Crops, fish and wood are listed in the inventory (I / Tab)
	_hud_label.text = "HP: %d / %d    Coins: %d" % [maxi(hp, 0), max_hp, coins]
