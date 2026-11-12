extends CharacterBody2D
## SmallWorld player.
## Builds the layered Sunnyside character (body + hair + tools), a collision
## shape, a following camera and a small HUD from code.
## E / Space: pick a ripe crop in front of you, otherwise use the selected tool.
## 1-7 pick a tool (axe, hoe, seeds, watering can, sword, fishing rod, sprinkler), Q cycles.
## Press 3 again to change the seed type.
## Harvesting gives farming XP: each farming level unlocks new seeds, animals and things at Gus's.
## E at the crate by your door opens the shipping bin (sold overnight).
## Fishing: face water, press E to cast, wait for the "!" and press E quickly to reel in.
## Tools always work on the tile in front of the character (left or right, the way it faces).
## Mouse wheel or +/- zooms the camera in and out.
## Keep walking and you break into a run by yourself (Shift runs straight away).
## A little "E" prompt pops up over whatever E would use (someone to talk to, a seat...),
## and one-time tips (tips.gd) explain the controls as you need them.
## E at the market counter opens the shop; E next to your bed sleeps until morning.
## I or Tab opens the inventory. E next to a villager talks to them. Esc pauses.
## Walk into water to swim (no tools while swimming).

enum Hair { NONE, BOWL, CURLY, LONG, MOP, SHORT, SPIKEY }
enum Tool { AXE, HOE, SEEDS, WATER, SWORD, ROD, SPRINKLER }

const Farm := preload("res://scripts/farm.gd")
const UIStyle := preload("res://scripts/ui_style.gd")
const SelectCursor := preload("res://scripts/select_cursor.gd")
const Ranch := preload("res://scripts/ranch.gd")
const Smithy := preload("res://scripts/smithy_shop.gd")

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
	"swim": "SWIMMING",
	"cast": "CASTING",
	"reel": "REELING",
	"caught": "CAUGHT",
	"sit": "SITTING", # made by tools/make_sitting.py
}
const ONE_SHOT := ["axe", "attack", "hurt", "death", "dig", "water", "doing", "cast", "reel", "caught"]

const UI_DIR := "res://assets/Sunnyside_World_Assets/UI/"
const TOOL_NAMES := {
	Tool.AXE: "Axe", Tool.HOE: "Hoe", Tool.SEEDS: "Seeds", Tool.WATER: "Watering can",
	Tool.SWORD: "Sword", Tool.ROD: "Fishing rod", Tool.SPRINKLER: "Sprinkler",
}
const TOOL_ICONS := {
	Tool.AXE: "axe.png", Tool.HOE: "shovel.png", Tool.WATER: "water.png", Tool.SWORD: "sword.png",
	Tool.ROD: "rod.png",
}
const TOOL_ANIMS := {
	Tool.AXE: "axe", Tool.HOE: "dig", Tool.SEEDS: "doing", Tool.WATER: "water", Tool.SWORD: "attack",
	Tool.ROD: "cast", Tool.SPRINKLER: "doing",
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
const IMPACT_FRAME := {"dig": 4, "water": 2, "doing": 4, "attack": 5, "axe": 6}

const HAIR_PREFIX := {
	Hair.BOWL: "bowlhair", Hair.CURLY: "curlyhair", Hair.LONG: "longhair",
	Hair.MOP: "mophair", Hair.SHORT: "shorthair", Hair.SPIKEY: "spikeyhair",
}

var hp: int
var wood := 0
var crops := {} # crop name -> how many harvested
var coins := 50
var seeds := {} # crop name -> seeds owned (Hazel gives you your first ones)
var xp := 0 # farming XP: harvesting crops, collecting eggs, milk and fish (see Farm.LEVEL_XP)
var upgrades: Array = [] # tools with the copper upgrade from Gus (they reach 3 tiles)
var sprinklers := 0 # sprinklers in your bag, ready to place
var dead := false
var tool := Tool.AXE
var seed_index := 0 # which of Farm.CROP_TYPES the seeds slot plants
## Tools you have. The sword has to be bought from Gus the blacksmith.
var owned_tools: Array = [Tool.AXE] # the rest you get through the story (or Gus's shop)
const TOOL_SOURCES := { # where to get tools you don't have
	Tool.HOE: "Hazel might lend you one", Tool.SEEDS: "Hazel might have some",
	Tool.WATER: "Hazel might lend you one", Tool.ROD: "Old Tom fishes by the lake",
	Tool.SWORD: "buy one from Gus", Tool.SPRINKLER: "Gus makes them",
}

var _layers: Array[AnimatedSprite2D] = []
var _facing := 1.0 # 1 = right, -1 = left
var _busy := false # true during axe / attack / hurt animations
var _invincible := 0.0
var _target_enemy: Node2D
var _hud_label: Label
var _hit_done := false # the current attack already landed
var _hotbar_slots: Array[PanelContainer] = []
var _hotbar_cursor: Control # gold corner brackets on the selected tool
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
var _sitting := false # on a stool or the sofa (E or a move key gets up)
const RUN_AFTER := 0.6 # seconds of walking before you start running by yourself
var _walk_time := 0.0 # how long you've been walking without stopping
var _run_blend := 0.0 # 0 = walking speed, 1 = running speed (eases between them)
var _prompt: PanelContainer # "E  Talk" over what E would use
var _prompt_label: Label
var _guide: Control # arrow at the edge of the screen pointing to whoever has quest news
var _guide_arrow: TextureRect
var _guide_name: Label
var _fishing := Fishing.NONE
var _swimming := false # in the water (not on the dock)
@export var swim_speed: float = 40.0
const FISH_PER_CATCH := 3 # a catch drops this many fish next to you
var _fish_timer := 0.0
var _fish_caught := false
var _above_head: Sprite2D # "!" when a fish bites, the fish when you catch it
var _toast: Label # short message above the hotbar ("It got away...")
var _toast_tween: Tween
var _quest_box: PanelContainer # current quest, under the clock
var _quest_title: Label
var _quest_goal: Label
var _level_label: Label # "Farming Lv 2" under the HP line
var _xp_fill: ColorRect # the gold part of the XP bar
var _shown_coins := 0.0 # the HUD counts up/down to your real coins
var _talking_to: Node2D # the villager we're chatting with (they stand still meanwhile)
var _step_time := 0.0 # until the next puff of dust (running) or splash (swimming)


func _ready() -> void:
	hp = max_hp
	_shown_coins = coins
	add_to_group("player")
	Story.player = self
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
		_play("sit" if _sitting else "idle") # e.g. chatting from a stool
		_prompt.visible = false
		_guide.visible = false
		return

	if Input.is_action_just_pressed("inventory") and not _busy and _fishing == Fishing.NONE:
		_open_menu("res://scripts/inventory.gd")
		return
	if Input.is_action_just_pressed("ui_cancel") and not _busy and _fishing == Fishing.NONE:
		_open_menu("res://scripts/pause_menu.gd")
		return

	_handle_tool_keys()
	_update_aim_highlight()
	_check_location()
	_update_prompt()
	_update_guide()

	if _fishing != Fishing.NONE:
		velocity = Vector2.ZERO
		_update_fishing(delta)
		return

	if _busy:
		velocity = Vector2.ZERO
		return

	var world := get_parent()
	_swimming = world.has_method("is_water") and world.is_water(global_position + Vector2(0, 5))

	if _sitting:
		_update_sitting()
		return

	if Input.is_action_just_pressed("use"):
		var farm := _farm()
		if _swimming:
			notify("You can't use that while swimming")
		elif world.has_method("is_near_market") and world.is_near_market(global_position):
			_open_shop()
		elif world.has_method("seat_near") and not world.seat_near(global_position).is_empty():
			_sit(world.seat_near(global_position))
		elif _npc_in_reach():
			_talk_to(_npc_in_reach())
		elif world.has_method("is_near_bed") and world.is_near_bed(global_position):
			_sleep(false)
		elif world.has_node("ShippingBin") and world.get_node("ShippingBin").is_near(global_position):
			_open_menu("res://scripts/shipping_menu.gd")
		elif world.has_node("Ranch") and world.get_node("Ranch").interact(self):
			pass # fed the animals or milked a cow
		elif not owned_tools.has(tool):
			notify("No %s yet - %s" % [TOOL_NAMES[tool].to_lower(), TOOL_SOURCES.get(tool, "")])
		elif tool == Tool.ROD:
			_start_fishing()
		elif tool != Tool.SWORD and farm and farm.is_ripe(_aim_point()):
			_start_action("doing") # picking a ripe crop works with any tool but the sword
		else:
			_target_enemy = _enemy_in_front() if tool == Tool.SWORD else null
			_start_action(TOOL_ANIMS[tool])
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_walk_time = _walk_time + delta if direction != Vector2.ZERO else 0.0
	var running := (Input.is_action_pressed("run") or _walk_time > RUN_AFTER) and not _swimming
	_run_blend = move_toward(_run_blend, 1.0 if running else 0.0, delta * 3.0) # speed up smoothly
	var speed := swim_speed if _swimming else lerpf(walk_speed, run_speed, _run_blend)
	velocity = direction * speed
	move_and_slide()

	if direction.x != 0.0:
		_face(direction.x)
	_update_footsteps(delta, direction)
	if _swimming:
		_play("swim") # just your head above the water
	elif direction == Vector2.ZERO:
		_play("idle")
	else:
		_play("run" if _run_blend > 0.5 else "walk")


## Little puffs of dust behind your feet when running, splashes when swimming.
func _update_footsteps(delta: float, direction: Vector2) -> void:
	if direction == Vector2.ZERO or not (_swimming or _run_blend > 0.5):
		_step_time = 0.0 # the first puff comes as soon as you get going
		return
	_step_time -= delta
	if _step_time > 0.0:
		return
	if _swimming:
		_step_time = 0.4
		Juice.puff(global_position + Vector2(0, 6), Juice.WATER, 3, 16.0, 60.0)
	else:
		_step_time = 0.24
		Juice.puff(global_position + Vector2(0, 8) - direction * 4.0, Juice.DUST, 2, 9.0, -12.0)


# --- The "E" prompt --------------------------------------------------------------

## What pressing E would do right now: {"text", "at" (world position)}, or {} for nothing
## special (then E just uses the tool in your hand). Checks things in the same order as E.
func use_target() -> Dictionary:
	var world := get_parent()
	if _busy or _fishing != Fishing.NONE or _swimming:
		return {}
	if _sitting:
		var npc := _npc_in_reach()
		if npc:
			return {"text": "Talk", "at": npc.global_position}
		return {"text": "Stand up", "at": global_position}
	if world.has_method("is_near_market") and world.is_near_market(global_position):
		return {"text": "Shop", "at": world.cell_to_world(world.market_cell + Vector2i(2, -1))}
	if world.has_method("seat_near"):
		var seat: Dictionary = world.seat_near(global_position)
		if not seat.is_empty():
			return {"text": "Sit", "at": seat["position"]}
	var npc := _npc_in_reach()
	if npc:
		return {"text": "Shop" if npc.shop != "" else "Talk", "at": npc.global_position}
	if world.has_method("is_near_bed") and world.is_near_bed(global_position):
		return {"text": "Sleep", "at": global_position}
	if world.has_node("ShippingBin") and world.get_node("ShippingBin").is_near(global_position):
		return {"text": "Ship", "at": world.get_node("ShippingBin").global_position}
	if world.has_node("Ranch"):
		var ranch_target: Dictionary = world.get_node("Ranch").interact_target(self)
		if not ranch_target.is_empty():
			return ranch_target
	var farm := _farm()
	if owned_tools.has(tool) and tool != Tool.SWORD and tool != Tool.ROD and farm and farm.is_ripe(_aim_point()):
		return {"text": "Harvest", "at": _aim_point()}
	if tool == Tool.SPRINKLER and farm and farm.has_sprinkler(_aim_point()):
		return {"text": "Pick up", "at": _aim_point()}
	return {}


func _update_prompt() -> void:
	var target := use_target()
	if target.is_empty() and _farm() and not (_busy or _sitting or _swimming or _fishing != Fishing.NONE):
		# Nothing to press E on: say how the crop you're facing is doing instead
		var status := _farm().status_at(_aim_point())
		if status != "":
			target = {"text": status, "at": _aim_point(), "plain": true}
	_prompt.visible = not target.is_empty()
	if target.is_empty():
		return
	_prompt_label.text = target["text"] if target.get("plain", false) else "E  " + target["text"]
	# Over the thing, in screen pixels (about a head's height above it)
	var screen: Vector2 = get_viewport().get_canvas_transform() * (target["at"] as Vector2 + Vector2(0, -32))
	_prompt.reset_size()
	_prompt.position = (screen - Vector2(_prompt.size.x / 2.0, _prompt.size.y)).round()


func _build_prompt(hud: CanvasLayer) -> void:
	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", UIStyle.nine("dt", 3, 10))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	_prompt.add_child(_prompt_label)
	_prompt.visible = false
	hud.add_child(_prompt)


# --- The quest arrow -----------------------------------------------------------

## An arrow at the edge of the screen (with their name) pointing to the villager who has
## quest news for you: the one with the "!" over their head. It hides once they're on
## screen. If they're inside the tavern and you're outside (or the other way round),
## it points to the door.
func _update_guide() -> void:
	_guide.visible = false
	var world := get_parent()
	var farm := _farm()
	if farm == null or not world.has_method("hall_rect"):
		return
	var target: Node2D = null
	for npc in get_tree().get_nodes_in_group("npc"):
		if Story.has_news(npc.npc_id) and (target == null or global_position.distance_to(npc.global_position)
				< global_position.distance_to(target.global_position)):
			target = npc
	if target == null:
		return
	var hall: Rect2i = world.hall_rect()
	var at := target.global_position
	var we_are_inside := hall.has_point(farm.cell_at(global_position))
	if hall.has_point(farm.cell_at(at)) != we_are_inside:
		at = world.cell_to_world(world._hall_door() if we_are_inside else world._tavern_door())
	# Where that is on the screen; nothing to show if you can already see them
	var screen_size := get_viewport().get_visible_rect().size
	var on_screen: Vector2 = get_viewport().get_canvas_transform() * at
	if Rect2(Vector2.ZERO, screen_size).grow(-40).has_point(on_screen):
		return
	var center := screen_size / 2.0
	var direction := (on_screen - center).normalized()
	# Slide out from the middle until just inside the edge (clear of the HUD and hotbar)
	var room := center - Vector2(90, 140)
	var reach := minf(room.x / maxf(absf(direction.x), 0.001), room.y / maxf(absf(direction.y), 0.001))
	var bob := sin(Time.get_ticks_msec() / 180.0) * 4.0
	_guide.position = (center + direction * (reach + bob)).round()
	_guide_arrow.rotation = direction.angle() + PI / 2.0 # the art points up
	_guide_name.text = target.display_name
	_guide.visible = true


func _build_guide(hud: CanvasLayer) -> void:
	_guide = Control.new()
	_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide.visible = false
	_guide_arrow = TextureRect.new()
	_guide_arrow.texture = load(UI_DIR + "arrow_up.png")
	_guide_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_guide_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_guide_arrow.size = Vector2(30, 39) # 3x the art
	_guide_arrow.position = -_guide_arrow.size / 2.0
	_guide_arrow.pivot_offset = _guide_arrow.size / 2.0
	_guide_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide.add_child(_guide_arrow)
	_guide_name = Label.new()
	_guide_name.position = Vector2(-100, 26)
	_guide_name.size = Vector2(200, 12)
	_guide_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_name.add_theme_font_size_override("font_size", 8)
	_guide_name.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	_guide_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_guide_name.add_theme_constant_override("outline_size", 4)
	_guide.add_child(_guide_name)
	hud.add_child(_guide)


## Sits down on a seat from the map's seat_near().
func _sit(seat: Dictionary) -> void:
	_sitting = true
	velocity = Vector2.ZERO
	global_position = seat["position"]
	_face(seat["face"])
	_play("sit")
	for layer in _layers:
		layer.position.y = seat["lift"] # up onto the stool


## While sitting: E talks to someone close by (or gets up), moving gets up.
func _update_sitting() -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("use") and _npc_in_reach():
		_talk_to(_npc_in_reach())
		_play("sit") # stay seated
	elif Input.is_action_just_pressed("use") or direction != Vector2.ZERO:
		_sitting = false
		for layer in _layers:
			layer.position.y = 0.0
		_play("idle")


## Called by goblins when their attack lands.
func take_damage(amount: int, from_position: Vector2) -> void:
	if dead or _invincible > 0.0:
		return
	hp -= amount
	_update_hud()
	_face(from_position.x - global_position.x) # turn toward the attacker
	_invincible = INVINCIBLE_TIME
	Juice.shake(3.0)
	Juice.hit_stop(0.06)
	Juice.sound("hurt")
	for layer in _layers:
		Juice.flash(layer, Color(1.0, 0.35, 0.35), 0.35) # red for a moment
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
	if anim == "attack":
		Juice.sound("swish")
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
		"axe":
			_chop()
		"dig":
			Juice.sound("dig")
			for p in _aim_points(Tool.HOE):
				if farm and farm.till(p):
					Juice.puff(p + Vector2(0, -3), Juice.DIRT, 8)
					Juice.shake(0.5)
		"water":
			Juice.sound("water")
			for p in _aim_points(Tool.WATER):
				Juice.puff(p + Vector2(0, -4), Juice.WATER, 8, 22.0)
				if farm:
					farm.water(p)
		"doing":
			_harvest_or_plant()
		"attack":
			_swing_sword()


func _swing_sword() -> void:
	if _target_enemy and is_instance_valid(_target_enemy) \
			and global_position.distance_to(_target_enemy.global_position) <= attack_range + 8.0:
		_target_enemy.take_damage(attack_damage, global_position)
		Juice.sound("hit")
		Juice.shake(1.5)
		Juice.hit_stop()
	elif get_parent().has_method("try_cut") and get_parent().try_cut(_aim_point()):
		# Slashed a flower, small bush or mushroom: bits of it fly off
		Juice.puff(_aim_point(), Juice.LEAF, 8)
		Juice.sound("chop", 1.6)


func _on_action_done(anim: String) -> void:
	if IMPACT_FRAME.has(anim) and not _hit_done: # animation missing or too short: still apply
		_hit_done = true
		_apply_tool(anim)
	match anim:
		"cast":
			# The line is in the water: hold the last frame and wait for a bite
			Juice.puff(global_position + Vector2(CAST_SPOTS[0].x * _facing, CAST_SPOTS[0].y), Juice.WATER, 6, 20.0)
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
	if not world.has_method("try_chop"):
		return
	var result: int = world.try_chop(target) # a felled tree drops wood to pick up (see pickup.gd)
	if result == 1: # hit: wood chips and a little thump
		Juice.puff(target + Vector2(0, -6), Juice.WOOD, 6)
		Juice.shake(0.8)
		Juice.sound("chop", randf_range(0.9, 1.1))
	elif result == 2: # felled: a burst of needles and a big thump
		Juice.puff(target + Vector2(0, -14), Juice.LEAF, 18, 55.0)
		Juice.puff(target, Juice.WOOD, 8)
		Juice.shake(2.5)
		Juice.sound("fell")


func _harvest_or_plant() -> void:
	var farm := _farm()
	if farm == null:
		return
	var picked := farm.harvest(_aim_point())
	if picked != "":
		crops[picked] = crops.get(picked, 0) + 1
		_update_hud()
		# The crop hops out of the ground and flies into your pocket
		Juice.toss(Farm.crop_texture(picked, Farm.STAGES), _aim_point() + Vector2(0, -6), self)
		Juice.puff(_aim_point(), Juice.LEAF, 6)
		Juice.gain(global_position + Vector2(0, -16), 1, picked)
		Juice.sound("harvest")
		add_xp(Farm.item_xp(picked))
	elif tool == Tool.SEEDS:
		var seed_type: String = Farm.CROP_TYPES[seed_index]
		if seeds.get(seed_type, 0) > 0 and farm.plant(_aim_point(), seed_type):
			seeds[seed_type] -= 1
			if seeds[seed_type] <= 0:
				_next_seed_type() # ran out: move on to seeds you still have
			_update_hotbar()
			Juice.puff(_aim_point(), Juice.DIRT, 4, 18.0)
			Juice.sound("plant")
	elif tool == Tool.SPRINKLER:
		var p := _aim_point()
		if farm.remove_sprinkler(p): # E on one that's already there picks it back up
			sprinklers += 1
			Juice.sound("tick")
		elif sprinklers <= 0:
			notify("No sprinklers left - Gus makes them")
		elif farm.place_sprinkler(p):
			sprinklers -= 1
			Juice.puff(p + Vector2(0, -6), Juice.WATER, 14, 40.0)
			Juice.sound("water")
		else:
			notify("A sprinkler needs a free tile")
		_update_hotbar()


# --- Farming level ------------------------------------------------------------

func level() -> int:
	return Farm.level_for(xp)


## Adds farming XP. Reaching a new level pays a few coins and unlocks new things to buy.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var before := level()
	xp += amount
	if level() > before:
		var bonus := level() * 25
		coins += bonus
		var text := "Farming level %d!\n+%d coins" % [level(), bonus]
		var new_things := unlocked_at(level())
		if not new_things.is_empty():
			text += "\n\nNew: " + ", ".join(new_things)
		show_big_message(text, 2.5)
		Juice.sound("harvest", 1.3)
		Juice.shake(1.0)
		Juice.puff(global_position + Vector2(0, -10), Juice.SPARKLE, 20, 60.0)
	_update_hud()


## Names of everything that farming level unlocks: seeds, animals, Gus's wares.
func unlocked_at(at_level: int) -> PackedStringArray:
	var names := PackedStringArray()
	for crop in Farm.CROP_TYPES:
		if Farm.CROP_DATA[crop]["level"] == at_level:
			names.append(crop.capitalize())
	for type in Ranch.TYPES:
		if Ranch.TYPES[type]["level"] == at_level:
			names.append(Ranch.TYPES[type]["name"])
	for ware in Smithy.WARES:
		if ware.get("level", 1) == at_level and at_level > 1:
			names.append(ware["name"])
	return names


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
				Juice.shake(0.6)
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
		# The fish flop out onto the ground behind you: walk over them to collect
		var world := get_parent()
		if world.has_method("drop_items"):
			world.drop_items(global_position + Vector2(-_facing * 14.0, 0), "fish", load(FISH_ICON),
				FISH_PER_CATCH, Vector2(8, 16))
		_show_toast("You caught fish!")
		Juice.puff(global_position + Vector2(CAST_SPOTS[0].x * _facing, CAST_SPOTS[0].y), Juice.WATER, 10, 35.0)
		_show_above_head(FISH_ICON)
		await get_tree().create_timer(1.2).timeout
		if _fishing == Fishing.NONE:
			_above_head.visible = false


func _show_above_head(path: String) -> void:
	_above_head.texture = load(path)
	_above_head.visible = true
	Juice.pop_in(_above_head)


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	Juice.squash(_toast, 0.12, 0.25)
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
	_update_quest_tracker()
	_update_coin_counter()


## The coins on the HUD roll up (or down) to the real number instead of jumping.
func _update_coin_counter() -> void:
	if int(_shown_coins) == coins:
		return
	if _shown_coins == roundf(_shown_coins) and coins > _shown_coins:
		Juice.sound("coin") # just got paid
	var step := maxf(0.34, absf(coins - _shown_coins) * 0.12)
	_shown_coins = move_toward(_shown_coins, coins, step)
	if int(_shown_coins) == coins:
		_shown_coins = coins
	_update_hud()


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
	var day_text := ("You passed out...\nDay %d" if passed_out else "Day %d") % clock.day
	# What the shipping bin sold overnight
	var bin := get_parent().get_node_or_null("ShippingBin")
	var earned: int = bin.take_report() if bin else 0
	if earned > 0:
		day_text += "\n\nShipped: +%d coins" % earned
	_message.text = day_text
	_message.modulate.a = 1.0
	await get_tree().create_timer(2.4 if earned > 0 else 1.2).timeout
	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 1.0)
	tween.parallel().tween_property(_message, "modulate:a", 0.0, 1.0)
	await tween.finished
	_in_menu = false
	if SaveGame.save_game(): # autosave every morning
		notify("Game saved")


func _open_shop() -> void:
	_open_menu("res://scripts/shop.gd")


## The closest villager you can talk to (within reach), or null.
func _npc_in_reach() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for npc in get_tree().get_nodes_in_group("npc"):
		var d := global_position.distance_to(npc.global_position)
		if d < npc.talk_reach and d < best_dist:
			best = npc
			best_dist = d
	return best


func _talk_to(npc: Node2D) -> void:
	_face(npc.global_position.x - global_position.x)
	if npc.has_method("react"):
		npc.react() # a little bounce: they noticed you
	Juice.sound("talk", 1.0, 4.0)
	Story.talk_to(npc.npc_id) # the first chat of the day makes you closer
	if npc.shop != "":
		_hold(npc)
		_open_menu(npc.shop) # e.g. Gus's smithy
		return
	var key := Story.dialogue_for(npc.npc_id)
	if key == "":
		return
	_hold(npc)
	_face(npc.global_position.x - global_position.x)
	_open_menu("res://scripts/story/dialogue_box.gd", {"dialogue_key": key})


## The villager stops walking and waits until the window closes (see _on_menu_closed).
func _hold(npc: Node2D) -> void:
	_talking_to = npc
	if npc.has_method("set_talking"):
		npc.set_talking(true)


## Big centered text that fades in and out over the game (e.g. "Chapter 1 complete").
func show_big_message(text: String, hold := 3.5) -> void:
	_message.text = text
	var tween := create_tween()
	tween.tween_property(_message, "modulate:a", 1.0, 1.0)
	tween.tween_interval(hold)
	tween.tween_property(_message, "modulate:a", 0.0, 1.5)


## Shows a short message above the hotbar (used by the story for quest news).
func notify(text: String) -> void:
	_show_toast(text)


func _update_quest_tracker() -> void:
	var id := Story.current_quest()
	_quest_box.visible = id != ""
	if id != "":
		_quest_title.text = Story.Text.QUESTS[id]["title"]
		_quest_goal.text = Story.quest_goal_text(id)


## Opens a menu window (shop, inventory, dialogue). Time stands still while it's open.
## setup = extra properties to set on the window before it opens.
func _open_menu(script_path: String, setup := {}) -> void:
	var clock := _clock()
	if clock:
		clock.paused = true
	_in_menu = true
	var menu := CanvasLayer.new()
	menu.set_script(load(script_path))
	menu.player = self
	for property in setup:
		menu.set(property, setup[property])
	menu.closed.connect(_on_menu_closed)
	add_child(menu)


func _on_menu_closed() -> void:
	var clock := _clock()
	if clock:
		clock.paused = false
	if is_instance_valid(_talking_to) and _talking_to.has_method("set_talking"):
		_talking_to.set_talking(false) # they carry on with their day
	_talking_to = null
	# Wait a moment so the key that closed the menu doesn't open it again
	await get_tree().create_timer(0.2).timeout
	_in_menu = false


## Called by pickups when you walk over them.
func add_item(item: String, amount: int) -> void:
	if item == "wood":
		wood += amount
	else:
		crops[item] = crops.get(item, 0) + amount
		add_xp(Farm.item_xp(item) * amount) # eggs, milk and fish count as farming too
	refresh_ui()
	Juice.pickup_sound()
	Juice.gain(global_position + Vector2(0, -16), amount, item)


## Everything about the player worth saving.
func get_state() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y],
		"hp": hp, "coins": coins, "wood": wood,
		"crops": crops.duplicate(), "seeds": seeds.duplicate(),
		"tool": tool, "seed_index": seed_index, "tools": owned_tools.duplicate(),
		"xp": xp, "upgrades": upgrades.duplicate(), "sprinklers": sprinklers,
	}


## Restores a saved player. (JSON turns whole numbers into decimals, hence the int().)
func set_state(data: Dictionary) -> void:
	global_position = Vector2(data["position"][0], data["position"][1])
	hp = int(data["hp"])
	coins = int(data["coins"])
	_shown_coins = coins
	wood = int(data["wood"])
	crops = {}
	for item in data["crops"]:
		crops[item] = int(data["crops"][item])
	seeds = {}
	for item in data["seeds"]:
		seeds[item] = int(data["seeds"][item])
	seed_index = int(data["seed_index"])
	tool = int(data["tool"]) as Tool
	if data.has("tools"): # older saves had every tool
		owned_tools = data["tools"].map(func(t): return int(t))
	xp = int(data.get("xp", 0)) # (saves from before farming levels start at level 1)
	upgrades = data.get("upgrades", []).map(func(t): return int(t))
	sprinklers = int(data.get("sprinklers", 0))
	seed_index = clampi(seed_index, 0, Farm.CROP_TYPES.size() - 1)
	_camera.reset_smoothing()
	refresh_ui()


## Updates the HUD and hotbar after coins, crops or seeds change (used by the shop).
func refresh_ui() -> void:
	_update_hud()
	_update_hotbar()


func _farm() -> Farm:
	return get_parent().get_node_or_null("Farm") as Farm


## The spot tools work on: the tile in front of the feet, on the side the character faces.
func _aim_point() -> Vector2:
	return global_position + Vector2(_facing * 16.0, 6.0)


## The spots a tool works on: one tile, or three in a row with Gus's copper upgrade.
func _aim_points(t: int) -> Array[Vector2]:
	var points: Array[Vector2] = [_aim_point()]
	if upgrades.has(t):
		for i in [1, 2]:
			points.append(_aim_point() + Vector2(_facing * 16.0 * i, 0))
	return points


func _update_aim_highlight() -> void:
	var farm := _farm()
	if farm == null:
		return
	var p := _aim_point()
	farm.highlight_cell = farm.cell_at(p)
	farm.highlight_length = 3 if upgrades.has(tool) else 1
	farm.highlight_dir = int(_facing)
	farm.show_highlight = not dead and tool in [Tool.HOE, Tool.WATER, Tool.SEEDS, Tool.SPRINKLER]
	# Green outline = the tool will do something there, red = it won't
	match tool:
		Tool.HOE:
			farm.highlight_ok = _aim_points(tool).any(func(q): return farm.can_till(q))
		Tool.WATER:
			farm.highlight_ok = _aim_points(tool).any(func(q): return farm.can_water(q))
		Tool.SPRINKLER:
			farm.highlight_ok = farm.has_sprinkler(p) or (sprinklers > 0 and farm.can_place_sprinkler(p))
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


## Pressing 3 again: switch to the next seed type you have seeds for.
func _next_seed_type() -> void:
	for step in range(1, Farm.CROP_TYPES.size() + 1):
		var next := (seed_index + step) % Farm.CROP_TYPES.size()
		if seeds.get(Farm.CROP_TYPES[next], 0) > 0:
			seed_index = next
			return


func _select_tool(t: int) -> void:
	tool = t as Tool
	_update_hotbar()
	Juice.squash(_hotbar_slots[tool], -0.18, 0.2) # the slot you picked bounces
	Juice.sound("tick")


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
		layer.visible = anim != "sit" or layer.sprite_frames.has_animation(anim) # no tools in hand
		if layer.sprite_frames.has_animation(anim) and (layer.animation != anim or not layer.is_playing()):
			layer.play(anim)


# --- Setup -----------------------------------------------------------------

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
		if anim == "sit" and prefix == "tools":
			continue # empty-handed while sitting
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
	_hud_label.add_theme_font_size_override("font_size", 16)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_hud_label)

	# Farming level with an XP bar, under the HP line
	_level_label = Label.new()
	_level_label.position = Vector2(16, 40)
	_level_label.add_theme_font_size_override("font_size", 8)
	_level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_level_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_level_label)
	var xp_back := ColorRect.new()
	xp_back.color = Color(0.2, 0.12, 0.05)
	xp_back.position = Vector2(136, 40)
	xp_back.size = Vector2(124, 10)
	hud.add_child(xp_back)
	_xp_fill = ColorRect.new()
	_xp_fill.color = Color(1.0, 0.8, 0.3)
	_xp_fill.position = Vector2(138, 42)
	_xp_fill.size = Vector2(0, 6)
	hud.add_child(_xp_fill)

	_clock_label = Label.new()
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clock_label.offset_left = -320
	_clock_label.offset_right = -16
	_clock_label.offset_top = 12
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.add_theme_font_size_override("font_size", 16)
	_clock_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_clock_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_clock_label)

	# Quest tracker: light pixel box under the clock with the quest's name and goal
	_quest_box = PanelContainer.new()
	_quest_box.add_theme_stylebox_override("panel", UIStyle.nine("lt", 3, 12))
	_quest_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_quest_box.offset_top = 52
	_quest_box.offset_right = -16
	_quest_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var quest_rows := VBoxContainer.new()
	quest_rows.add_theme_constant_override("separation", 0)
	var title_row := HBoxContainer.new()
	var alert := TextureRect.new()
	alert.texture = load(UI_DIR + "expression_alerted.png")
	alert.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	alert.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	alert.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	alert.custom_minimum_size = Vector2(12, 22)
	title_row.add_child(alert)
	_quest_title = Label.new()
	_quest_title.add_theme_font_size_override("font_size", 16)
	_quest_title.add_theme_color_override("font_color", Color(0.24, 0.16, 0.12))
	title_row.add_child(_quest_title)
	quest_rows.add_child(title_row)
	_quest_goal = Label.new()
	_quest_goal.add_theme_font_size_override("font_size", 8)
	_quest_goal.add_theme_color_override("font_color", Color(0.38, 0.26, 0.2))
	quest_rows.add_child(_quest_goal)
	_quest_box.add_child(quest_rows)
	_quest_box.visible = false
	hud.add_child(_quest_box)

	_build_location_banner(hud)
	_build_hotbar(hud)

	_build_prompt(hud)
	_build_guide(hud)
	var tips := CanvasLayer.new() # one-time tips about the controls
	tips.set_script(load("res://scripts/tips.gd"))
	tips.set("player", self)
	add_child(tips)

	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = -150
	_toast.offset_bottom = -120
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 16)
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
	_message.add_theme_font_size_override("font_size", 32)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # long "New: ..." lists wrap
	_message.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.05))
	_message.add_theme_constant_override("outline_size", 12) # readable over the map too
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
	_location_label.add_theme_font_size_override("font_size", 24)
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
	# A column at the bottom center: tool name above a dark-brown bar of tool slots
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
	_tool_label.add_theme_font_size_override("font_size", 16)
	_tool_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_tool_label.add_theme_constant_override("outline_size", 6)
	column.add_child(_tool_label)

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIStyle.nine("dt", 3, 10))
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6) # 7 slots: keep clear of the tips box
	bar.add_child(row)
	for i in Tool.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(60, 60)
		slot.add_theme_stylebox_override("panel", UIStyle.nine("lt", 3, 9))
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = tool_icon(i)
		slot.add_child(icon)
		var number := Label.new()
		number.text = str(i + 1)
		number.add_theme_font_size_override("font_size", 8)
		number.add_theme_color_override("font_color", Color(0.24, 0.16, 0.12))
		number.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		number.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		slot.add_child(number)
		row.add_child(slot)
		_hotbar_slots.append(slot)
	_hotbar_cursor = SelectCursor.new()
	_hotbar_cursor.outset = 15 # the slot's 9 px padding + 6 px outside its edge
	_hotbar_slots[0].add_child(_hotbar_cursor)


## A tool's hotbar picture (null for seeds: that slot shows the crop).
func tool_icon(t: int) -> Texture2D:
	if t == Tool.SPRINKLER:
		return load(Farm.SPRINKLER_ICON)
	return load(UI_DIR + TOOL_ICONS[t]) if TOOL_ICONS.has(t) else null


func _update_hotbar() -> void:
	var seed_type: String = Farm.CROP_TYPES[seed_index]
	var seed_count: int = seeds.get(seed_type, 0)
	# The seeds slot shows the crop it grows into
	var seed_icon := _hotbar_slots[Tool.SEEDS].get_node("Icon") as TextureRect
	seed_icon.texture = Farm.crop_texture(seed_type, Farm.STAGES)
	seed_icon.modulate.a = 1.0 if seed_count > 0 else 0.35 # faded when you have none
	for t in Tool.size():
		if t != Tool.SEEDS:
			_hotbar_slots[t].get_node("Icon").modulate.a = 1.0 if owned_tools.has(t) else 0.25
	if _hotbar_cursor.get_parent() != _hotbar_slots[tool]:
		_hotbar_cursor.reparent(_hotbar_slots[tool], false)
	if tool == Tool.SEEDS:
		if seed_count > 0:
			_tool_label.text = "%s seeds x%d  (press 3 to change)" % [seed_type.capitalize(), seed_count]
		else:
			_tool_label.text = "%s seeds x0 - buy some at the market  (press 3 to change)" % seed_type.capitalize()
	elif not owned_tools.has(tool):
		_tool_label.text = "%s - %s" % [TOOL_NAMES[tool], TOOL_SOURCES.get(tool, "not yours yet")]
	elif tool == Tool.SPRINKLER:
		_tool_label.text = "Sprinkler x%d  (waters the 8 tiles around it)" % sprinklers
	elif upgrades.has(tool):
		_tool_label.text = "Copper %s  (3 tiles)" % TOOL_NAMES[tool].to_lower()
	else:
		_tool_label.text = TOOL_NAMES[tool]


## Gives you a tool (bought from a shop) and puts it in your hand.
func give_tool(t: int) -> void:
	if not owned_tools.has(t):
		owned_tools.append(t)
	_select_tool(t)
	refresh_ui()


func _update_hud() -> void:
	# Crops, fish and wood are listed in the inventory (I / Tab)
	_hud_label.text = "HP: %d / %d    Coins: %d" % [maxi(hp, 0), max_hp, int(_shown_coins)]
	_level_label.text = "Farming Lv %d" % level()
	_xp_fill.size.x = 120.0 * Farm.level_progress(xp)
