extends Node2D
## SmallWorld farm: tilled soil, crops, watering and harvesting.
## Created at runtime by map_generator (named "Farm", drawn just below the Player).
## The player calls till / plant / water / harvest with a world position.
## Crops grow overnight: every night a crop was watered counts as one day of growth,
## and all soil dries out by morning (see on_new_day).

const CROPS_DIR := "res://assets/Sunnyside_World_Assets/Elements/Crops/"
## Crops the player can plant, in hotbar/shop order
const CROP_TYPES: Array[String] = ["carrot", "wheat", "potato", "cabbage", "sunflower", "pumpkin"]
## nights = watered nights until ripe, seed = shop price, sell = price per harvested crop
const CROP_DATA := {
	"carrot": {"nights": 3, "seed": 10, "sell": 30},
	"wheat": {"nights": 3, "seed": 8, "sell": 25},
	"potato": {"nights": 4, "seed": 15, "sell": 45},
	"cabbage": {"nights": 5, "seed": 25, "sell": 75},
	"sunflower": {"nights": 5, "seed": 20, "sell": 65},
	"pumpkin": {"nights": 6, "seed": 40, "sell": 140},
}
const STAGES := 5 # <crop>_00 (seed) .. <crop>_04 (ripe); <crop>_05 is the harvested item
const RIPE := STAGES - 1

var highlight_cell := Vector2i(-1, -1) ## the tile the player is aiming at (outlined)
var show_highlight := false
var highlight_ok := true ## normal gold brackets if the current tool works there, red if not

var _ground: TileMapLayer
var _soil_dry: Texture2D
var _soil_wet: Texture2D
var _corners := {} # "tl", "tr", "bl", "br" -> the pack's gold bracket textures
var _time := 0.0
var _plots := {} # cell -> {soil: Sprite2D, crop: Sprite2D or null, type, stage, wet, grown}


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


## Called by the clock every morning: watered crops grow, then all soil dries.
func on_new_day(_day: int) -> void:
	for cell in _plots:
		var plot: Dictionary = _plots[cell]
		if plot.crop != null and plot.wet and plot.stage < RIPE:
			plot.grown += 1
			# Spread the 4 growth stages evenly over the crop's nights
			var nights: int = CROP_DATA[plot.type]["nights"]
			plot.stage = mini(RIPE, plot.grown * RIPE / nights)
			if plot.grown >= nights:
				plot.stage = RIPE
			_update_crop_sprite(cell)
		_set_wet(plot, false)


func _draw() -> void:
	if not show_highlight:
		return
	# Gold corner brackets around the tile, bouncing out by a pixel and back
	var tile := Rect2(_ground.map_to_local(highlight_cell) - Vector2(8, 8), Vector2(16, 16))
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
	return not _plots.has(cell) and get_parent().is_farmable(cell)


func can_plant(world_pos: Vector2) -> bool:
	var cell := cell_at(world_pos)
	return _plots.has(cell) and _plots[cell].crop == null


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
	_plots[cell] = {"soil": soil, "crop": null, "type": "", "stage": 0, "wet": false, "grown": 0}
	return true


## Seeds: plant a crop on empty soil.
func plant(world_pos: Vector2, crop_type: String) -> bool:
	if not can_plant(world_pos):
		return false
	var cell := cell_at(world_pos)
	var plot: Dictionary = _plots[cell]
	plot.type = crop_type
	plot.stage = 0
	plot.grown = 0
	plot.crop = Sprite2D.new()
	plot.crop.centered = false
	add_child(plot.crop)
	_update_crop_sprite(cell)
	return true


## Watering can: make soil wet so the crop on it can grow.
func water(world_pos: Vector2) -> bool:
	if not can_water(world_pos):
		return false
	_set_wet(_plots[cell_at(world_pos)], true)
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


## Icon of a crop: the seed (stage 0) or the harvested item (stage 5).
static func crop_texture(crop_type: String, stage: int) -> Texture2D:
	return load(CROPS_DIR + "%s_%02d.png" % [crop_type, stage])


func _set_wet(plot: Dictionary, wet: bool) -> void:
	plot.wet = wet
	plot.soil.texture = _soil_wet if wet else _soil_dry


func _update_crop_sprite(cell: Vector2i) -> void:
	var plot: Dictionary = _plots[cell]
	var tex := crop_texture(plot.type, plot.stage)
	plot.crop.texture = tex
	# Crop sprites have different sizes: center them and stand them on the soil
	var bottom := _ground.map_to_local(cell) + Vector2(0, 4)
	plot.crop.position = (bottom - tex.get_size() * Vector2(0.5, 1.0)).round()
