extends Node2D
## SmallWorld farm: tilled soil, crops, watering, harvesting and sprinklers.
## Created at runtime by map_generator (named "Farm", drawn just below the Player).
## The player calls till / plant / water / harvest with a world position.
## Crops grow by the clock: each one needs a number of game hours in wet soil to ripen
## (a game hour is 30 real seconds). Watered soil stays wet for WET_HOURS and then dries,
## and a crop in dry soil just waits. Sprinklers keep the eight tiles around them wet,
## so those crops never need the watering can. Sleeping counts too: the night's hours pass.
##
## This script also holds the farming numbers the shops and menus share:
## crop prices, what unlocks at which farming level, and how much XP a level takes.

const CROPS_DIR := "res://assets/Sunnyside_World_Assets/Elements/Crops/"
const SPRINKLER_ICON := "res://assets/farm/sprinkler.png" # made by tools/make_sprinkler.py
## Crops the player can plant, in hotbar/shop order (the order you unlock them in)
const CROP_TYPES: Array[String] = ["carrot", "wheat", "radish", "potato", "parsnip", "cabbage",
	"beetroot", "sunflower", "kale", "cauliflower", "pumpkin"]
## hours = game hours in wet soil until ripe, seed = shop price, sell = price per harvested crop,
## level = farming level that unlocks the seeds, xp = farming XP for harvesting one.
## Quick crops earn a little, often; slow ones earn more per hour but need re-watering.
const CROP_DATA := {
	"carrot": {"hours": 3, "seed": 4, "sell": 10, "level": 1, "xp": 2},
	"wheat": {"hours": 3, "seed": 3, "sell": 8, "level": 1, "xp": 2},
	"radish": {"hours": 2, "seed": 3, "sell": 8, "level": 2, "xp": 2},
	"potato": {"hours": 5, "seed": 6, "sell": 18, "level": 2, "xp": 3},
	"parsnip": {"hours": 6, "seed": 8, "sell": 24, "level": 3, "xp": 4},
	"cabbage": {"hours": 8, "seed": 10, "sell": 34, "level": 4, "xp": 5},
	"beetroot": {"hours": 7, "seed": 10, "sell": 32, "level": 5, "xp": 5},
	"sunflower": {"hours": 9, "seed": 12, "sell": 42, "level": 5, "xp": 6},
	"kale": {"hours": 10, "seed": 14, "sell": 50, "level": 6, "xp": 7},
	"cauliflower": {"hours": 14, "seed": 18, "sell": 72, "level": 7, "xp": 9},
	"pumpkin": {"hours": 18, "seed": 22, "sell": 98, "level": 8, "xp": 12},
}
const WET_HOURS := 6.0 ## how long watered soil stays wet
## Things you can sell that aren't crops (xp = farming XP for collecting one)
const OTHER_ITEMS := {
	"fish": {"sell": 5, "xp": 1},
	"egg": {"sell": 12, "xp": 3},
	"milk": {"sell": 30, "xp": 6},
}
## Total XP needed to reach each farming level: LEVEL_XP[0] is level 1, [1] is level 2...
const LEVEL_XP: Array[int] = [0, 30, 100, 220, 400, 650, 1000, 1500, 2200, 3000]
const STAGES := 5 # <crop>_00 (seed) .. <crop>_04 (ripe); <crop>_05 is the harvested item
const RIPE := STAGES - 1

var highlight_cell := Vector2i(-1, -1) ## the tile the player is aiming at (outlined)
var highlight_length := 1 ## how many tiles in a row the tool reaches (upgraded hoe / can: 3)
var highlight_dir := 1 ## which way that row runs from highlight_cell: 1 = right, -1 = left
var show_highlight := false
var highlight_ok := true ## normal gold brackets if the current tool works there, red if not

var _ground: TileMapLayer
var _soil_dry: Texture2D
var _soil_wet: Texture2D
var _corners := {} # "tl", "tr", "bl", "br" -> the pack's gold bracket textures
var _time := 0.0
var _sparkle_time := 0.0 # until the next twinkle on a ripe crop
## cell -> {soil: Sprite2D, crop: Sprite2D or null, type, stage, wet,
##          grown: game minutes of growing so far, wet_left: game minutes until the soil dries}
var _plots := {}
var _last_minutes := -1.0 # the clock when the crops last grew (-1 = not looked yet)
var _sprinklers := {} # cell -> Sprite2D


func _ready() -> void:
	_ground = get_parent().get_node("Ground")
	transform = _ground.transform # same space as the tiles, even if the layer is moved/scaled
	_soil_dry = load(CROPS_DIR + "soil_00.png")
	_soil_wet = load(CROPS_DIR + "soil_01.png")
	for corner in ["tl", "tr", "bl", "br"]:
		_corners[corner] = load("res://assets/Sunnyside_World_Assets/UI/selectbox_%s.png" % corner)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw() # keeps the aim brackets in sync with the player and bouncing
	# Crops grow as the clock runs (checked once per game minute, twice a second)
	var clock := get_parent().get_node_or_null("DayNight")
	if clock and not clock.paused:
		if _last_minutes < 0.0 or clock.minutes < _last_minutes:
			_last_minutes = clock.minutes
		elif clock.minutes - _last_minutes >= 1.0:
			_advance(clock.minutes - _last_minutes)
			_last_minutes = clock.minutes
	# Ripe crops twinkle now and then, so you can spot what's ready to pick
	_sparkle_time -= delta
	if _sparkle_time <= 0.0:
		_sparkle_time = 0.5
		var ripe := _plots.keys().filter(func(cell): return _plots[cell].crop != null and _plots[cell].stage >= RIPE)
		if not ripe.is_empty():
			var spot := to_global(_ground.map_to_local(ripe.pick_random())) + Vector2(randf_range(-5, 5), randf_range(-10, 0))
			Juice.puff(spot, Juice.SPARKLE, 2, 6.0, -14.0)


## Called by the clock when you sleep (or pass out): the hours until 6 AM go by.
func on_new_day(_day: int) -> void:
	if _last_minutes >= 0.0:
		_advance(30 * 60 - _last_minutes) # 6 AM the next morning is minute 30 * 60
	_last_minutes = -1.0 # pick the clock up again from the new morning


## Lets `minutes` of game time pass on the farm: crops in wet soil grow, soil dries out,
## sprinklers wet the soil around them again.
func _advance(minutes: float) -> void:
	for cell in _plots:
		var plot: Dictionary = _plots[cell]
		if not plot.wet:
			continue
		if plot.crop != null and plot.stage < RIPE:
			plot.grown += minf(minutes, plot.wet_left) # only grows for as long as the soil was wet
			# Spread the 4 growth stages evenly over the crop's growing time
			var total: float = CROP_DATA[plot.type]["hours"] * 60.0
			var stage := RIPE if plot.grown >= total else int(plot.grown / total * RIPE)
			if stage != plot.stage:
				plot.stage = stage
				_update_crop_sprite(cell)
				Juice.squash(plot.crop, -0.25) # stretches up as it grows
		plot.wet_left -= minutes
		if plot.wet_left <= 0.0:
			_set_wet(plot, false)
	for cell in _sprinklers:
		_sprinkle(cell)


## A word about the crop on a tile, for the player's prompt: "Needs water" or how long
## until it's ripe. "" for empty soil and ripe crops.
func status_at(world_pos: Vector2) -> String:
	var cell := cell_at(world_pos)
	if not _plots.has(cell) or _plots[cell].crop == null or _plots[cell].stage >= RIPE:
		return ""
	var plot: Dictionary = _plots[cell]
	if not plot.wet:
		return "Needs water"
	return "Ripe in " + time_text(CROP_DATA[plot.type]["hours"] * 60.0 - plot.grown)


## How many crops are planted and have been watered (for Hazel's first lesson).
func count_growing() -> int:
	return _plots.values().filter(func(plot): return plot.crop != null and (plot.wet or plot.grown > 0)).size()


func has_crops() -> bool:
	return _plots.values().any(func(plot): return plot.crop != null)


func _draw() -> void:
	if not show_highlight:
		return
	# Gold corner brackets around the tile (or the row of tiles), bouncing out by a pixel and back
	var first := _ground.map_to_local(highlight_cell) - Vector2(8, 8)
	var tile := Rect2(first, Vector2(16 * highlight_length, 16))
	if highlight_dir < 0:
		tile.position.x -= 16 * (highlight_length - 1)
	var d := 3.0 + (1.0 if fmod(_time, 0.9) < 0.45 else 0.0)
	var tint := Color.WHITE if highlight_ok else Color(1.0, 0.4, 0.4)
	var size: Vector2 = _corners["tl"].get_size()
	draw_texture(_corners["tl"], tile.position + Vector2(-d, -d), tint)
	draw_texture(_corners["tr"], Vector2(tile.end.x - size.x + d, tile.position.y - d), tint)
	draw_texture(_corners["bl"], Vector2(tile.position.x - d, tile.end.y - size.y + d), tint)
	draw_texture(_corners["br"], tile.end - size + Vector2(d, d), tint)


## World position -> tile coordinates of the Ground layer.
func cell_at(world_pos: Vector2) -> Vector2i:
	return _ground.local_to_map(_ground.to_local(world_pos))


func can_till(world_pos: Vector2) -> bool:
	var cell := cell_at(world_pos)
	return not _plots.has(cell) and not _sprinklers.has(cell) and get_parent().is_farmable(cell)


func can_plant(world_pos: Vector2) -> bool:
	var cell := cell_at(world_pos)
	return _plots.has(cell) and _plots[cell].crop == null and not _sprinklers.has(cell)


func can_water(world_pos: Vector2) -> bool:
	var cell := cell_at(world_pos)
	return _plots.has(cell) and not _plots[cell].wet


## Hoe: turn a free grass tile into dry soil.
func till(world_pos: Vector2) -> bool:
	if not can_till(world_pos):
		return false
	var cell := cell_at(world_pos)
	var soil := Sprite2D.new()
	soil.texture = _soil_dry
	soil.position = _ground.map_to_local(cell)
	add_child(soil)
	Juice.pop_in(soil, 0.2)
	_plots[cell] = {"soil": soil, "crop": null, "type": "", "stage": 0, "wet": false, "grown": 0.0, "wet_left": 0.0}
	return true


## Seeds: plant a crop on empty soil.
func plant(world_pos: Vector2, crop_type: String) -> bool:
	if not can_plant(world_pos):
		return false
	var cell := cell_at(world_pos)
	var plot: Dictionary = _plots[cell]
	plot.type = crop_type
	plot.stage = 0
	plot.grown = 0.0
	plot.crop = Sprite2D.new()
	plot.crop.centered = false
	add_child(plot.crop)
	_update_crop_sprite(cell)
	Juice.pop_in(plot.crop)
	return true


## Watering can: make soil wet so the crop on it can grow.
func water(world_pos: Vector2) -> bool:
	if not can_water(world_pos):
		return false
	var plot: Dictionary = _plots[cell_at(world_pos)]
	_set_wet(plot, true)
	if plot.crop != null:
		Juice.squash(plot.crop, 0.2) # the plant wobbles under the water
	return true


## Returns the crop name if a ripe crop was picked, otherwise "".
func harvest(world_pos: Vector2) -> String:
	var cell := cell_at(world_pos)
	if not is_ripe(world_pos):
		return ""
	var plot: Dictionary = _plots[cell]
	var crop_type: String = plot.type
	plot.crop.queue_free()
	plot.crop = null
	plot.type = ""
	_set_wet(plot, false) # the soil stays, ready for new seeds
	return crop_type


func is_ripe(world_pos: Vector2) -> bool:
	var cell := cell_at(world_pos)
	return _plots.has(cell) and _plots[cell].crop != null and _plots[cell].stage >= RIPE


# --- Sprinklers ---------------------------------------------------------------

func has_sprinkler(world_pos: Vector2) -> bool:
	return _sprinklers.has(cell_at(world_pos))


## A sprinkler needs a free tile: grass you could dig, or empty soil.
func can_place_sprinkler(world_pos: Vector2) -> bool:
	return can_till(world_pos) or can_plant(world_pos)


## Puts a sprinkler down. It waters the soil around it straight away, and every morning.
func place_sprinkler(world_pos: Vector2) -> bool:
	if not can_place_sprinkler(world_pos):
		return false
	var cell := cell_at(world_pos)
	_add_sprinkler(cell)
	Juice.pop_in(_sprinklers[cell])
	_sprinkle(cell)
	return true


## Picks a sprinkler back up. False if there isn't one there.
func remove_sprinkler(world_pos: Vector2) -> bool:
	var cell := cell_at(world_pos)
	if not _sprinklers.has(cell):
		return false
	_sprinklers[cell].queue_free()
	_sprinklers.erase(cell)
	return true


func _add_sprinkler(cell: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(SPRINKLER_ICON)
	sprite.position = _ground.map_to_local(cell)
	add_child(sprite)
	_sprinklers[cell] = sprite


## Wets the soil on the eight tiles around a sprinkler.
func _sprinkle(cell: Vector2i) -> void:
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			var near: Vector2i = cell + Vector2i(x, y)
			if near != cell and _plots.has(near):
				_set_wet(_plots[near], true)


# --- Save / load -------------------------------------------------------------

## Every plot (and sprinkler) as plain data, for the save file.
func get_state() -> Array:
	var list := []
	for cell in _plots:
		var plot: Dictionary = _plots[cell]
		list.append({"cell": [cell.x, cell.y], "type": plot.type, "stage": plot.stage,
			"wet": plot.wet, "grown": plot.grown, "wet_left": plot.wet_left})
	for cell in _sprinklers:
		list.append({"sprinkler": [cell.x, cell.y]})
	return list


## Rebuilds the farm from saved data.
func set_state(list: Array) -> void:
	_last_minutes = -1.0 # the clock is about to jump to the saved time
	for data in list:
		if data.has("sprinkler"):
			continue # after the soil, so they sit on top of it
		var cell := Vector2i(data["cell"][0], data["cell"][1])
		var soil := Sprite2D.new()
		soil.position = _ground.map_to_local(cell)
		add_child(soil)
		var plot := {"soil": soil, "crop": null, "type": data["type"], "stage": int(data["stage"]),
			"wet": false, "grown": float(data["grown"]), "wet_left": 0.0}
		_plots[cell] = plot
		_set_wet(plot, data["wet"])
		if data.has("wet_left"):
			plot.wet_left = float(data["wet_left"])
		elif plot.type != "": # a save from when crops grew by the night: keep the stage it had
			plot.grown = CROP_DATA[plot.type]["hours"] * 60.0 * plot.stage / RIPE
		if plot.type != "":
			plot.crop = Sprite2D.new()
			plot.crop.centered = false
			add_child(plot.crop)
			_update_crop_sprite(cell)
	for data in list:
		if data.has("sprinkler"):
			_add_sprinkler(Vector2i(data["sprinkler"][0], data["sprinkler"][1]))


# --- Shared farming numbers ---------------------------------------------------

## Icon of a crop: the seed (stage 0) or the harvested item (stage 5).
static func crop_texture(crop_type: String, stage: int) -> Texture2D:
	return load(CROPS_DIR + "%s_%02d.png" % [crop_type, stage])


## What one of these sells for (crops, fish, eggs, milk).
static func item_price(item: String) -> int:
	return OTHER_ITEMS[item]["sell"] if OTHER_ITEMS.has(item) else CROP_DATA[item]["sell"]


static func item_icon(item: String) -> Texture2D:
	return load(CROPS_DIR + item + ".png") if OTHER_ITEMS.has(item) else crop_texture(item, STAGES)


## Farming XP for harvesting / collecting one (0 for things like wood).
static func item_xp(item: String) -> int:
	if OTHER_ITEMS.has(item):
		return OTHER_ITEMS[item]["xp"]
	return CROP_DATA[item]["xp"] if CROP_DATA.has(item) else 0


## Everything you can sell, in shop order.
static func sellable_items() -> Array:
	return CROP_TYPES + OTHER_ITEMS.keys()


## Game minutes as words: "2h 30m", "45m".
static func time_text(minutes: float) -> String:
	var whole := maxi(1, ceili(minutes))
	if whole >= 60:
		return "%dh %02dm" % [whole / 60, whole % 60]
	return "%dm" % whole


## Farming level (1, 2, 3...) for a total amount of XP.
static func level_for(xp: int) -> int:
	var level := 1
	for i in LEVEL_XP.size():
		if xp >= LEVEL_XP[i]:
			level = i + 1
	return level


## How far through the current level you are, 0..1 (1 at the top level).
static func level_progress(xp: int) -> float:
	var level := level_for(xp)
	if level >= LEVEL_XP.size():
		return 1.0
	return float(xp - LEVEL_XP[level - 1]) / (LEVEL_XP[level] - LEVEL_XP[level - 1])


func _set_wet(plot: Dictionary, wet: bool) -> void:
	plot.wet = wet
	plot.wet_left = WET_HOURS * 60.0 if wet else 0.0
	plot.soil.texture = _soil_wet if wet else _soil_dry


func _update_crop_sprite(cell: Vector2i) -> void:
	var plot: Dictionary = _plots[cell]
	var tex := crop_texture(plot.type, plot.stage)
	plot.crop.texture = tex
	# Crop sprites have different sizes: center them and stand them on the soil.
	# The sprite's own position is where it stands, so bounces grow from the ground up.
	var bottom := _ground.map_to_local(cell) + Vector2(0, 4)
	plot.crop.position = bottom
	plot.crop.offset = (bottom - tex.get_size() * Vector2(0.5, 1.0)).round() - bottom
