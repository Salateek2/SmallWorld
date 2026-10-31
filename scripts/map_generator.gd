@tool
extends Node2D
## SmallWorld map generator.
## Select the Main node and press "Generate Map" in the Inspector.
## The result is a normal tilemap, so you can fix anything by hand afterwards.
## Needs TileMapLayer children named Ground, Decor and (optional) Canopy.
## Canopy should be below Player in the Scene panel so tree tops draw over the player.
## "Shore" and "ShoreSides" layers (water edges, the dock) and a "Roofs" layer (house roofs,
## which fade out when you walk inside) are added automatically.
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
const WATER_TILES: Array[Vector2i] = [Vector2i(4, 1)] # plain water; details go on the Shore layer
# Shore pieces drawn over the water's edge. Each side looks different, like in the pack's art:
# the top edge has foam under a brown earth face (the land drops down to the water),
# the left/right edges are a straight line, the bottom edge is a darker line.
# Top/bottom go on the Shore layer, left/right on ShoreSides, so a corner gets both = square.
const SHORE_N: Array[Vector2i] = [Vector2i(20, 2), Vector2i(23, 2)]
const SHORE_S: Array[Vector2i] = [Vector2i(20, 4), Vector2i(23, 4)]
const SHORE_W := Vector2i(22, 3)
const SHORE_E := Vector2i(21, 3)
const WATER_FLECKS: Array[Vector2i] = [Vector2i(20, 3), Vector2i(23, 3)] # ripples in open water
const EARTH_FACE := Vector2i(11, 4) # the brown drop between grass and water on north shores
# Wooden fence (horizontal run) and dock
const FENCE_LEFT := Vector2i(38, 2)
const FENCE_MIDDLE := Vector2i(39, 2)
const FENCE_RIGHT := Vector2i(42, 2)
# Fence corners and sides for the animal pen
const FENCE_TOP_LEFT := Vector2i(42, 1)
const FENCE_TOP_RIGHT := Vector2i(41, 1)
const FENCE_BOTTOM_LEFT := Vector2i(39, 1)
const FENCE_BOTTOM_RIGHT := Vector2i(38, 1)
const FENCE_SIDE := Vector2i(40, 3)
const PEN_SIZE := Vector2i(10, 7) # tiles, fence included
const TROUGH := {"origin": Vector2i(37, 17), "size": Vector2i(2, 1)}
# The smithy's work yard
const ANVIL := {"origin": Vector2i(37, 18), "size": Vector2i(2, 1)}
const FORGE := {"origin": Vector2i(39, 17), "size": Vector2i(2, 2)} # furnace + stone chimney
const BARREL_OPEN := Vector2i(40, 16)
const BARREL_WATER := Vector2i(38, 16)
const FORGE_FIRE := "res://assets/Sunnyside_World_Assets/Elements/VFX/Fire/spr_deco_fire_02_strip4.png"
const DOCK_PLANK := Vector2i(40, 5)
const DOCK_END := Vector2i(40, 6)
const DOCK_POST_LEFT := Vector2i(39, 5)
const DOCK_POST_RIGHT := Vector2i(41, 5)
const DOCK_LENGTH := 4 # planks out over the water

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
const ROOF_CHIMNEY := Vector2i(28, 9) # roof tile with a chimney opening
const CHIMNEY_SMOKE := "res://assets/Sunnyside_World_Assets/Elements/VFX/Chimney Smoke/chimneysmoke_01_strip30.png"
const SMOKE_FRAME_WIDTH := 15
## Village houses with a smoking chimney (your house always has one)
const CHIMNEY_CHANCE := 0.6
const WALL_WINDOW := Vector2i(16, 14) # front wall with a window
const DOOR := Vector2i(16, 15)
const FLOOR := Vector2i(10, 10) # wooden floor inside
const BACK_WALL := Vector2i(10, 9)
# Furniture: top-left tile and size
const BED := {"origin": Vector2i(40, 33), "size": Vector2i(2, 2)} # side view, headboard on the left
const SHELVES: Array[Vector2i] = [ # 1x2 bookcases, cupboards, wardrobe, dresser
	Vector2i(42, 33), Vector2i(43, 33), Vector2i(44, 33), Vector2i(45, 33), Vector2i(46, 33), Vector2i(47, 33),
]
const RUG := {"origin": Vector2i(43, 35), "size": Vector2i(3, 2)}
const JARS: Array[Vector2i] = [Vector2i(46, 32), Vector2i(47, 32), Vector2i(48, 32), Vector2i(51, 32)]

const WELL := {"origin": Vector2i(37, 19), "size": Vector2i(2, 2)}
# Market stall: open produce crates (Elements/Crops/crate_base.png) filled with crops
const MARKET_CRATE := "res://assets/Sunnyside_World_Assets/Elements/Crops/crate_base.png"
const MARKET_PRODUCE: Array[String] = ["pumpkin", "carrot", "cabbage"]
const STATUE := {"origin": Vector2i(44, 18), "size": Vector2i(2, 4), "solid_rows": 2}

# Raised ground (plateaus): grass edge lines around the top, a 2-tile brown cliff face
# below the front (south) edge with shaded ends, darker grass at its foot, and ramps
# (darker grassy slopes) cut into the cliff to walk up and down.
const CLIFF_SHADOW := Vector2i(0, 3) # grass at the foot of a cliff
# The rocky cliff face is our own tile sheet (assets/cliffs/cliffs.png, drawn by
# tools/make_cliff_tiles.py), added to the TileSet as a second source. Each piece is
# 2 tiles tall: atlas row 0 = upper half (with the grass lip), row 1 = lower half.
const CLIFF_SOURCE := 1
const CLIFF_SHEET := "res://assets/cliffs/cliffs.png"
const CLIFF_VARIANTS := 4 # columns 0-3, they join seamlessly in order (x % 4)
const CLIFF_LEFT_END := 4
const CLIFF_RIGHT_END := 5
const CLIFF_LADDER := 6
# Edges of a plateau's top, one piece per direction (in the same sheet)
const CLIFF_BACK_LEFT := Vector2i(7, 0)
const CLIFF_BACK := Vector2i(8, 0)
const CLIFF_BACK_RIGHT := Vector2i(9, 0)
const CLIFF_SIDE_LEFT := Vector2i(7, 1)
const CLIFF_SIDE_RIGHT := Vector2i(9, 1)
# Path edges: see-through pieces laid over every path tile so the grass creeps in with a
# wobbly, rounded edge (assets/paths/paths.png, drawn by tools/make_path_tiles.py).
# Column = sides with grass (1 N, 2 E, 4 S, 8 W), row = corners with grass (1 NE, 2 SE,
# 4 SW, 8 NW); row 16 has pebbles.
const PATH_SOURCE := 2
const PATH_SHEET := "res://assets/paths/paths.png"
const PEBBLE_CHANCE := 0.14
const HILL_COUNT := 4 # little hills scattered around the countryside

## Named places: center as a fraction of the map size, radius in tiles.
## The forest is the band along the top of the map instead (see _forest_edge).
const LOCATIONS := {
	"farm": {"name": "Your Farm", "center": Vector2(0.30, 0.56), "radius": Vector2(13, 10)},
	"village": {"name": "Willowbrook Village", "center": Vector2(0.64, 0.47), "radius": Vector2(24, 17)},
	"lake": {"name": "Mirror Lake", "center": Vector2(0.80, 0.80), "radius": Vector2(17, 10)},
	"meadow": {"name": "Sunny Meadow", "center": Vector2(0.13, 0.82), "radius": Vector2(13, 9)},
}
const FOREST_NAME := "Pinewood Forest"

# Solid areas per tile, in tile pixels (x, y, width, height) from the tile's top-left.
# Trees and bushes are only solid at the trunk/bottom, so you can walk behind them.
const COLLISION_RECTS := {
	Vector2i(38, 2): Rect2(4, 8, 12, 5), Vector2i(39, 2): Rect2(0, 8, 16, 5), # fence
	Vector2i(42, 2): Rect2(0, 8, 12, 5),
	Vector2i(42, 1): Rect2(5, 8, 11, 8), Vector2i(41, 1): Rect2(0, 8, 11, 8), # pen corners
	Vector2i(39, 1): Rect2(5, 0, 11, 13), Vector2i(38, 1): Rect2(0, 0, 11, 13),
	Vector2i(40, 3): Rect2(5, 0, 6, 16), # pen sides
	Vector2i(37, 17): Rect2(4, 2, 12, 12), Vector2i(38, 17): Rect2(0, 2, 12, 12), # trough
	Vector2i(37, 18): Rect2(5, 2, 11, 9), Vector2i(38, 18): Rect2(0, 2, 10, 9), # anvil
	Vector2i(39, 18): Rect2(3, 0, 13, 14), Vector2i(40, 18): Rect2(0, 0, 11, 14), # forge
	Vector2i(38, 16): Rect2(3, 4, 10, 10), Vector2i(40, 16): Rect2(3, 4, 10, 10), # barrels
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
	Vector2i(40, 34): Rect2(0, 0, 16, 12), Vector2i(41, 34): Rect2(0, 0, 3, 12),
	Vector2i(42, 34): Rect2(0, 0, 16, 10), Vector2i(43, 34): Rect2(0, 0, 16, 10),
	Vector2i(44, 34): Rect2(0, 0, 16, 10), Vector2i(45, 34): Rect2(0, 0, 16, 10),
	Vector2i(46, 34): Rect2(0, 0, 13, 10), Vector2i(47, 34): Rect2(0, 0, 16, 10),
}

enum ChopResult { NOTHING, HIT, FELLED }
const CHOPPABLE := PINES
const STUMP := Vector2i(31, 5)
const HITS_TO_CHOP := 3
const WOOD_DROPS := 3 # pieces of wood that pop out of a felled tree
const WOOD_ICON := "res://assets/Sunnyside_World_Assets/Elements/Crops/wood.png"
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
var _changes: Array = [] # trees felled and plants cut this game (saved, replayed on load)

## Houses on the map: footprint rect and door cell (saved with the scene by Generate Map).
## The first one is your home.
@export_storage var houses: Array[Dictionary] = []
## Top-left tile of the market counter in the village
@export_storage var market_cell := Vector2i(-1, -1)
## The lake dock's tiles (you walk on it instead of swimming)
@export_storage var dock_cells := Rect2i()
## The animal pen next to your house (fence included) and its trough
@export_storage var pen_rect := Rect2i()
@export_storage var trough_cell := Vector2i()
## The smithy's furnace (its fire and chimney smoke are added when the game starts)
@export_storage var forge_cell := Vector2i(-1, -1)
## Raised ground: one rectangle per plateau (the village's upper level, hills)
@export_storage var plateaus: Array[Rect2i] = []
## Ramps: the columns of a cliff you can walk through, as rectangles over the cliff face
@export_storage var ramps: Array[Rect2i] = []

var _rng := RandomNumberGenerator.new()
var _blocked := {} # cells that already have a path, water or object
var _source: TileSetAtlasSource
var _roofs: Array[TileMapLayer] = [] # one per house at runtime, faded when you're inside


func _ready() -> void:
	_fix_layers()
	if Engine.is_editor_hint():
		return
	_add_forge_fire()
	_setup_houses()
	_setup_cliff_walls()
	_add_water_effects()
	_spawn_farm()
	_spawn_ranch()
	_spawn_clock()
	_spawn_merchant()
	_spawn_story_characters()
	_setup_world_bounds()
	_place_player()
	_spawn_goblins()
	if SaveGame.load_requested:
		SaveGame.apply(self) # "Continue" on the title screen


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
	var shore := _get_or_create_shore(ground, "Shore", 1)
	var sides := _get_or_create_shore(ground, "ShoreSides", 2)
	_fix_layers()

	_source = ground.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	_setup_cliff_source(ground.tile_set)
	_setup_path_source(ground.tile_set)
	for layer in [ground, decor]:
		_setup_collision(layer.tile_set)

	clear()
	houses.clear()
	_fill_grass(ground)
	var layers := {"ground": ground, "decor": decor, "canopy": canopy, "roofs": roofs, "shore": shore}
	_make_home(layers)
	_make_pen(decor)
	_make_lake(ground)
	plateaus.clear()
	ramps.clear()
	var plaza := _make_village(layers)
	_make_roads(ground, decor, plaza)
	_connect_doors(ground, decor)
	for i in pond_count:
		_make_pond(ground)
	_make_hills(ground, shore)
	_decorate_water(ground, shore, sides)
	var dock := _make_dock(ground, shore, decor)
	_make_lake_fence(ground, shore, decor, dock)
	_scatter_objects(decor, canopy)
	_decorate_paths(ground, shore, sides)
	print("SmallWorld map generated (seed %d)" % _rng.seed)


func clear() -> void:
	_blocked.clear()
	for layer_name in ["Ground", "Shore", "ShoreSides", "Decor", "Canopy", "Roofs"]:
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
	for house in houses:
		if house["rect"].has_point(cell):
			return # never through a house (its floor isn't on Decor)
	if pen_rect.has_point(cell):
		return # or the animal pen
	if _is_cliff(cell):
		return # roads don't run up cliff faces (ramps are fine)
	ground.set_cell(cell, SOURCE_ID, PATH_TILES[_rng.randi() % PATH_TILES.size()])
	_blocked[cell] = true


## A fenced pen for animals left of your house, gate at the bottom, trough inside.
func _make_pen(decor: TileMapLayer) -> void:
	var home: Rect2i = houses[0]["rect"]
	pen_rect = Rect2i(home.position + Vector2i(-PEN_SIZE.x - 2, 0), PEN_SIZE)
	var gate := [PEN_SIZE.x / 2 - 1, PEN_SIZE.x / 2]
	for x in PEN_SIZE.x:
		for y in PEN_SIZE.y:
			var cell := pen_rect.position + Vector2i(x, y)
			_blocked[cell] = true # nothing grows inside
			var last_x := x == PEN_SIZE.x - 1
			var last_y := y == PEN_SIZE.y - 1
			var piece := Vector2i(-1, -1)
			if y == 0:
				piece = FENCE_TOP_LEFT if x == 0 else (FENCE_TOP_RIGHT if last_x else FENCE_MIDDLE)
			elif last_y:
				if x == 0: piece = FENCE_BOTTOM_LEFT
				elif last_x: piece = FENCE_BOTTOM_RIGHT
				elif gate.has(x): continue # opening to walk in
				elif gate.has(x + 1): piece = FENCE_RIGHT # end posts either side of the gate
				elif gate.has(x - 1): piece = FENCE_LEFT
				else: piece = FENCE_MIDDLE
			elif x == 0 or last_x:
				piece = FENCE_SIDE
			if piece.x >= 0:
				_set_tile(decor, cell, piece)
	trough_cell = pen_rect.position + Vector2i(2, 1)
	_place_tiles(decor, trough_cell, TROUGH)


func _make_home(layers: Dictionary) -> void:
	# Your blue house at the top of the farm clearing, door facing the field
	var door := home_spawn_cell() + Vector2i(0, -2)
	_build_house(layers, door - Vector2i(3, HOUSE_HEIGHT - 1), 5, HOUSE_COLOURS[0], true)


## Builds a house with its top-left corner at `cell`. inner = width of the room in tiles.
## Layers: floor/back wall on Ground, furniture and front wall on Decor (under the player),
## side posts on Canopy (over the player), roof on Roofs (over the player, fades when inside).
func _build_house(layers: Dictionary, cell: Vector2i, inner: int, colour: int, chimney := false) -> void:
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

	var house := {
		"rect": Rect2i(cell, Vector2i(width, HOUSE_HEIGHT)),
		"door": cell + Vector2i(door_x, HOUSE_HEIGHT - 1),
	}
	if chimney:
		# Top shingle row, right side of the roof
		var chimney_cell := cell + Vector2i(width - 2, 1)
		_set_tile(roofs, chimney_cell, ROOF_CHIMNEY + shade)
		house["chimney"] = chimney_cell
	houses.append(house)


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
	# Blocky, like the ponds in the art pack: a wide middle and two lobes, all rectangles
	var c := location_center("lake")
	var r := Vector2i(LOCATIONS["lake"]["radius"]) - Vector2i(3, 2) # leave a grassy shore
	var rects: Array[Rect2i] = [
		Rect2i(c - Vector2i(r.x, r.y / 2), Vector2i(r.x * 2, r.y)),
		Rect2i(c + Vector2i(_rng.randi_range(-r.x, -2), -r.y), Vector2i(_rng.randi_range(r.x / 2 + 2, r.x), r.y)),
		Rect2i(c + Vector2i(_rng.randi_range(-r.x / 2, r.x / 4), 0), Vector2i(_rng.randi_range(r.x / 2, r.x), r.y)),
	]
	_fill_water(ground, rects)


func _fill_water(ground: TileMapLayer, rects: Array[Rect2i]) -> void:
	for rect in rects:
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var cell := Vector2i(x, y)
				if cell.x >= BORDER and cell.x < map_width - BORDER and cell.y >= BORDER and cell.y < map_height - BORDER:
					ground.set_cell(cell, SOURCE_ID, WATER_TILES[0])
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
	# Market between the two south houses: crates of produce, merchant behind them
	# (the stall itself is made of sprites in _spawn_merchant)
	market_cell = c + Vector2i(-2, 7)
	for x in range(-1, 6):
		for y in range(-2, 3):
			_blocked[market_cell + Vector2i(x, y)] = true # keep the area around it clear

	# Upper Willowbrook: a plateau behind the plaza, its cliff just above the plaza,
	# with a ramp in the middle down to the plaza
	var upper := Rect2i(c + Vector2i(-21, -18), Vector2i(43, 11)) # front edge on row c.y - 8
	var ramp := Rect2i(c.x - 1, upper.end.y, 2, 2)
	_add_plateau(ground, layers["shore"], upper, [ramp])
	# Its street runs along the front edge; the ramp carries it down to the plaza
	for x in range(-19, 20):
		for y in [-9, -8]:
			_paint_path(ground, decor, c + Vector2i(x, y))
	for x in range(ramp.position.x, ramp.end.x):
		_paint_path(ground, decor, Vector2i(x, ramp.end.y)) # the foot of the ramp joins the plaza

	# Houses in random colours: five up on the plateau along its street, two below the plaza
	var colours := HOUSE_COLOURS.slice(1)
	var first := _rng.randi() % colours.size()
	var spots: Array[Vector2i] = [
		Vector2i(-20, -15), Vector2i(-12, -15), Vector2i(-4, -15), Vector2i(4, -15), Vector2i(12, -15),
		Vector2i(-9, 6), Vector2i(3, 6),
	]
	for i in spots.size():
		_build_house(layers, c + spots[i], 4, colours[(first + i) % colours.size()], _rng.randf() < CHIMNEY_CHANCE)
	_make_smithy(layers, c + Vector2i(-22, 4))
	return c


## Gus's smithy: his house, and beside it a dirt work yard with the forge against the
## house wall, an anvil (Gus hammers at it), the trough and a couple of barrels.
func _make_smithy(layers: Dictionary, house_corner: Vector2i) -> void:
	var ground: TileMapLayer = layers["ground"]
	var decor: TileMapLayer = layers["decor"]
	_build_house(layers, house_corner, 4, HOUSE_COLOURS[3], false) # red roof
	var yard := Rect2i(house_corner + Vector2i(6, 1), Vector2i(7, 6))
	for x in range(yard.position.x, yard.end.x):
		for y in range(yard.position.y, yard.end.y):
			_paint_path(ground, decor, Vector2i(x, y))
	_place_tiles(decor, yard.position, FORGE)
	forge_cell = yard.position + Vector2i(0, 1)
	_place_tiles(decor, yard.position + Vector2i(3, 0), TROUGH)
	_place_tiles(decor, yard.position + Vector2i(2, 3), ANVIL)
	_set_tile(decor, yard.position + Vector2i(6, 1), BARREL_OPEN)
	_set_tile(decor, yard.position + Vector2i(6, 3), BARREL_WATER)


# --- Levels: plateaus, cliffs and ramps ----------------------------------------

## True if the tile is on raised ground.
func is_high(cell: Vector2i) -> bool:
	for rect in plateaus:
		if rect.has_point(cell):
			return true
	return false


## True for the two cliff rows below a plateau's front edge (not counting ramps).
func _is_cliff(cell: Vector2i) -> bool:
	if is_high(cell):
		return false
	if not (is_high(cell + Vector2i(0, -1)) or (is_high(cell + Vector2i(0, -2)) and not is_high(cell + Vector2i(0, -1)))):
		return false
	for ramp in ramps:
		if ramp.has_point(cell):
			return false
	return true


## Raises a rectangle of ground and draws its edges, cliff face and ramps on the Ground layer.
## Adds the cliff tile sheet to the TileSet (once) as source CLIFF_SOURCE.
func _setup_cliff_source(tile_set: TileSet) -> void:
	var cliffs: TileSetAtlasSource
	if tile_set.has_source(CLIFF_SOURCE):
		cliffs = tile_set.get_source(CLIFF_SOURCE)
	else:
		cliffs = TileSetAtlasSource.new()
		cliffs.texture = load(CLIFF_SHEET)
		cliffs.texture_region_size = Vector2i(16, 16)
		tile_set.add_source(cliffs, CLIFF_SOURCE)
	# The sheet may have grown since: make sure every piece exists
	for x in cliffs.texture.get_width() / 16:
		for y in 2:
			if not cliffs.has_tile(Vector2i(x, y)):
				cliffs.create_tile(Vector2i(x, y))


## Adds the path edge sheet to the TileSet (once) as source PATH_SOURCE.
func _setup_path_source(tile_set: TileSet) -> void:
	var paths: TileSetAtlasSource
	if tile_set.has_source(PATH_SOURCE):
		paths = tile_set.get_source(PATH_SOURCE)
	else:
		paths = TileSetAtlasSource.new()
		paths.texture = load(PATH_SHEET)
		paths.texture_region_size = Vector2i(16, 16)
		tile_set.add_source(paths, PATH_SOURCE)
	for x in paths.texture.get_width() / 16:
		for y in paths.texture.get_height() / 16:
			if not paths.has_tile(Vector2i(x, y)):
				paths.create_tile(Vector2i(x, y))


## Soft edges for every path: each path tile gets the edge piece that matches where
## the grass is around it, and some get a few pebbles.
func _decorate_paths(ground: TileMapLayer, edges_layer: TileMapLayer, pebbles_layer: TileMapLayer) -> void:
	var is_path := func(c: Vector2i) -> bool:
		return ground.get_cell_source_id(c) == SOURCE_ID and PATH_TILES.has(ground.get_cell_atlas_coords(c))
	# Grass creeps in only from plain grass (not from cliffs, water, houses or the dock)
	var is_grass := func(c: Vector2i) -> bool:
		if is_path.call(c) or edges_layer.get_cell_source_id(c) != -1:
			return false
		var tile := ground.get_cell_atlas_coords(c)
		return tile == GRASS or GRASS_VARIANTS.has(tile) or tile == CLIFF_SHADOW
	for cell in ground.get_used_cells():
		if not is_path.call(cell) or edges_layer.get_cell_source_id(cell) != -1:
			continue
		var sides := 0
		for bit_dir in [[1, Vector2i(0, -1)], [2, Vector2i(1, 0)], [4, Vector2i(0, 1)], [8, Vector2i(-1, 0)]]:
			if is_grass.call(cell + bit_dir[1]):
				sides |= bit_dir[0]
		var corners := 0
		for bit_dir in [[1, Vector2i(1, -1)], [2, Vector2i(1, 1)], [4, Vector2i(-1, 1)], [8, Vector2i(-1, -1)]]:
			if is_grass.call(cell + bit_dir[1]):
				corners |= bit_dir[0]
		if sides != 0 or corners != 0:
			edges_layer.set_cell(cell, PATH_SOURCE, Vector2i(sides, corners))
		if _rng.randf() < PEBBLE_CHANCE and pebbles_layer.get_cell_source_id(cell) == -1:
			pebbles_layer.set_cell(cell, PATH_SOURCE, Vector2i(_rng.randi() % 4, 16))


## Raises a rectangle of ground and draws its edges, rocky cliff face and ways up.
## A ramp 1 tile wide is a ladder; wider ramps are a dirt path cut through the cliff.
func _add_plateau(ground: TileMapLayer, overlay: TileMapLayer, rect: Rect2i, plateau_ramps: Array) -> void:
	plateaus.append(rect)
	for ramp in plateau_ramps:
		ramps.append(ramp)
	var ramp_at := func(x: int) -> Rect2i:
		for ramp in plateau_ramps:
			if x >= ramp.position.x and x < ramp.end.x:
				return ramp
		return Rect2i()
	for x in range(rect.position.x - 1, rect.end.x + 1):
		for y in range(rect.position.y - 1, rect.end.y + 3):
			var cell := Vector2i(x, y)
			if rect.has_point(cell):
				# One edge piece per direction: outlined back, rock strip down each side
				# (the front gets the cliff face's grass lip instead)
				var piece := Vector2i(-1, -1)
				var left := x == rect.position.x
				var right := x == rect.end.x - 1
				if y == rect.position.y:
					piece = CLIFF_BACK_LEFT if left else (CLIFF_BACK_RIGHT if right else CLIFF_BACK)
				elif left:
					piece = CLIFF_SIDE_LEFT
				elif right:
					piece = CLIFF_SIDE_RIGHT
				if piece.x >= 0:
					_set_tile(ground, cell, GRASS)
					overlay.set_cell(cell, CLIFF_SOURCE, piece)
					_blocked[cell] = true
				continue
			if x < rect.position.x or x >= rect.end.x or y < rect.end.y:
				continue
			# Below the front edge: two rows of cliff (or a way up), then a shadow row
			var row := y - rect.end.y
			var ramp: Rect2i = ramp_at.call(x)
			if row < 2:
				_set_tile(ground, cell, GRASS) # under the rock (its rounded corners show it)
				var column := x % CLIFF_VARIANTS
				if ramp.size.x == 1:
					column = CLIFF_LADDER
				elif ramp.size.x > 1:
					ground.set_cell(cell, SOURCE_ID, PATH_TILES[0]) # a path cut through the cliff
					column = -1
				elif x == rect.position.x or ramp_at.call(x - 1).size.x > 1:
					column = CLIFF_LEFT_END # also frames the right side of a path cut
				elif x == rect.end.x - 1 or ramp_at.call(x + 1).size.x > 1:
					column = CLIFF_RIGHT_END
				if column >= 0:
					overlay.set_cell(cell, CLIFF_SOURCE, Vector2i(column, row))
			elif ramp.size.x == 0:
				_set_tile(ground, cell, CLIFF_SHADOW)
			_blocked[cell] = true


## A few hills in the open countryside, each with a ladder up its front.
func _make_hills(ground: TileMapLayer, overlay: TileMapLayer) -> void:
	var made := 0
	for attempt in 200:
		if made >= HILL_COUNT:
			return
		var size := Vector2i(_rng.randi_range(8, 14), _rng.randi_range(5, 8))
		var corner := Vector2i(
			_rng.randi_range(BORDER + 2, map_width - size.x - BORDER - 2),
			_rng.randi_range(BORDER + 2, map_height - size.y - BORDER - 5))
		var ok := true
		for x in range(corner.x - 2, corner.x + size.x + 2):
			for y in range(corner.y - 2, corner.y + size.y + 4):
				var cell := Vector2i(x, y)
				if _blocked.has(cell) or location_at(cell) != "":
					ok = false # only on free countryside, away from roads, water and buildings
		if not ok:
			continue
		var ladder_x := corner.x + _rng.randi_range(1, size.x - 2)
		_add_plateau(ground, overlay, Rect2i(corner, size), [Rect2i(ladder_x, corner.y + size.y, 1, 2)])
		made += 1


## Invisible walls along every cliff: around a plateau's top edges and over its cliff face,
## with gaps at the ramps. Built when the game starts.
func _setup_cliff_walls() -> void:
	if plateaus.is_empty():
		return
	var walls := StaticBody2D.new()
	walls.name = "CliffWalls"
	add_child(walls)
	var add_wall := func(r: Rect2):
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = r.get_center()
		walls.add_child(collision)
	for rect in plateaus:
		var top_left := cell_to_world(rect.position) - Vector2(8, 8)
		var size := Vector2(rect.size * 16)
		add_wall.call(Rect2(top_left, Vector2(size.x, 3))) # back edge
		add_wall.call(Rect2(top_left, Vector2(3, size.y))) # left edge
		add_wall.call(Rect2(top_left + Vector2(size.x - 3, 0), Vector2(3, size.y))) # right edge
		# The cliff face below the front edge, except where a ramp goes through
		for x in range(rect.position.x, rect.end.x):
			if _is_cliff(Vector2i(x, rect.end.y)):
				add_wall.call(Rect2(cell_to_world(Vector2i(x, rect.end.y)) - Vector2(8, 8), Vector2(16, 30)))


func _make_roads(ground: TileMapLayer, decor: TileMapLayer, plaza: Vector2i) -> void:
	var home := home_spawn_cell()
	var lake := location_center("lake")
	var lake_radius: Vector2 = LOCATIONS["lake"]["radius"]
	var north := Vector2i(plaza.x + 24, int(_forest_edge(plaza.x + 24)) + 1)
	_carve_road(ground, decor, home, plaza + Vector2i(-7, 0)) # farm -> village
	_carve_road(ground, decor, plaza + Vector2i(6, 1), lake - Vector2i(0, int(lake_radius.y) - 1)) # village -> lake
	_carve_road(ground, decor, plaza + Vector2i(6, 1), plaza + Vector2i(24, 1)) # east, past the upper village
	_carve_road(ground, decor, plaza + Vector2i(24, 1), north) # village -> forest
	_carve_road(ground, decor, home + Vector2i(0, 2), location_center("meadow")) # farm -> meadow


## A footpath from every front door to the nearest road or plaza below it:
## straight down from the door, then sideways along that row. Doors face down,
## so going down first never cuts through the house itself.
func _connect_doors(ground: TileMapLayer, decor: TileMapLayer) -> void:
	for house in houses:
		var start: Vector2i = house["door"] + Vector2i(0, 1)
		var target := _nearest_path_below(ground, start, 40)
		if target.x < 0:
			continue
		var cell := start
		while cell.y < target.y:
			_paint_path(ground, decor, cell)
			cell.y += 1
		while cell.x != target.x:
			_paint_path(ground, decor, cell)
			cell.x += signi(target.x - cell.x)


## Closest path tile at or below `from` (by walking distance), or (-1, -1).
func _nearest_path_below(ground: TileMapLayer, from: Vector2i, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for x in range(from.x - radius, from.x + radius + 1):
		for y in range(from.y, from.y + radius + 1):
			var cell := Vector2i(x, y)
			if not PATH_TILES.has(ground.get_cell_atlas_coords(cell)):
				continue
			var distance := absi(x - from.x) + absi(y - from.y)
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


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
		var size := Vector2i(_rng.randi_range(4, 7), _rng.randi_range(3, 5))
		var corner := Vector2i(
			_rng.randi_range(BORDER + 3, map_width - size.x - BORDER - 4),
			_rng.randi_range(BORDER + 3, map_height - size.y - BORDER - 4))
		var rects: Array[Rect2i] = [Rect2i(corner, size)]
		if _rng.randf() < 0.6: # a second, offset rectangle for a less boxy shape
			rects.append(Rect2i(corner + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(1, 3)),
				Vector2i(_rng.randi_range(3, 5), _rng.randi_range(2, 3))))
		var ok := true
		for rect in rects:
			for x in range(rect.position.x - 1, rect.end.x + 1):
				for y in range(rect.position.y - 2, rect.end.y + 1):
					var cell := Vector2i(x, y)
					if _near_blocked(cell, 1) or location_at(cell) != "":
						ok = false # only in the open countryside, away from roads and buildings
		if ok:
			_fill_water(ground, rects)
			return


## Edges, earth faces and ripples for every lake and pond.
func _decorate_water(ground: TileMapLayer, shore: TileMapLayer, sides: TileMapLayer) -> void:
	var is_water := func(c: Vector2i) -> bool: return WATER_TILES.has(ground.get_cell_atlas_coords(c))
	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)
			if not is_water.call(cell):
				# Land right above the water: the brown earth face of the drop
				if is_water.call(cell + Vector2i(0, 1)):
					_set_tile(shore, cell, EARTH_FACE)
					_blocked[cell] = true
				continue
			var n: bool = is_water.call(cell + Vector2i(0, -1))
			var s: bool = is_water.call(cell + Vector2i(0, 1))
			if not n:
				_set_tile(shore, cell, _pick(SHORE_N))
			elif not s:
				_set_tile(shore, cell, _pick(SHORE_S))
			if not is_water.call(cell + Vector2i(-1, 0)):
				_set_tile(sides, cell, SHORE_W)
			elif not is_water.call(cell + Vector2i(1, 0)):
				_set_tile(sides, cell, SHORE_E)
			elif n and s and sin(x * 0.9) + sin(y * 1.3 + x * 0.4) > 0.9:
				_set_tile(shore, cell, _pick(WATER_FLECKS)) # ripples in patches; the rest stays smooth


## A wooden dock reaching into the lake where the road from the village arrives.
## Returns the dock's column (or -1).
func _make_dock(ground: TileMapLayer, shore: TileMapLayer, decor: TileMapLayer) -> int:
	var x := location_center("lake").x
	var top := -1
	for y in range(location_center("lake").y - 20, location_center("lake").y):
		if WATER_TILES.has(ground.get_cell_atlas_coords(Vector2i(x, y))):
			top = y
			break
	if top < 0:
		return -1
	# Starts on the shore (over the earth face) and runs out over the water
	for i in range(-1, DOCK_LENGTH):
		var cell := Vector2i(x, top + i)
		_set_tile(shore, cell, DOCK_END if i == DOCK_LENGTH - 1 else DOCK_PLANK)
		_blocked[cell] = true
		if i >= 0 and i % 2 == 0:
			_set_tile(decor, cell + Vector2i(-1, 0), DOCK_POST_LEFT)
			_set_tile(decor, cell + Vector2i(1, 0), DOCK_POST_RIGHT)
	dock_cells = Rect2i(x, top - 1, 1, DOCK_LENGTH + 1)
	# The 2-wide road narrows to a 1-tile footpath lined up with the dock
	for y in range(top - 4, top - 1):
		for dx in [-2, -1, 1, 2]:
			var side := Vector2i(x + dx, y)
			if PATH_TILES.has(ground.get_cell_atlas_coords(side)):
				ground.set_cell(side, SOURCE_ID, GRASS)
		ground.set_cell(Vector2i(x, y), SOURCE_ID, PATH_TILES[0])
	return x


## A fence along the lake's north shore (behind the earth face), open at the dock.
func _make_lake_fence(ground: TileMapLayer, shore: TileMapLayer, decor: TileMapLayer, dock_x: int) -> void:
	var fence_cells: Array[Vector2i] = []
	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)
			var below := cell + Vector2i(0, 1)
			if location_at(below) != "lake" or shore.get_cell_atlas_coords(below) != EARTH_FACE:
				continue
			if x == dock_x or PATH_TILES.has(ground.get_cell_atlas_coords(cell)):
				continue # gap for the path onto the dock
			fence_cells.append(cell)
	# Join neighbours into runs with an end post on each side (short bits look odd: skipped)
	for cell in fence_cells:
		if fence_cells.has(cell + Vector2i(-1, 0)):
			continue # not the start of a run
		var length := 1
		while fence_cells.has(cell + Vector2i(length, 0)):
			length += 1
		if length < 4:
			continue
		for i in length:
			var piece := FENCE_LEFT if i == 0 else (FENCE_RIGHT if i == length - 1 else FENCE_MIDDLE)
			_set_tile(decor, cell + Vector2i(i, 0), piece)
			_blocked[cell + Vector2i(i, 0)] = true


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
	return [WELL, STATUE, BED, RUG,
		{"origin": Vector2i(38, 1), "size": Vector2i(5, 2)}, # fence pieces and corners
		{"origin": Vector2i(40, 3), "size": Vector2i(1, 1)}, TROUGH, ANVIL, FORGE,
		{"origin": Vector2i(38, 16), "size": Vector2i(4, 1)}, # barrels
		{"origin": Vector2i(42, 33), "size": Vector2i(6, 2)}, # all shelves
	]


## Keeps the tile layers exactly on top of each other and locks them in the editor,
## so clicking on the map can't drag or stretch one of them by accident.
func _fix_layers() -> void:
	for layer_name in ["Ground", "Shore", "ShoreSides", "Decor", "Canopy", "Roofs"]:
		var layer := get_node_or_null(layer_name) as Node2D
		if layer:
			layer.transform = Transform2D.IDENTITY
			layer.set_meta("_edit_lock_", true)


## An overlay layer for water edges, `above` places it right over the ground (1, 2, ...).
func _get_or_create_shore(ground: TileMapLayer, layer_name: String, above: int) -> TileMapLayer:
	var shore := get_node_or_null(layer_name) as TileMapLayer
	if shore == null:
		shore = TileMapLayer.new()
		shore.name = layer_name
		shore.tile_set = ground.tile_set
		shore.collision_enabled = false
		add_child(shore)
		shore.owner = self # saved with the scene
	move_child(shore, ground.get_index() + above) # under everything else
	return shore


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
				_fell_tree(tree_cell, i)
				_changes.append({"felled": [tree_cell.x, tree_cell.y], "tree": i})
				# Wood pops out around the stump; the player walks over it to collect
				var stump := decor.to_global(decor.map_to_local(tree_cell + Vector2i(0, size.y - 1)))
				drop_items(stump + Vector2(size.x * 4 - 4, 0), "wood", load(WOOD_ICON), WOOD_DROPS)
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
	_changes.append({"cut": [cell.x, cell.y]})
	return true


## Throws `count` pickups out of `world_pos` in random directions, landing
## between distance.x and distance.y pixels away.
func drop_items(world_pos: Vector2, item: String, icon: Texture2D, count: int, distance := Vector2(22, 34)) -> void:
	var player := get_node_or_null("Player")
	for n in count:
		var pickup := Node2D.new()
		pickup.set_script(load("res://scripts/pickup.gd"))
		pickup.item = item
		pickup.texture = icon
		add_child(pickup)
		if player:
			move_child(pickup, player.get_index()) # lies on the ground, under the player
		# Land on dry ground (or the dock): try a few directions, else drop at your feet
		var land := world_pos + Vector2(0, 6)
		for attempt in 8:
			var angle := TAU * (n + randf() * 0.6 + attempt * 0.37) / count
			var spot := world_pos + Vector2(cos(angle), sin(angle) * 0.6) * randf_range(distance.x, distance.y) + Vector2(0, 8)
			if not is_water(spot):
				land = spot
				break
		pickup.launch(world_pos, land)


## Removes a tree (all its tiles) and leaves a stump.
func _fell_tree(tree_cell: Vector2i, index: int) -> void:
	var decor := get_node("Decor") as TileMapLayer
	var canopy := get_node_or_null("Canopy") as TileMapLayer
	if canopy == null:
		canopy = decor
	var size: Vector2i = BIG_OBJECTS[index]["size"]
	for ox in size.x:
		for oy in size.y:
			var c := tree_cell + Vector2i(ox, oy)
			decor.erase_cell(c)
			canopy.erase_cell(c)
	decor.set_cell(tree_cell + Vector2i(0, size.y - 1), SOURCE_ID, STUMP)


## What changed on the map this game, for the save file.
func get_changes() -> Array:
	return _changes.duplicate(true)


## Replays saved changes: fells the same trees and cuts the same plants again.
func apply_changes(changes: Array) -> void:
	var decor := get_node("Decor") as TileMapLayer
	for change in changes:
		if change.has("felled"):
			_fell_tree(Vector2i(change["felled"][0], change["felled"][1]), int(change["tree"]))
		elif change.has("cut"):
			decor.erase_cell(Vector2i(change["cut"][0], change["cut"][1]))
	_changes = changes.duplicate(true)


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
	var shore := get_node_or_null("Shore") as TileMapLayer
	if shore and shore.get_cell_source_id(cell) != -1:
		return false # earth faces at the water, the dock
	return true


## Location display name at a world position ("" in the open countryside).
func location_name_at(world_pos: Vector2) -> String:
	var ground := get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return ""
	return location_name(location_at(ground.local_to_map(ground.to_local(world_pos))))


## At game start: gives every house its own roof layer (so only that roof fades),
## invisible walls with a gap at the door, and chimney smoke.
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
	_add_chimney_smoke(shared)


## Animated smoke rising from every house that has a chimney.
func _add_chimney_smoke(roofs: TileMapLayer) -> void:
	var strip: Texture2D = load(CHIMNEY_SMOKE)
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 10.0)
	for i in strip.get_width() / SMOKE_FRAME_WIDTH:
		var atlas := AtlasTexture.new()
		atlas.atlas = strip
		atlas.region = Rect2(i * SMOKE_FRAME_WIDTH, 0, SMOKE_FRAME_WIDTH, strip.get_height())
		frames.add_frame("default", atlas)
	# [tile, where its opening is relative to the tile's center]
	var chimneys: Array = houses.filter(func(h): return h.has("chimney")).map(func(h): return [h["chimney"], Vector2(1, 2)])
	if forge_cell.x >= 0:
		chimneys.append([forge_cell + Vector2i(1, -1), Vector2(-2, -4)]) # the forge's stone chimney
	for chimney in chimneys:
		var smoke := AnimatedSprite2D.new()
		smoke.sprite_frames = frames
		smoke.centered = false
		# The smoke starts at the bottom of its frame, right at the opening
		var opening: Vector2 = roofs.map_to_local(chimney[0]) + chimney[1]
		smoke.position = to_local(roofs.to_global(opening)) - Vector2(SMOKE_FRAME_WIDTH / 2.0, strip.get_height())
		smoke.modulate.a = 0.85
		add_child(smoke) # last child: drawn above the roofs
		smoke.play()
		smoke.frame = randi() % frames.get_frame_count("default") # chimneys don't puff in sync


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


## True if there's water (lake or pond) at world_pos, not counting the dock.
## Used for fishing and swimming.
func is_water(world_pos: Vector2) -> bool:
	var ground := get_node("Ground") as TileMapLayer
	var cell := ground.local_to_map(ground.to_local(world_pos))
	return WATER_TILES.has(ground.get_cell_atlas_coords(cell)) and not dock_cells.has_point(cell)


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
	var ranch := get_node_or_null("Ranch")
	if ranch:
		clock.new_day.connect(ranch.on_new_day)
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
	merchant.position = to_local(cell_to_world(market_cell + Vector2i(2, -1)) + Vector2(0, 2))
	add_child(merchant)

	# The stall: three crates of produce in a row in front of the merchant
	var stall := StaticBody2D.new()
	stall.name = "MarketStall"
	stall.position = to_local(cell_to_world(market_cell + Vector2i(2, 0)))
	var crate_texture: Texture2D = load(MARKET_CRATE)
	for i in MARKET_PRODUCE.size():
		var crate := Sprite2D.new()
		crate.texture = crate_texture
		crate.position = Vector2((i - 1) * 16, 0)
		stall.add_child(crate)
		var produce := Sprite2D.new()
		produce.texture = load("res://assets/Sunnyside_World_Assets/Elements/Crops/%s_05.png" % MARKET_PRODUCE[i])
		produce.position = Vector2((i - 1) * 16, -5) # sitting in the open top of the crate
		stall.add_child(produce)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(48, 10)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, 2)
	stall.add_child(collision)
	add_child(stall)

	var player := get_node_or_null("Player")
	if player:
		move_child(merchant, player.get_index())
		move_child(stall, player.get_index()) # drawn over the merchant's feet: he's behind it


## The smithy's forge: flickering fire in the furnace (its smoke comes from _add_chimney_smoke).
func _add_forge_fire() -> void:
	if forge_cell.x < 0:
		return
	var strip: Texture2D = load(FORGE_FIRE)
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 8.0)
	for i in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = strip
		atlas.region = Rect2(i * 8, 0, 8, strip.get_height())
		frames.add_frame("default", atlas)
	var fire := AnimatedSprite2D.new()
	fire.sprite_frames = frames
	fire.position = to_local(cell_to_world(forge_cell)) + Vector2(-1, -2) # in the furnace mouth
	fire.play()
	add_child(fire)
	var decor := get_node_or_null("Decor")
	if decor:
		move_child(fire, decor.get_index() + 1)


## Moving water (shader on the Ground layer), sparkles on the water and ducks on the lake.
func _add_water_effects() -> void:
	var ground := get_node("Ground") as TileMapLayer
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	ground.material = material

	var shore := get_node_or_null("Shore") as TileMapLayer
	var sides := get_node_or_null("ShoreSides") as TileMapLayer
	var life := Node2D.new()
	life.set_script(load("res://scripts/water_life.gd"))
	life.name = "WaterLife"
	for cell in ground.get_used_cells_by_id(SOURCE_ID, WATER_TILES[0]):
		var edge := (sides and sides.get_cell_source_id(cell) != -1) 				or (shore and not WATER_FLECKS.has(shore.get_cell_atlas_coords(cell)) and shore.get_cell_source_id(cell) != -1)
		if edge or dock_cells.has_point(cell):
			continue # only open water, away from the edges and the dock
		var spot := cell_to_world(cell)
		life.water_spots.append(spot)
		if location_at(cell) == "lake":
			life.lake_spots.append(spot)
	add_child(life)
	var decor := get_node_or_null("Decor")
	if decor:
		move_child(life, decor.get_index()) # on the water, under everything standing on land


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
		npc.set("animation_folder", info.get("animation", "IDLE"))
		npc.set("turn_to_player", info.get("turn_to_player", true))
		npc.set("face_right", info.get("face_right", false))
		npc.set("shop", info.get("shop", ""))
		npc.position = to_local(cell_to_world(location_center(info["place"]) + info["offset"]))
		add_child(npc)
		if player:
			move_child(npc, player.get_index())


func _spawn_ranch() -> void:
	if pen_rect.size == Vector2i.ZERO:
		return
	var ranch := Node2D.new()
	ranch.set_script(load("res://scripts/ranch.gd"))
	ranch.name = "Ranch"
	# Animals stay a tile away from the fence; the trough row is off limits too
	var inside := Rect2i(pen_rect.position + Vector2i(1, 2), pen_rect.size - Vector2i(2, 3))
	var top_left := cell_to_world(inside.position) - Vector2(4, 4)
	ranch.pen = Rect2(top_left, Vector2(inside.size * 16) - Vector2(8, 8))
	ranch.trough = cell_to_world(trough_cell) + Vector2(8, 0)
	add_child(ranch)
	var player := get_node_or_null("Player")
	if player:
		move_child(ranch, player.get_index()) # animals walk under the player


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
