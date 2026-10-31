@tool
extends Node2D
## SmallWorld map generator.
## Select the Main node and press "Generate Map" in the Inspector.
## The result is a normal tilemap, so you can fix anything by hand afterwards.
## Needs TileMapLayer children named Ground, Decor and (optional) Canopy.
## Canopy should be below Player in the Scene panel so tree tops draw over the player.
## A "Roofs" layer is added automatically for house roofs; they fade out when you walk inside.
## The tile layers are locked in the editor so they can't be dragged out of place by accident.
##
## The world is split into locations (see LOCATIONS): your farm with your house,
## a village with houses, a statue and a well, a big lake, a flower meadow and a
## pine forest along the north. Roads connect them, and a thick tree line hides the edges.

@export_tool_button("Generate Map") var generate_action = generate
@export_tool_button("Clear Map") var clear_action = clear

@export var map_width: int = 150
@export var map_height: int = 100
## 0 = a new random map every time. Any other number = the same map every time.
@export var seed_value: int = 0
## Small ponds in the open countryside (the big lake is always there)
@export var pond_count: int = 3
## Trees and decor in the open countryside between locations
@export_range(0.0, 0.2) var tree_density: float = 0.03
@export_range(0.0, 0.3) var decor_density: float = 0.06
## Goblins spawned in the forest when the game starts (not in the editor)
@export var goblin_count: int = 0

const SOURCE_ID := 0
const BORDER := 3 # tiles of dense trees along the map edge

# Tile positions in spr_tileset_sunnysideworld_16px.png (column, row)
const GRASS := Vector2i(2, 1)
const GRASS_VARIANTS: Array[Vector2i] = [
	Vector2i(2, 2), Vector2i(3, 2), Vector2i(5, 2), Vector2i(6, 2),
	Vector2i(2, 3), Vector2i(3, 3), Vector2i(5, 3), Vector2i(1, 4), Vector2i(2, 4),
]
const PATH_TILES: Array[Vector2i] = [
	Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7), Vector2i(9, 8), Vector2i(10, 8),
]
const WATER_TILES: Array[Vector2i] = [Vector2i(31, 7), Vector2i(32, 7)]

# Single-tile decorations: small bushes, flowers, rocks, stumps, mushrooms
const SMALL_DECOR: Array[Vector2i] = [
	Vector2i(27, 2), Vector2i(28, 2), Vector2i(29, 2), Vector2i(30, 2),
	Vector2i(27, 3), Vector2i(28, 3), Vector2i(29, 3), Vector2i(30, 3),
	Vector2i(31, 1), Vector2i(31, 2), Vector2i(31, 3), Vector2i(34, 1), Vector2i(34, 2),
	Vector2i(31, 4), Vector2i(32, 4), Vector2i(33, 4),
	Vector2i(31, 5), Vector2i(32, 5), Vector2i(49, 7),
]
const FLOWERS: Array[Vector2i] = [
	Vector2i(31, 1), Vector2i(31, 2), Vector2i(31, 3), Vector2i(34, 1), Vector2i(34, 2),
]
const FOREST_DECOR: Array[Vector2i] = [
	Vector2i(49, 7), Vector2i(49, 7), # mushrooms twice as likely
	Vector2i(27, 2), Vector2i(28, 2), Vector2i(29, 3), Vector2i(30, 3), Vector2i(31, 5),
]

# Multi-tile objects: top-left tile and size in tiles
const BIG_OBJECTS := [
	{"origin": Vector2i(49, 1), "size": Vector2i(2, 2)}, # round bush
	{"origin": Vector2i(49, 3), "size": Vector2i(2, 2)}, # apple bush
	{"origin": Vector2i(49, 5), "size": Vector2i(2, 2)}, # orange bush
	{"origin": Vector2i(52, 3), "size": Vector2i(1, 3)}, # small pine
	{"origin": Vector2i(51, 6), "size": Vector2i(2, 3)}, # tall pine
]
const PINES := [3, 4] # indices in BIG_OBJECTS
const FRUIT_BUSHES := [1, 2]

# Houses are built from pieces (see _build_house). Each roof colour is the same set of
# pieces, 8 rows further down the tileset: blue (your house), green, orange, red, purple.
const HOUSE_COLOURS: Array[int] = [0, 8, 16, 24, 32] # row offset of each colour set
const HOUSE_HEIGHT := 6 # rows: roof top, 3 roof rows, eave, front wall with door
const POST_LEFT := Vector2i(15, 9) # + (0, row) ; left wall post
const ROOF := Vector2i(16, 9) # + (0, row) ; row 0 top edge, 3 = shingles, 4 = eave
const POST_RIGHT := Vector2i(17, 9)
const ROOF_WINDOW := Vector2i(18, 10) # little X attic window in the roof
const WALL_WINDOW := Vector2i(16, 14) # front wall with a window
const DOOR := Vector2i(16, 15)
const FLOOR := Vector2i(10, 10) # wooden floor inside
const BACK_WALL := Vector2i(10, 9)
# Furniture: top-left tile and size
const BED := {"origin": Vector2i(39, 33), "size": Vector2i(2, 2)}
const SHELVES: Array[Vector2i] = [ # 1x2 bookcases, cupboards, wardrobe, dresser
	Vector2i(42, 33), Vector2i(43, 33), Vector2i(44, 33), Vector2i(45, 33), Vector2i(46, 33), Vector2i(47, 33),
]
const RUG := {"origin": Vector2i(43, 35), "size": Vector2i(3, 2)}
const JARS: Array[Vector2i] = [Vector2i(46, 32), Vector2i(47, 32), Vector2i(48, 32), Vector2i(51, 32)]

const WELL := {"origin": Vector2i(37, 19), "size": Vector2i(2, 2)}
const MARKET_CRATES := {"origin": Vector2i(35, 9), "size": Vector2i(5, 2)} # three crate stacks
const STATUE := {"origin": Vector2i(44, 18), "size": Vector2i(2, 4), "solid_rows": 2}

## Named places: center as a fraction of the map size, radius in tiles.
## The forest is the band along the top of the map instead (see _forest_edge).
const LOCATIONS := {
	"farm": {"name": "Your Farm", "center": Vector2(0.30, 0.56), "radius": Vector2(13, 10)},
	"village": {"name": "Willowbrook Village", "center": Vector2(0.64, 0.47), "radius": Vector2(14, 11)},
	"lake": {"name": "Mirror Lake", "center": Vector2(0.80, 0.80), "radius": Vector2(17, 10)},
	"meadow": {"name": "Sunny Meadow", "center": Vector2(0.13, 0.82), "radius": Vector2(13, 9)},
}
const FOREST_NAME := "Pinewood Forest"

# Solid areas per tile, in tile pixels (x, y, width, height) from the tile's top-left.
# Trees and bushes are only solid at the trunk/bottom, so you can walk behind them.
const COLLISION_RECTS := {
	Vector2i(31, 7): Rect2(0, 0, 16, 16), Vector2i(32, 7): Rect2(0, 0, 16, 16), # water
	Vector2i(49, 2): Rect2(6, 0, 10, 7), Vector2i(50, 2): Rect2(0, 0, 10, 7), # round bush
	Vector2i(49, 4): Rect2(6, 0, 10, 7), Vector2i(50, 4): Rect2(0, 0, 10, 7), # apple bush
	Vector2i(49, 6): Rect2(6, 0, 10, 7), Vector2i(50, 6): Rect2(0, 0, 10, 7), # orange bush
	Vector2i(52, 5): Rect2(5, 9, 6, 5), # small pine trunk
	Vector2i(51, 8): Rect2(11, 0, 5, 5), Vector2i(52, 8): Rect2(0, 0, 5, 5), # tall pine trunk
	Vector2i(31, 4): Rect2(2, 3, 12, 8), Vector2i(32, 4): Rect2(1, 2, 14, 9), Vector2i(33, 4): Rect2(3, 5, 9, 7), # rocks
	Vector2i(31, 5): Rect2(2, 4, 12, 10), Vector2i(32, 5): Rect2(2, 4, 12, 10), # stumps
	Vector2i(27, 2): Rect2(6, 7, 8, 5), Vector2i(28, 2): Rect2(6, 7, 8, 5), # small bushes
	Vector2i(29, 2): Rect2(6, 7, 8, 5), Vector2i(30, 2): Rect2(6, 7, 8, 5),
	Vector2i(27, 3): Rect2(3, 2, 6, 6), Vector2i(28, 3): Rect2(3, 2, 6, 6),
	Vector2i(29, 3): Rect2(3, 2, 6, 6), Vector2i(30, 3): Rect2(3, 2, 6, 6),
	Vector2i(37, 20): Rect2(6, 0, 10, 12), Vector2i(38, 20): Rect2(0, 0, 10, 12), # well
	Vector2i(44, 20): Rect2(0, 4, 16, 12), Vector2i(45, 20): Rect2(0, 4, 16, 12), # statue base
	Vector2i(44, 21): Rect2(0, 0, 16, 10), Vector2i(45, 21): Rect2(0, 0, 16, 10),
	Vector2i(35, 10): Rect2(8, 0, 8, 14), Vector2i(36, 10): Rect2(0, 0, 8, 14), # market crates
	Vector2i(37, 10): Rect2(8, 0, 8, 14), Vector2i(38, 10): Rect2(0, 0, 8, 14),
	Vector2i(39, 10): Rect2(0, 0, 16, 14),
}
# Furniture you bump into (bottom tile of beds and cupboards)
const FURNITURE_RECTS := {
	Vector2i(39, 34): Rect2(0, 0, 16, 12), Vector2i(40, 34): Rect2(0, 0, 16, 12),
	Vector2i(42, 34): Rect2(0, 0, 16, 10), Vector2i(43, 34): Rect2(0, 0, 16, 10),
	Vector2i(44, 34): Rect2(0, 0, 16, 10), Vector2i(45, 34): Rect2(0, 0, 16, 10),
	Vector2i(46, 34): Rect2(0, 0, 13, 10), Vector2i(47, 34): Rect2(0, 0, 16, 10),
}

enum ChopResult { NOTHING, HIT, FELLED }
const CHOPPABLE := PINES
const STUMP := Vector2i(31, 5)
const HITS_TO_CHOP := 3
## The creator's shake animation for the tall pine (4 frames, 28 px wide). Its pixels match
## the tileset pine exactly when drawn 2 px right and 1 px up from the tree's top-left.
const PINE_SHAKE := "res://assets/Sunnyside_World_Assets/Elements/Plants/spr_deco_tree_02_strip4.png"
const PINE_SHAKE_OFFSET := Vector2(2, -1)
# Small decor the sword can slash away: small bushes, flowers, mushroom (not rocks/stumps)
const CUTTABLE: Array[Vector2i] = [
	Vector2i(27, 2), Vector2i(28, 2), Vector2i(29, 2), Vector2i(30, 2),
	Vector2i(27, 3), Vector2i(28, 3), Vector2i(29, 3), Vector2i(30, 3),
	Vector2i(31, 1), Vector2i(31, 2), Vector2i(31, 3), Vector2i(34, 1), Vector2i(34, 2),
	Vector2i(49, 7),
]

var _tree_hits := {} # tree cell -> hits so far

## Houses on the map: footprint rect and door cell (saved with the scene by Generate Map).
## The first one is your home.
@export_storage var houses: Array[Dictionary] = []
## Top-left tile of the market counter in the village
@export_storage var market_cell := Vector2i(-1, -1)

var _rng := RandomNumberGenerator.new()
var _blocked := {} # cells that already have a path, water or object
var _source: TileSetAtlasSource
var _roofs: Array[TileMapLayer] = [] # one per house at runtime, faded when you're inside


func _ready() -> void:
	_fix_layers()
	if Engine.is_editor_hint():
		return
	_setup_houses()
	_spawn_farm()
	_spawn_clock()
	_spawn_merchant()
	_spawn_story_characters()
	_setup_world_bounds()
	_place_player()
	_spawn_goblins()


func generate() -> void:
	var ground := get_node_or_null("Ground") as TileMapLayer
	var decor := get_node_or_null("Decor") as TileMapLayer
	if ground == null or decor == null:
		push_error("Main needs two TileMapLayer children named 'Ground' and 'Decor'.")
		return

	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

	var canopy := get_node_or_null("Canopy") as TileMapLayer
	if canopy:
		canopy.collision_enabled = false
	else:
		canopy = decor # no Canopy layer: tree tops go on Decor instead
	var roofs := _get_or_create_roofs(ground)
	_fix_layers()

	_source = ground.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	for layer in [ground, decor]:
		_setup_collision(layer.tile_set)

	clear()
	houses.clear()
	_fill_grass(ground)
	var layers := {"ground": ground, "decor": decor, "canopy": canopy, "roofs": roofs}
	_make_home(layers)
	_make_lake(ground)
	var plaza := _make_village(layers)
	_make_roads(ground, decor, plaza)
	for i in pond_count:
		_make_pond(ground)
	_scatter_objects(decor, canopy)
	print("SmallWorld map generated (seed %d)" % _rng.seed)


func clear() -> void:
	_blocked.clear()
	for layer_name in ["Ground", "Decor", "Canopy", "Roofs"]:
		var layer := get_node_or_null(layer_name) as TileMapLayer
		if layer:
			layer.clear()


# --- Locations --------------------------------------------------------------

## Which location a tile belongs to: "farm", "village", "lake", "meadow", "forest" or "".
func location_at(cell: Vector2i) -> String:
	for key in LOCATIONS:
		if _in_ellipse(cell, location_center(key), LOCATIONS[key]["radius"]):
			return key
	if cell.y < _forest_edge(cell.x):
		return "forest"
	return ""


## The location's display name, e.g. "Willowbrook Village" ("" for open countryside).
func location_name(key: String) -> String:
	if key == "forest":
		return FOREST_NAME
	return LOCATIONS[key]["name"] if LOCATIONS.has(key) else ""


func location_center(key: String) -> Vector2i:
	var c: Vector2 = LOCATIONS[key]["center"]
	return Vector2i(int(c.x * map_width), int(c.y * map_height))


## Where the player starts: just in front of their house on the farm.
func home_spawn_cell() -> Vector2i:
	return location_center("farm") + Vector2i(0, -1)


## The forest covers everything above this wavy line.
func _forest_edge(x: int) -> float:
	return map_height * 0.24 + 3.0 * sin(x * 0.13) + 2.0 * sin(x * 0.31 + 1.0)


func _in_ellipse(cell: Vector2i, center: Vector2i, radius: Vector2) -> bool:
	var d := Vector2(cell - center) / radius
	return d.length_squared() <= 1.0


# --- Building the map -------------------------------------------------------

func _fill_grass(ground: TileMapLayer) -> void:
	for x in map_width:
		for y in map_height:
			var tile := GRASS
			if _rng.randf() < 0.15:
				tile = GRASS_VARIANTS[_rng.randi() % GRASS_VARIANTS.size()]
			ground.set_cell(Vector2i(x, y), SOURCE_ID, tile)


func _paint_path(ground: TileMapLayer, decor: TileMapLayer, cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return
	if WATER_TILES.has(ground.get_cell_atlas_coords(cell)) or decor.get_cell_source_id(cell) != -1:
		return # roads stop at water and go around buildings
	ground.set_cell(cell, SOURCE_ID, PATH_TILES[_rng.randi() % PATH_TILES.size()])
	_blocked[cell] = true


func _make_home(layers: Dictionary) -> void:
	# Your blue house at the top of the farm clearing, door facing the field
	var door := home_spawn_cell() + Vector2i(0, -2)
	_build_house(layers, door - Vector2i(3, HOUSE_HEIGHT - 1), 5, HOUSE_COLOURS[0])


## Builds a house with its top-left corner at `cell`. inner = width of the room in tiles.
## Layers: floor/back wall on Ground, furniture and front wall on Decor (under the player),
## side posts on Canopy (over the player), roof on Roofs (over the player, fades when inside).
func _build_house(layers: Dictionary, cell: Vector2i, inner: int, colour: int) -> void:
	var ground: TileMapLayer = layers["ground"]
	var decor: TileMapLayer = layers["decor"]
	var canopy: TileMapLayer = layers["canopy"]
	var roofs: TileMapLayer = layers["roofs"]
	var width := inner + 2
	var shade := Vector2i(0, colour)
	var door_x := 1 + inner / 2
	var window_x := 1 + (inner - 1) / 2 if inner % 2 == 0 else door_x
	for x in width:
		for y in HOUSE_HEIGHT:
			var c := cell + Vector2i(x, y)
			_blocked[c] = true
			if x == 0 or x == width - 1:
				# Side posts; the bottom one is part of the front wall
				var post := (POST_LEFT if x == 0 else POST_RIGHT) + shade + Vector2i(0, y)
				_set_tile(decor if y == HOUSE_HEIGHT - 1 else canopy, c, post)
				continue
			if y > 0:
				_set_tile(ground, c, BACK_WALL if y == 1 else FLOOR)
			if y == HOUSE_HEIGHT - 1:
				_set_tile(decor, c, (DOOR if x == door_x else WALL_WINDOW) + shade)
				continue
			var roof := ROOF + shade + Vector2i(0, y)
			if y == 1 or y == 2:
				roof = ROOF + shade + Vector2i(0, 3) # plain shingles
				if y == 1 and x == window_x:
					roof = ROOF_WINDOW + shade
			_set_tile(roofs, c, roof)

	# Furniture: bed in the corner, a cupboard, a rug by the door and a pot
	_place_tiles(decor, cell + Vector2i(1, 1), BED)
	var shelf: Vector2i = _pick(SHELVES)
	_place_tiles(decor, cell + Vector2i(inner, 1), {"origin": shelf, "size": Vector2i(1, 2)})
	if inner >= 5:
		_place_tiles(decor, cell + Vector2i(inner - 1, 1), {"origin": _pick(SHELVES), "size": Vector2i(1, 2)})
	_place_tiles(decor, cell + Vector2i(door_x - 1, 3), RUG)
	_set_tile(decor, cell + Vector2i(1, 4), _pick(JARS))

	houses.append({
		"rect": Rect2i(cell, Vector2i(width, HOUSE_HEIGHT)),
		"door": cell + Vector2i(door_x, HOUSE_HEIGHT - 1),
	})


func _set_tile(layer: TileMapLayer, cell: Vector2i, coords: Vector2i) -> void:
	if not _source.has_tile(coords):
		_source.create_tile(coords) # tiles that weren't set up in the TileSet yet
	layer.set_cell(cell, SOURCE_ID, coords)


## Copies a block of tiles (furniture) without splitting it over layers.
func _place_tiles(layer: TileMapLayer, cell: Vector2i, obj: Dictionary) -> void:
	for ox in obj["size"].x:
		for oy in obj["size"].y:
			_set_tile(layer, cell + Vector2i(ox, oy), obj["origin"] + Vector2i(ox, oy))


func _make_lake(ground: TileMapLayer) -> void:
	var center := location_center("lake")
	var radius: Vector2 = LOCATIONS["lake"]["radius"] - Vector2(3, 2) # leave a grassy shore
	var phase := _rng.randf() * TAU
	for x in range(-int(radius.x) - 3, int(radius.x) + 4):
		for y in range(-int(radius.y) - 3, int(radius.y) + 4):
			# Wobble the radius with the angle so the shore isn't a perfect oval
			var angle := atan2(float(y), float(x))
			var wobble := 1.0 + 0.12 * sin(angle * 3.0 + phase) + 0.07 * sin(angle * 5.0 + phase * 2.0)
			var d := Vector2(x, y) / (radius * wobble)
			var cell := center + Vector2i(x, y)
			if d.length_squared() <= 1.0 and cell.x >= BORDER and cell.x < map_width - BORDER \
					and cell.y >= BORDER and cell.y < map_height - BORDER:
				ground.set_cell(cell, SOURCE_ID, WATER_TILES[_rng.randi() % WATER_TILES.size()])
				_blocked[cell] = true


## Builds the village around a dirt plaza. Returns the plaza's center tile.
func _make_village(layers: Dictionary) -> Vector2i:
	var ground: TileMapLayer = layers["ground"]
	var decor: TileMapLayer = layers["decor"]
	var canopy: TileMapLayer = layers["canopy"]
	var c := location_center("village")
	var plaza_radius := Vector2(6, 4)
	for x in range(-6, 7):
		for y in range(-4, 5):
			if _in_ellipse(c + Vector2i(x, y), c, plaza_radius + Vector2(0.5, 0.5)):
				_paint_path(ground, decor, c + Vector2i(x, y))

	_place_object(decor, canopy, c + Vector2i(-1, -3), STATUE) # statue in the middle
	_place_object(decor, canopy, c + Vector2i(9, -1), WELL)
	# Market: a counter of crates between the two south houses, merchant stands behind it
	market_cell = c + Vector2i(-2, 7)
	_place_tiles(decor, market_cell, MARKET_CRATES)
	for x in range(-1, 6):
		for y in range(-2, 3):
			_blocked[market_cell + Vector2i(x, y)] = true # keep the area around it clear

	# Houses in random colours: three north of the plaza facing it, two south
	var colours := HOUSE_COLOURS.slice(1)
	var first := _rng.randi() % colours.size()
	var spots: Array[Vector2i] = [
		Vector2i(-11, -11), Vector2i(-3, -11), Vector2i(5, -11), Vector2i(-9, 6), Vector2i(3, 6),
	]
	for i in spots.size():
		_build_house(layers, c + spots[i], 4, colours[(first + i) % colours.size()])
		# A little path from the door down toward the plaza / road
		var door: Vector2i = houses.back()["door"]
		for n in range(1, 3):
			_paint_path(ground, decor, door + Vector2i(0, n))
	return c


func _make_roads(ground: TileMapLayer, decor: TileMapLayer, plaza: Vector2i) -> void:
	var home := home_spawn_cell()
	var lake := location_center("lake")
	var lake_radius: Vector2 = LOCATIONS["lake"]["radius"]
	var north := Vector2i(plaza.x + 13, int(_forest_edge(plaza.x + 13)) + 1)
	_carve_road(ground, decor, home, plaza + Vector2i(-7, 0)) # farm -> village
	_carve_road(ground, decor, plaza + Vector2i(6, 1), lake - Vector2i(0, int(lake_radius.y) - 1)) # village -> lake
	_carve_road(ground, decor, plaza + Vector2i(13, 1), north) # village -> forest
	_carve_road(ground, decor, home + Vector2i(0, 2), location_center("meadow")) # farm -> meadow


## A 2-tile-wide road that wanders from a to b.
func _carve_road(ground: TileMapLayer, decor: TileMapLayer, a: Vector2i, b: Vector2i) -> void:
	var p := a
	for step in 2000:
		for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			_paint_path(ground, decor, p + offset)
		if p == b:
			return
		var d := b - p
		# Step along x or y, more often along the longer distance, with a little wobble
		var along_x := _rng.randf() < float(absi(d.x)) / float(absi(d.x) + absi(d.y))
		if _rng.randf() < 0.12:
			along_x = not along_x
		if along_x:
			p.x += signi(d.x) if d.x != 0 else _rng.randi_range(-1, 1)
		else:
			p.y += signi(d.y) if d.y != 0 else _rng.randi_range(-1, 1)


func _make_pond(ground: TileMapLayer) -> void:
	for attempt in 40:
		var rx := _rng.randi_range(2, 4)
		var ry := _rng.randi_range(2, 3)
		var center := Vector2i(
			_rng.randi_range(rx + BORDER + 2, map_width - rx - BORDER - 3),
			_rng.randi_range(ry + BORDER + 2, map_height - ry - BORDER - 3))
		if location_at(center) != "":
			continue # only in the open countryside
		var cells: Array[Vector2i] = []
		var ok := true
		for x in range(-rx, rx + 1):
			for y in range(-ry, ry + 1):
				var d := pow(float(x) / rx, 2) + pow(float(y) / ry, 2)
				if d <= 1.0 + _rng.randf_range(-0.15, 0.15):
					var cell := center + Vector2i(x, y)
					if _near_blocked(cell, 2) or location_at(cell) != "":
						ok = false
					cells.append(cell)
		if ok:
			for cell in cells:
				ground.set_cell(cell, SOURCE_ID, WATER_TILES[_rng.randi() % WATER_TILES.size()])
				_blocked[cell] = true
			return


func _setup_collision(tile_set: TileSet) -> void:
	if tile_set == null:
		return
	if tile_set.get_physics_layers_count() == 0:
		tile_set.add_physics_layer()
	var source := tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	# Make sure every building tile exists in the atlas, so set_cell can use it
	for obj in _building_defs():
		for ox in obj["size"].x:
			for oy in obj["size"].y:
				var coords: Vector2i = obj["origin"] + Vector2i(ox, oy)
				if not source.has_tile(coords):
					source.create_tile(coords)
	var rects := COLLISION_RECTS.duplicate()
	rects.merge(FURNITURE_RECTS)
	for coords in rects:
		if not source.has_tile(coords):
			continue
		var data := source.get_tile_data(coords, 0)
		while data.get_collision_polygons_count(0) > 0:
			data.remove_collision_polygon(0, 0)
		# Polygon points are relative to the tile's center, so shift by -8
		var r: Rect2 = rects[coords]
		r.position -= Vector2(8, 8)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, PackedVector2Array([
			r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
		]))


func _building_defs() -> Array:
	return [WELL, STATUE, BED, RUG, MARKET_CRATES,
		{"origin": Vector2i(42, 33), "size": Vector2i(6, 2)}, # all shelves
	]


## Keeps the tile layers exactly on top of each other and locks them in the editor,
## so clicking on the map can't drag or stretch one of them by accident.
func _fix_layers() -> void:
	for layer_name in ["Ground", "Decor", "Canopy", "Roofs"]:
		var layer := get_node_or_null(layer_name) as Node2D
		if layer:
			layer.transform = Transform2D.IDENTITY
			layer.set_meta("_edit_lock_", true)


func _get_or_create_roofs(ground: TileMapLayer) -> TileMapLayer:
	var roofs := get_node_or_null("Roofs") as TileMapLayer
	if roofs == null:
		roofs = TileMapLayer.new()
		roofs.name = "Roofs"
		roofs.tile_set = ground.tile_set
		roofs.collision_enabled = false
		add_child(roofs)
		roofs.owner = self # saved with the scene
	var canopy := get_node_or_null("Canopy")
	if canopy:
		move_child(roofs, canopy.get_index() + 1) # roofs draw over everything
	return roofs


func _scatter_objects(decor: TileMapLayer, canopy: TileMapLayer) -> void:
	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)
			if _blocked.has(cell):
				continue
			var roll := _rng.randf()
			var edge := mini(mini(x, y), mini(map_width - 1 - x, map_height - 1 - y))
			if edge < BORDER:
				# Thick tree line along the map edge
				if roll < 0.6:
					_try_place_big(decor, canopy, cell, BIG_OBJECTS[_pick(PINES)], 0)
				continue
			match location_at(cell):
				"farm", "village":
					if roll < 0.01:
						_place_small(decor, cell, FLOWERS)
				"meadow":
					if roll < 0.025:
						_try_place_big(decor, canopy, cell, BIG_OBJECTS[_pick(FRUIT_BUSHES)], 1)
					elif roll < 0.2:
						_place_small(decor, cell, FLOWERS)
				"forest":
					if roll < 0.3:
						_try_place_big(decor, canopy, cell, BIG_OBJECTS[_pick(PINES)], 0)
					elif roll < 0.36:
						_place_small(decor, cell, FOREST_DECOR)
				_: # lake shore and open countryside
					if roll < tree_density:
						_try_place_big(decor, canopy, cell, _pick(BIG_OBJECTS), 1)
					elif roll < tree_density + decor_density:
						_place_small(decor, cell, SMALL_DECOR)


## Random element using the map's seed (so a fixed seed_value gives the same map).
func _pick(items: Array) -> Variant:
	return items[_rng.randi() % items.size()]


func _place_small(decor: TileMapLayer, cell: Vector2i, tiles: Array[Vector2i]) -> void:
	if not _near_blocked(cell, 0):
		decor.set_cell(cell, SOURCE_ID, tiles[_rng.randi() % tiles.size()])
		_blocked[cell] = true


## Places a multi-tile object if there's room (margin = free tiles kept around it).
func _try_place_big(decor: TileMapLayer, canopy: TileMapLayer, cell: Vector2i, obj: Dictionary, margin: int) -> void:
	var size: Vector2i = obj["size"]
	if cell.x + size.x > map_width or cell.y + size.y > map_height:
		return
	for ox in size.x:
		for oy in size.y:
			if _near_blocked(cell + Vector2i(ox, oy), margin):
				return
	_place_object(decor, canopy, cell, obj)


## Places a multi-tile object without checking for room.
func _place_object(decor: TileMapLayer, canopy: TileMapLayer, cell: Vector2i, obj: Dictionary) -> void:
	var size: Vector2i = obj["size"]
	var origin: Vector2i = obj["origin"]
	var solid_rows: int = obj.get("solid_rows", 1)
	for ox in size.x:
		for oy in size.y:
			var offset := Vector2i(ox, oy)
			# Bottom rows (trunk, walls) go on Decor, everything above on Canopy
			var layer: TileMapLayer = decor if oy >= size.y - solid_rows else canopy
			layer.set_cell(cell + offset, SOURCE_ID, origin + offset)
			_blocked[cell + offset] = true


func _near_blocked(cell: Vector2i, margin: int) -> bool:
	for x in range(-margin, margin + 1):
		for y in range(-margin, margin + 1):
			if _blocked.has(cell + Vector2i(x, y)):
				return true
	return false


# --- Gameplay ---------------------------------------------------------------

## Called by the player when swinging the axe. world_pos = the spot in front of the player.
func try_chop(world_pos: Vector2) -> ChopResult:
	var decor := get_node_or_null("Decor") as TileMapLayer
	var canopy := get_node_or_null("Canopy") as TileMapLayer
	if decor == null:
		return ChopResult.NOTHING
	if canopy == null:
		canopy = decor

	var center := decor.local_to_map(decor.to_local(world_pos))
	for dy in [0, -1, 1]:
		for dx in [0, -1, 1]:
			var cell: Vector2i = center + Vector2i(dx, dy)
			var atlas := decor.get_cell_atlas_coords(cell)
			for i in CHOPPABLE:
				var obj: Dictionary = BIG_OBJECTS[i]
				var origin: Vector2i = obj["origin"]
				var size: Vector2i = obj["size"]
				var offset := atlas - origin
				# Only the trunk (bottom row) of a pine counts as a hit
				if offset.y != size.y - 1 or offset.x < 0 or offset.x >= size.x:
					continue
				var tree_cell := cell - offset
				_tree_hits[tree_cell] = _tree_hits.get(tree_cell, 0) + 1
				if _tree_hits[tree_cell] < HITS_TO_CHOP:
					_shake_tree(decor, canopy, tree_cell, i)
					return ChopResult.HIT
				_tree_hits.erase(tree_cell)
				for ox in size.x:
					for oy in size.y:
						var c := tree_cell + Vector2i(ox, oy)
						decor.erase_cell(c)
						canopy.erase_cell(c)
				decor.set_cell(tree_cell + Vector2i(0, size.y - 1), SOURCE_ID, STUMP)
				return ChopResult.FELLED
	return ChopResult.NOTHING


## Plays a shake on a tree that was hit. Tiles can't move, so the tree's tiles are
## swapped for a sprite while it shakes, then put back.
func _shake_tree(decor: TileMapLayer, canopy: TileMapLayer, tree_cell: Vector2i, index: int) -> void:
	var obj: Dictionary = BIG_OBJECTS[index]
	var size: Vector2i = obj["size"]
	var origin: Vector2i = obj["origin"]
	var top_left := decor.map_to_local(tree_cell) - Vector2(8, 8) # tree's top-left pixel
	var shaker: Node2D
	var duration := 0.5
	if origin == BIG_OBJECTS[4]["origin"]:
		# Tall pine: the real animation from the pack, wiggling back and forth
		var strip: Texture2D = load(PINE_SHAKE)
		var frames := SpriteFrames.new()
		frames.set_animation_loop("default", false)
		frames.set_animation_speed("default", 14.0)
		for f in [1, 2, 3, 2, 1, 2, 3, 0]:
			var atlas := AtlasTexture.new()
			atlas.atlas = strip
			atlas.region = Rect2(f * 28, 0, 28, strip.get_height())
			frames.add_frame("default", atlas)
		var anim := AnimatedSprite2D.new()
		anim.sprite_frames = frames
		anim.centered = false
		anim.position = top_left + PINE_SHAKE_OFFSET
		anim.play()
		shaker = anim
		duration = frames.get_frame_count("default") / 14.0
	else:
		# Small pine: no animation in the pack, so lean it left and right from the trunk
		var sprite := Sprite2D.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = decor.tile_set.get_source(SOURCE_ID).texture
		atlas.region = Rect2(Vector2(origin * 16), Vector2(size * 16))
		sprite.texture = atlas
		sprite.centered = false
		sprite.offset = Vector2(-size.x * 8, -size.y * 16) # pivot at the bottom middle
		shaker = Node2D.new()
		shaker.add_child(sprite)
		shaker.position = top_left + Vector2(size.x * 8, size.y * 16)
		var tween := shaker.create_tween()
		for lean in [0.12, -0.1, 0.06, -0.03, 0.0]:
			tween.tween_property(shaker, "skew", lean, duration / 5.0)

	# Hide the tiles, show the shaking tree in the same place (above the player, like tree tops)
	var saved := {}
	for ox in size.x:
		for oy in size.y:
			var c := tree_cell + Vector2i(ox, oy)
			var layer: TileMapLayer = decor if oy == size.y - 1 else canopy
			saved[c] = [layer, layer.get_cell_atlas_coords(c)]
			layer.erase_cell(c)
	shaker.position = to_local(decor.to_global(shaker.position))
	add_child(shaker)
	move_child(shaker, canopy.get_index() + 1 if canopy != decor else get_child_count() - 1)
	await get_tree().create_timer(duration).timeout
	for c in saved:
		# Put the tiles back (unless the tree was cut down in the meantime)
		if saved[c][0].get_cell_source_id(c) == -1:
			saved[c][0].set_cell(c, SOURCE_ID, saved[c][1])
	shaker.queue_free()


## Called by the player's sword. Removes small decor on that tile; true if something was cut.
func try_cut(world_pos: Vector2) -> bool:
	var decor := get_node_or_null("Decor") as TileMapLayer
	if decor == null:
		return false
	var cell := decor.local_to_map(decor.to_local(world_pos))
	if not CUTTABLE.has(decor.get_cell_atlas_coords(cell)):
		return false
	decor.erase_cell(cell)
	return true


## True if the hoe can turn this tile into soil: plain grass with nothing on it.
func is_farmable(cell: Vector2i) -> bool:
	var ground := get_node_or_null("Ground") as TileMapLayer
	var decor := get_node_or_null("Decor") as TileMapLayer
	var canopy := get_node_or_null("Canopy") as TileMapLayer
	if ground == null:
		return false
	var tile := ground.get_cell_atlas_coords(cell)
	if tile != GRASS and not GRASS_VARIANTS.has(tile):
		return false
	if decor and decor.get_cell_source_id(cell) != -1:
		return false
	if canopy and canopy.get_cell_source_id(cell) != -1:
		return false
	return true


## Location display name at a world position ("" in the open countryside).
func location_name_at(world_pos: Vector2) -> String:
	var ground := get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return ""
	return location_name(location_at(ground.local_to_map(ground.to_local(world_pos))))


## At game start: gives every house its own roof layer (so only that roof fades)
## and invisible walls with a gap at the door.
func _setup_houses() -> void:
	var shared := get_node_or_null("Roofs") as TileMapLayer
	if shared == null:
		return
	var tile := Vector2(shared.tile_set.tile_size)
	var walls := StaticBody2D.new()
	walls.name = "HouseWalls"
	add_child(walls)
	for house in houses:
		var rect: Rect2i = house["rect"]
		var roof := TileMapLayer.new()
		roof.tile_set = shared.tile_set
		roof.collision_enabled = false
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var c := Vector2i(x, y)
				if shared.get_cell_source_id(c) != -1:
					roof.set_cell(c, SOURCE_ID, shared.get_cell_atlas_coords(c))
					shared.erase_cell(c)
		add_child(roof)
		move_child(roof, shared.get_index() + 1)
		_roofs.append(roof)

		# Walls in world pixels: left/right posts, back wall, front wall on both sides of the door
		var left := rect.position.x * tile.x
		var right := rect.end.x * tile.x
		var top := rect.position.y * tile.y
		var front := (rect.end.y - 1) * tile.y
		var door_left: float = house["door"].x * tile.x
		for r in [
			Rect2(left + 8, top + 8, 8, front - top), # left post
			Rect2(right - 16, top + 8, 8, front - top), # right post
			Rect2(left, top, right - left, tile.y * 2 - 4), # back wall
			Rect2(left + 8, front, door_left - left - 8, 12), # front wall, left of the door
			Rect2(door_left + tile.x, front, right - door_left - tile.x - 8, 12), # right of the door
		]:
			var shape := RectangleShape2D.new()
			shape.size = r.size
			var collision := CollisionShape2D.new()
			collision.shape = shape
			collision.position = r.get_center()
			walls.add_child(collision)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _roofs.is_empty():
		return
	var player := get_node_or_null("Player") as Node2D
	var ground := get_node_or_null("Ground") as TileMapLayer
	if player == null or ground == null:
		return
	var cell := ground.local_to_map(ground.to_local(player.global_position))
	for i in _roofs.size():
		var rect: Rect2i = houses[i]["rect"]
		# Inside = in the room (between the posts, below the roof's top edge, above the front wall)
		var room := Rect2i(rect.position + Vector2i(1, 1), rect.size - Vector2i(2, 1))
		var target := 0.0 if room.has_point(cell) else 1.0
		_roofs[i].modulate.a = move_toward(_roofs[i].modulate.a, target, delta * 4.0)


## World position of a tile's center.
func cell_to_world(cell: Vector2i) -> Vector2:
	var ground := get_node("Ground") as TileMapLayer
	return ground.to_global(ground.map_to_local(cell))


## True if there's water (lake or pond) at world_pos. Used for fishing.
func is_water(world_pos: Vector2) -> bool:
	var ground := get_node("Ground") as TileMapLayer
	return WATER_TILES.has(ground.get_cell_atlas_coords(ground.local_to_map(ground.to_local(world_pos))))


## True if world_pos is next to the bed in your home (where you can sleep).
func is_near_bed(world_pos: Vector2) -> bool:
	if houses.is_empty():
		return false
	var bed := Rect2i(houses[0]["rect"].position + Vector2i(1, 1), Vector2i(2, 2)).grow(1)
	var ground := get_node("Ground") as TileMapLayer
	return bed.has_point(ground.local_to_map(ground.to_local(world_pos)))


## Where you wake up in the morning: next to your bed.
func bed_side_position() -> Vector2:
	return cell_to_world(houses[0]["rect"].position + Vector2i(3, 2))


## True if world_pos is close enough to the market counter to trade.
func is_near_market(world_pos: Vector2) -> bool:
	if market_cell.x < 0:
		return false
	var center := cell_to_world(market_cell + Vector2i(2, 0)) + Vector2(0, 8)
	return world_pos.distance_to(center) < 48.0


func _spawn_clock() -> void:
	var clock := Node.new()
	clock.set_script(load("res://scripts/day_night.gd"))
	clock.name = "DayNight"
	add_child(clock)
	var farm := get_node_or_null("Farm")
	if farm:
		clock.new_day.connect(farm.on_new_day)
	var player := get_node_or_null("Player")
	if player and player.has_method("on_passed_out"):
		clock.passed_out.connect(player.on_passed_out)


func _spawn_merchant() -> void:
	if market_cell.x < 0:
		return
	var merchant := StaticBody2D.new()
	merchant.set_script(load("res://scripts/villager.gd"))
	merchant.name = "Merchant"
	merchant.set("hair", "curlyhair")
	merchant.set("display_name", "Merchant")
	merchant.position = to_local(cell_to_world(market_cell + Vector2i(2, -1)) + Vector2(0, -2))
	add_child(merchant)
	var player := get_node_or_null("Player")
	if player:
		move_child(merchant, player.get_index())


## Characters from story_text.gd, standing in their locations.
func _spawn_story_characters() -> void:
	var characters: Dictionary = load("res://scripts/story/story_text.gd").NPCS
	var player := get_node_or_null("Player")
	for id in characters:
		var info: Dictionary = characters[id]
		var npc := StaticBody2D.new()
		npc.set_script(load("res://scripts/villager.gd"))
		npc.name = info["name"]
		npc.set("npc_id", id)
		npc.set("hair", info["hair"])
		npc.set("display_name", info["name"])
		npc.position = to_local(cell_to_world(location_center(info["place"]) + info["offset"]))
		add_child(npc)
		if player:
			move_child(npc, player.get_index())


func _spawn_farm() -> void:
	var farm := Node2D.new()
	farm.set_script(load("res://scripts/farm.gd"))
	farm.name = "Farm"
	add_child(farm)
	var player := get_node_or_null("Player")
	if player:
		move_child(farm, player.get_index()) # soil and crops draw under the player


## The map's area in world pixels.
func _world_rect() -> Rect2:
	var ground := get_node("Ground") as TileMapLayer
	var used := ground.get_used_rect()
	var tile := Vector2(ground.tile_set.tile_size)
	var top_left := ground.to_global(Vector2(used.position) * tile)
	var bottom_right := ground.to_global(Vector2(used.end) * tile)
	return Rect2(top_left, bottom_right - top_left)


## Invisible walls around the map so nobody walks off the edge.
func _setup_world_bounds() -> void:
	var rect := _world_rect()
	var walls := StaticBody2D.new()
	walls.name = "WorldBounds"
	var t := 32.0 # wall thickness
	for r in [
		Rect2(rect.position.x - t, rect.position.y - t, rect.size.x + 2 * t, t), # top
		Rect2(rect.position.x - t, rect.end.y, rect.size.x + 2 * t, t), # bottom
		Rect2(rect.position.x - t, rect.position.y, t, rect.size.y), # left
		Rect2(rect.end.x, rect.position.y, t, rect.size.y), # right
	]:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = r.get_center()
		walls.add_child(collision)
	add_child(walls)


func _place_player() -> void:
	var player := get_node_or_null("Player") as Node2D
	var ground := get_node_or_null("Ground") as TileMapLayer
	if player == null or ground == null:
		return
	player.global_position = ground.to_global(ground.map_to_local(home_spawn_cell()))
	if player.has_method("set_camera_limits"):
		player.set_camera_limits(_world_rect())


func _spawn_goblins() -> void:
	var ground := get_node_or_null("Ground") as TileMapLayer
	var decor := get_node_or_null("Decor") as TileMapLayer
	var canopy := get_node_or_null("Canopy") as TileMapLayer
	var player := get_node_or_null("Player") as Node2D
	if ground == null or decor == null:
		return
	var goblin_script := load("res://scripts/goblin.gd")
	var area := ground.get_used_rect()
	var spawned := 0
	for attempt in 2000:
		if spawned >= goblin_count:
			break
		var cell := Vector2i(
			randi_range(area.position.x + 1, area.end.x - 2),
			randi_range(area.position.y + 1, area.end.y - 2))
		if location_at(cell) != "forest":
			continue # goblins only live in the forest
		var ground_tile := ground.get_cell_atlas_coords(cell)
		if WATER_TILES.has(ground_tile) or ground_tile == Vector2i(-1, -1):
			continue
		if decor.get_cell_source_id(cell) != -1:
			continue
		if canopy and canopy.get_cell_source_id(cell) != -1:
			continue
		var pos := ground.to_global(ground.map_to_local(cell))
		if player and pos.distance_to(player.global_position) < 150.0:
			continue # don't spawn right next to the player
		var goblin := CharacterBody2D.new()
		goblin.set_script(goblin_script)
		goblin.name = "Goblin%d" % (spawned + 1)
		goblin.position = to_local(pos)
		add_child(goblin)
		if canopy:
			move_child(goblin, canopy.get_index()) # draw goblins under the tree tops
		spawned += 1
