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

@export var map_width: int = 180
@export var map_height: int = 124
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
const FORGE_FIRE := "res://assets/Sunnyside_World_Assets/Elements/VFX/Fire/spr_deco_fire_01_strip4.png"
const FIRE_FRAME_WIDTH := 5
# The tavern: an 8 x 8 house on the upper street. Its door leads (with a fade) into a big
# hall built off the edge of the map, furnished with props from assets/tavern/tavern_props.png
# (made with PixelLab, 32 x 32 each, 8 per row).
const TAVERN_OFFSET := Vector2i(-5, -17) # from the village center
const TAVERN_PROPS := "res://assets/tavern/tavern_props.png"
const HALL_SIZE := Vector2i(20, 14) # tiles, walls included
const HALL_GAP := 40 # tiles between the map's right edge and the hall
const HALL_DOOR_X := 10
const HALL_MARGIN := 600.0 # black space around the hall that the camera may show
# [sheet column, sheet row, tile in the hall (top-left of the 2 x 2 prop), solid width (0 = walk through)]
const HALL_LAYOUT := [
	# along the back wall (rows 0-1: drawn behind everyone, Isla included)
	[0, 7, Vector2(2, 1), 26], # fireplace
	[1, 7, Vector2(4.25, 0), 0], # torch
	[3, 6, Vector2(6.25, 1), 0], # bottle shelves behind the bar
	[4, 6, Vector2(8, 1), 0],
	[1, 3, Vector2(12, 1), 26], # barrel with a tap
	[6, 3, Vector2(14, 1), 26], # another barrel
	[7, 7, Vector2(16, 0.5), 30], # stairs (the rooms upstairs come later)
	# tables (the door aisle in the middle stays clear)
	[0, 5, Vector2(2, 6.5), 26],
	[2, 5, Vector2(2.75, 9.4), 26], # in front of the corner sofa
	[4, 5, Vector2(6, 9), 26],
	[5, 5, Vector2(12, 9), 26],
	[6, 5, Vector2(15, 6.5), 26],
	[1, 5, Vector2(15, 10), 26],
	[7, 3, Vector2(17, 11), 26], # stacked barrels in the corner
]
# Furniture Michal drew in Piskel (tidied up by tools/clean_bar.py and clean_sofa.py).
# Position in hall pixels; walls = what you bump into, also in hall pixels;
# under = drawn below people (they sit on it) instead of in front of them.
const HALL_PIECES := [
	{ # the corner bar, Isla inside its L
		"texture": "res://assets/tavern/bar_corner.png",
		"position": Vector2(88, 17),
		"walls": [
			Rect2(100, 75, 78, 14), # the long front
			Rect2(161, 18, 20, 57), # the arm back to the wall
			Rect2(88, 28, 12, 61), # the gap at its left end (a little gate)
		],
	},
	{ # the corner sofa in the bottom-left corner (the hall's walls hold it in)
		"texture": "res://assets/tavern/sofa_corner.png",
		"position": Vector2(16, 127),
		"walls": [],
		"under": true,
	},
]
const HALL_STOOLS := [ # 1 tile each, never solid
	Vector2(7, 6), Vector2(9, 6), Vector2(11, 6), # at the bar
	Vector2(1, 7), Vector2(4, 7),
	Vector2(5, 9.5), Vector2(8, 9.5), Vector2(11, 9.5), Vector2(14, 9.5),
	Vector2(14, 7), Vector2(17, 7), Vector2(14, 10.5),
]
const TAVERN_SIGN := Vector2i(0, 0) # sheet cell: hanging sign with a mug
# Places on the corner sofa you can sit (hall tiles); the stools are seats too
const HALL_SOFA_SEATS := [
	[Vector2i(1, 9), -2.0], [Vector2i(1, 10), -2.0], [Vector2i(1, 11), -2.0], # the tall seat
	[Vector2i(2, 12), -6.0], [Vector2i(3, 12), -6.0], [Vector2i(4, 12), -6.0], # the bottom seat
]
const SEAT_REACH := 12.0 # how close you stand to a seat to sit on it with E
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
# Chimney pipes that stick up over the roof (square, angled, round), one picked per house
const CHIMNEY_PIPES: Array[Vector2i] = [Vector2i(27, 5), Vector2i(28, 5), Vector2i(29, 5)]
const CHIMNEY_TOP := -17.0 # where the smoke comes out: pixels above the chimney cell's center
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
# Beaches: sand tiles, with the same wobbly grass edges as the paths (tools/make_sand_tiles.py)
const SAND_SOURCE := 3
const SAND_SHEET := "res://assets/paths/sand.png"
const SAND_TILES: Array[Vector2i] = [Vector2i(43, 7), Vector2i(43, 8)]
const SHELL_CHANCE := 0.06
# The island: sea all around (at least this many tiles of it at the map's edge)
const SEA_MARGIN := 6
const BEACH_WIDTH := 3 # tiles of sand along the sandy stretches of coast
# The river: from a spring in the pines down to the sea, between the farm and the village
const RIVER_X := 0.43 # where it starts, as a fraction of the map width
const RIVER_WIDTH := 3
const BRIDGE_PLANK := Vector2i(40, 5) # the dock's planks, laid across the river
# Waterfalls: where water crosses a cliff (tools/make_waterfall.py, 4 animation frames)
const WATERFALL_SOURCE := 4
const WATERFALL_SHEET := "res://assets/water/waterfall.png"
# The island sketch (assets/map/island_sketch.png): 1 pixel = 2 x 2 tiles. When it exists,
# the island, its water and its levels come from it instead of being made up at random.
# Colours (the nearest one counts, so slightly-off colours are fine):
const SKETCH := "res://assets/map/island_sketch.png"
const SKETCH_KEY := {
	"water": Color8(40, 110, 220), # sea, lakes, rivers (their height comes from the land around)
	"blank": Color8(255, 255, 255), # unpainted = sea
	"level0": Color8(200, 200, 200), # land at the bottom
	"level1": Color8(150, 150, 150), # a level up
	"level2": Color8(100, 100, 100), # higher
	"level3": Color8(55, 55, 55), # highest
	"beach": Color8(240, 215, 140), # sand (bottom level)
	"ladder": Color8(160, 60, 200), # a ladder up the cliff here
	"ramp": Color8(255, 140, 0), # a walkable path up the cliff (or a slope at its side)
	"line": Color8(255, 230, 0), # cliff lines people draw to plan: ignored
}
const CLOUDS := "res://assets/clouds/clouds.png"
const CLOUD_SIZE := Vector2i(64, 40)
const CLOUD_COUNT := 26
const CLOUD_SPEED := 4.0 # pixels per second, drifting east
const PEBBLE_CHANCE := 0.14
const HILL_COUNT := 12 # terraces scattered around the countryside and the pines
const HILL_SIZE_MIN := Vector2i(10, 7)
const HILL_SIZE_MAX := Vector2i(24, 13)
const SECOND_LEVEL_CHANCE := 0.75 # big terraces may get a smaller, higher level on top
# Small gable cottages (3 x 4) and lookout towers (1 x 5) from the tileset, in every roof
# colour (+ HOUSE_COLOURS row offset). Not enterable (yet): they dress up the island.
const COTTAGE := {"origin": Vector2i(32, 10), "size": Vector2i(3, 4)}
const TOWER := {"origin": Vector2i(30, 9), "size": Vector2i(1, 5)}
const COTTAGE_COUNT := 8
const TOWER_COUNT := 3

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
## Isla's tavern (the furniture and sign are added when the game starts)
@export_storage var tavern_rect := Rect2i()
## Raised ground: one rectangle per plateau (the village's upper level, hills)
@export_storage var plateaus: Array[Rect2i] = []
## Ramps: the columns of a cliff you can walk through, as rectangles over the cliff face
@export_storage var ramps: Array[Rect2i] = []
## Height of every tile (0 = bottom level), row by row: what the cliffs are drawn from
@export_storage var level_heights := PackedByteArray()
## Tiles of cliff face with a ladder, and tiles where a path cuts through (or a slope at a side)
@export_storage var ladder_cells := {}
@export_storage var ramp_cells := {}
## Cottages and towers (solid at the bottom when the game starts)
@export_storage var small_buildings: Array[Rect2i] = []
## Where roads cross the river on wooden bridges (walkable, not water to swim in)
@export_storage var bridge_cells: Array[Vector2i] = []

var _rng := RandomNumberGenerator.new()
var _blocked := {} # cells that already have a path, water or object
var _island := {} # land cells (everything else is sea), while generating
var _sand := {} # beach cells, while generating
var _river := {} # river cells, while generating
var _from_sketch := false # the island comes from assets/map/island_sketch.png
var _source: TileSetAtlasSource
var _roofs: Array[TileMapLayer] = [] # one per house at runtime, faded when you're inside
var _in_hall := false # player is inside the tavern hall (camera kept there)
var _fading := false # walking through a door
var _house_owners := {} # house index -> owner's name (from NPCS "home")
var _grid: AStarGrid2D # where villagers can walk: roads, plaza, doorways
var _hall_grid: AStarGrid2D # the same inside the tavern hall


func _ready() -> void:
	_fix_layers()
	if Engine.is_editor_hint():
		return
	_add_forge_fire()
	_setup_houses()
	_setup_cliff_walls()
	_setup_small_building_walls()
	_add_water_effects()
	_spawn_clouds()
	_spawn_farm()
	_spawn_ranch()
	_spawn_clock()
	_spawn_merchant()
	_spawn_story_characters()
	_build_tavern() # after Isla, so the bar is drawn in front of her
	_setup_world_bounds()
	_place_player()
	_spawn_goblins()
	if SaveGame.load_requested:
		SaveGame.apply(self) # "Continue" on the title screen
	elif SaveGame.intro_requested:
		_start_intro.call_deferred() # "New Game": wake up by the lake


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
	_setup_sheet_source(ground.tile_set, SAND_SOURCE, SAND_SHEET)
	for layer in [ground, decor]:
		_setup_collision(layer.tile_set)

	clear()
	houses.clear()
	bridge_cells.clear()
	plateaus.clear()
	ramps.clear()
	ladder_cells.clear()
	ramp_cells.clear()
	level_heights = PackedByteArray()
	level_heights.resize(map_width * map_height)
	_setup_sheet_source(ground.tile_set, WATERFALL_SOURCE, WATERFALL_SHEET, 4)
	_fill_grass(ground)
	_from_sketch = _apply_sketch(ground)
	if not _from_sketch:
		_make_island(ground)
		_make_beaches(ground)
		_make_river(ground)
	var layers := {"ground": ground, "decor": decor, "canopy": canopy, "roofs": roofs, "shore": shore}
	_make_home(layers)
	_make_pen(decor)
	if not _from_sketch:
		_make_lake(ground)
	var plaza := _make_village(layers)
	_make_roads(ground, decor, plaza)
	_connect_doors(ground, decor)
	_join_diagonal_paths(ground, decor)
	if not _from_sketch:
		for i in pond_count:
			_make_pond(ground)
		_make_hills(ground, shore)
	_draw_levels(ground, shore)
	_place_small_buildings(layers)
	_decorate_water(ground, shore, sides)
	_make_bridges(shore, sides)
	var dock := _make_dock(ground, shore, decor)
	_make_lake_fence(ground, shore, decor, dock)
	_scatter_objects(decor, canopy)
	_decorate_paths(ground, shore, sides)
	_decorate_beaches(ground, shore, sides)
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
	if _river.has(cell):
		if not bridge_cells.has(cell):
			bridge_cells.append(cell) # a bridge carries the road over the river
		return
	if WATER_TILES.has(ground.get_cell_atlas_coords(cell)) or decor.get_cell_source_id(cell) != -1:
		return # roads stop at water and go around buildings
	for house in houses:
		if house["rect"].has_point(cell):
			return # never through a house (its floor isn't on Decor)
	if pen_rect.has_point(cell):
		return # or the animal pen
	if _is_cliff(cell):
		ramp_cells[cell] = true # a road climbing a level cuts its own way up the cliff
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
func _build_house(layers: Dictionary, cell: Vector2i, inner: int, colour: int, chimney := false,
		height := HOUSE_HEIGHT, furnished := true) -> Dictionary:
	var ground: TileMapLayer = layers["ground"]
	var decor: TileMapLayer = layers["decor"]
	var canopy: TileMapLayer = layers["canopy"]
	var roofs: TileMapLayer = layers["roofs"]
	var width := inner + 2
	var shade := Vector2i(0, colour)
	var door_x := 1 + inner / 2
	var window_x := 1 + (inner - 1) / 2 if inner % 2 == 0 else door_x
	for x in width:
		for y in height:
			var c := cell + Vector2i(x, y)
			_blocked[c] = true
			if x == 0 or x == width - 1:
				# Side posts (the middle piece repeats for taller houses); the bottom one is front wall
				var post_row := 0 if y == 0 else (5 if y == height - 1 else (4 if y == height - 2 else mini(y, 3)))
				var post := (POST_LEFT if x == 0 else POST_RIGHT) + shade + Vector2i(0, post_row)
				_set_tile(decor if y == height - 1 else canopy, c, post)
				continue
			if y > 0:
				_set_tile(ground, c, BACK_WALL if y == 1 else FLOOR)
			if y == height - 1:
				_set_tile(decor, c, (DOOR if x == door_x else WALL_WINDOW) + shade)
				continue
			# Roof: top edge, shingles, and the eave just above the front wall
			var roof := ROOF + shade + Vector2i(0, 0 if y == 0 else (4 if y == height - 2 else 3))
			if y == 1 and x == window_x:
				roof = ROOF_WINDOW + shade
			_set_tile(roofs, c, roof)

	var house := {
		"rect": Rect2i(cell, Vector2i(width, height)),
		"door": cell + Vector2i(door_x, height - 1),
	}
	if chimney:
		# Top shingle row, right side of the roof
		var chimney_cell := cell + Vector2i(width - 2, 1)
		_set_tile(roofs, chimney_cell, ROOF_CHIMNEY + shade)
		house["chimney"] = chimney_cell
	houses.append(house)
	if not furnished:
		return house

	# Furniture: bed in the corner, a cupboard, a rug by the door and a pot
	_place_tiles(decor, cell + Vector2i(1, 1), BED)
	var shelf: Vector2i = _pick(SHELVES)
	_place_tiles(decor, cell + Vector2i(inner, 1), {"origin": shelf, "size": Vector2i(1, 2)})
	if inner >= 5:
		_place_tiles(decor, cell + Vector2i(inner - 1, 1), {"origin": _pick(SHELVES), "size": Vector2i(1, 2)})
	_place_tiles(decor, cell + Vector2i(door_x - 1, 3), RUG)
	_set_tile(decor, cell + Vector2i(1, 4), _pick(JARS))
	return house


func _set_tile(layer: TileMapLayer, cell: Vector2i, coords: Vector2i) -> void:
	if not _source.has_tile(coords):
		_source.create_tile(coords) # tiles that weren't set up in the TileSet yet
	layer.set_cell(cell, SOURCE_ID, coords)


## Copies a block of tiles (furniture) without splitting it over layers.
func _place_tiles(layer: TileMapLayer, cell: Vector2i, obj: Dictionary) -> void:
	for ox in obj["size"].x:
		for oy in obj["size"].y:
			_set_tile(layer, cell + Vector2i(ox, oy), obj["origin"] + Vector2i(ox, oy))


# --- The island sketch -----------------------------------------------------------

## Builds the island from assets/map/island_sketch.png if there is one: sea, beaches,
## lakes and rivers, the height of every bit of land, ladders and ramps. Returns false
## (and changes nothing) without a sketch.
func _apply_sketch(ground: TileMapLayer) -> bool:
	if not FileAccess.file_exists(SKETCH):
		return false
	var image := Image.load_from_file(ProjectSettings.globalize_path(SKETCH))
	if image == null:
		return false
	var blocks := Vector2i(map_width / 2, map_height / 2)
	if image.get_size() != blocks:
		image.resize(blocks.x, blocks.y, Image.INTERPOLATE_NEAREST)
	var kind := {}
	for by in blocks.y:
		for bx in blocks.x:
			kind[Vector2i(bx, by)] = _sketch_kind(image.get_pixel(bx, by))
	var level := {"level0": 0, "beach": 0, "level1": 1, "level2": 2, "level3": 3}
	var height := {}
	for b in kind:
		if level.has(kind[b]):
			height[b] = level[kind[b]]
	# Ladders, ramps and planning lines take the height of the land under them (the lower side)
	for b in kind:
		if kind[b] in ["ladder", "ramp", "line"]:
			height[b] = 0
			for d in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
				if level.has(kind.get(b + d, "")):
					height[b] = level[kind[b + d]]
					break
	# The sea: water joined to the edge of the picture. Other water (lakes, rivers) is as
	# high as the land closest to it, so a river can step down the levels in waterfalls.
	# (Only open water counts: the sea spreads through water with water all around, so a
	# river flowing into it stays a river, with bridges.)
	var wet := func(b: Vector2i) -> bool: return kind.get(b, "water") in ["water", "blank"]
	var open := func(b: Vector2i) -> bool:
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if not wet.call(b + Vector2i(ox, oy)):
					return false
		return true
	var sea := {}
	var todo: Array[Vector2i] = []
	for b in kind:
		if open.call(b) and (b.x == 0 or b.y == 0 or b.x == blocks.x - 1 or b.y == blocks.y - 1):
			sea[b] = true
			todo.append(b)
	while not todo.is_empty():
		var b: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if open.call(b + d) and kind.has(b + d) and not sea.has(b + d):
				sea[b + d] = true
				todo.append(b + d)
	for b in sea.keys(): # and the water right along the coast
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if wet.call(b + Vector2i(ox, oy)) and kind.has(b + Vector2i(ox, oy)):
					sea[b + Vector2i(ox, oy)] = true
	var frontier: Array[Vector2i] = []
	for b in height:
		frontier.append(b)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for b in frontier:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var w: Vector2i = b + d
				if kind.get(w, "") in ["water", "blank"] and not sea.has(w) and not height.has(w):
					height[w] = height[b]
					next.append(w)
		frontier = next
	# Tiles
	_island.clear()
	_sand.clear()
	_river.clear()
	for b in kind:
		for oy in 2:
			for ox in 2:
				var cell: Vector2i = b * 2 + Vector2i(ox, oy)
				_set_height(cell, 0 if sea.has(b) else height.get(b, 0))
				if sea.has(b):
					ground.set_cell(cell, SOURCE_ID, WATER_TILES[0])
					_blocked[cell] = true
					continue
				_island[cell] = true
				if kind[b] in ["water", "blank"]:
					ground.set_cell(cell, SOURCE_ID, WATER_TILES[0])
					_river[cell] = true # roads cross it on bridges
					_blocked[cell] = true
				elif kind[b] == "beach":
					ground.set_cell(cell, SOURCE_ID, _pick(SAND_TILES))
					_sand[cell] = true
					_blocked[cell] = true
	# Ladders (1 tile wide) and ramps (2 wide) go on the cliff face next to where they're drawn
	for b in kind:
		if not kind[b] in ["ladder", "ramp"]:
			continue
		var columns := [b.x * 2] if kind[b] == "ladder" else [b.x * 2, b.x * 2 + 1]
		var found := false
		for x in columns:
			for y in range(b.y * 2 - 2, b.y * 2 + 4):
				if _is_face(Vector2i(x, y)):
					var ways: Dictionary = ladder_cells if kind[b] == "ladder" else ramp_cells
					ways[Vector2i(x, y)] = true
					found = true
		if not found and kind[b] == "ramp": # no cliff here: a slope down the side of a level
			for oy in 2:
				for ox in 2:
					ramp_cells[Vector2i(b.x * 2 + ox, b.y * 2 + oy)] = true
	_block_levels()
	return true


func _sketch_kind(colour: Color) -> String:
	if colour.a < 0.5:
		return "blank"
	var best := ""
	var best_distance := INF
	for key in SKETCH_KEY:
		var c: Color = SKETCH_KEY[key]
		var distance := Vector3(c.r - colour.r, c.g - colour.g, c.b - colour.b).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = key
	return best


## Writes the current island as a sketch (the template to draw on): run from a tool script.
func export_sketch(path: String) -> void:
	var ground := get_node("Ground") as TileMapLayer
	var image := Image.create(map_width / 2, map_height / 2, false, Image.FORMAT_RGBA8)
	var names := ["level0", "level1", "level2", "level3"]
	for by in map_height / 2:
		for bx in map_width / 2:
			var cells: Array[Vector2i] = []
			for oy in 2:
				for ox in 2:
					cells.append(Vector2i(bx * 2 + ox, by * 2 + oy))
			var key: String = names[mini(height_at(cells[3]), 3)]
			var water := 0
			var sand := 0
			for cell in cells:
				if WATER_TILES.has(ground.get_cell_atlas_coords(cell)) and not bridge_cells.has(cell):
					water += 1
				if SAND_TILES.has(ground.get_cell_atlas_coords(cell)):
					sand += 1
			if water >= 2:
				key = "water"
			elif sand >= 2:
				key = "beach"
			for cell in cells:
				if ladder_cells.has(cell):
					key = "ladder"
				elif ramp_cells.has(cell):
					key = "ramp"
			image.set_pixel(bx, by, SKETCH_KEY[key])
	image.save_png(ProjectSettings.globalize_path(path))


# --- The island ------------------------------------------------------------------

## Island in the sea: a big rounded middle, every location with some land around it, and
## the pine forest along the top. Worked out in 2 x 2 blocks so the coast comes out blocky,
## like the water in the art pack (the shore pieces fit straight edges and steps).
func _make_island(ground: TileMapLayer) -> void:
	_island.clear()
	var phase := _rng.randf() * TAU
	var middle := Vector2(map_width * 0.5, map_height * 0.47)
	var reach := Vector2(map_width * 0.4, map_height * 0.37)
	for by in range(0, map_height, 2):
		for bx in range(0, map_width, 2):
			var c := Vector2i(bx, by)
			var land := false
			if bx >= SEA_MARGIN and by >= SEA_MARGIN and bx < map_width - SEA_MARGIN - 1 and by < map_height - SEA_MARGIN - 1:
				var d := (Vector2(c) - middle) / reach
				var wobble := 1.0 + 0.09 * sin(d.angle() * 3.0 + phase) + 0.05 * sin(d.angle() * 7.0 + phase * 2.0)
				land = d.length() < wobble
				for key in LOCATIONS:
					if _in_ellipse(c, location_center(key), LOCATIONS[key]["radius"] + Vector2(6, 5)):
						land = true
				# Land all along the roads between places, so the sea never cuts a road
				for link in [["farm", "village"], ["farm", "meadow"], ["village", "lake"]]:
					var from := Vector2(location_center(link[0]))
					var to := Vector2(location_center(link[1]))
					var along := clampf((Vector2(c) - from).dot(to - from) / (to - from).length_squared(), 0.0, 1.0)
					if Vector2(c).distance_to(from.lerp(to, along)) < 8.0:
						land = true
				var forest_top := SEA_MARGIN + 3 + 3.0 * sin(bx * 0.11 + phase) + 2.0 * sin(bx * 0.27)
				if by > forest_top and by < _forest_edge(bx) + 4 and bx > map_width * 0.07 and bx < map_width * 0.93:
					land = true
			if land:
				for oy in 2:
					for ox in 2:
						_island[c + Vector2i(ox, oy)] = true
	for x in map_width:
		for y in map_height:
			var cell := Vector2i(x, y)
			if not _island.has(cell):
				ground.set_cell(cell, SOURCE_ID, WATER_TILES[0])
				_blocked[cell] = true


## Sandy beaches on some stretches of coast (not in the forest, the farm or the village).
func _make_beaches(ground: TileMapLayer) -> void:
	_sand.clear()
	var phase := _rng.randf() * TAU
	for cell in _island:
		if location_at(cell) in ["farm", "village", "forest"] or cell.y < _forest_edge(cell.x) + 3:
			continue
		if sin(cell.x * 0.06 + phase) + cos(cell.y * 0.08 + phase * 0.7) < 0.2:
			continue # these stretches of coast stay grassy (with a cliff drop to the sea)
		var near_sea := false
		for oy in range(-BEACH_WIDTH, BEACH_WIDTH + 1):
			for ox in range(-BEACH_WIDTH, BEACH_WIDTH + 1):
				if not _island.has(cell + Vector2i(ox, oy)):
					near_sea = true
		if near_sea:
			_sand[cell] = true
			ground.set_cell(cell, SOURCE_ID, _pick(SAND_TILES))
			_blocked[cell] = true # (beach decoration comes later)


## A river from a spring in the pines down to the sea: 3 tiles wide, running south in
## straight stretches with a step to one side now and then (blocky, like the lake).
func _make_river(ground: TileMapLayer) -> void:
	_river.clear()
	var x := int(map_width * RIVER_X)
	var y := int(_forest_edge(x)) - 10
	var left := int(map_width * 0.4) # stay between the farm and the village
	var right := int(map_width * 0.48)
	while y < map_height:
		var run := _rng.randi_range(5, 9)
		for i in run:
			for w in RIVER_WIDTH:
				var cell := Vector2i(x + w, y)
				if _island.has(cell):
					_river[cell] = true
			y += 1
		var step := _rng.randi_range(2, 4) * (1 if _rng.randf() < 0.5 else -1)
		var to := clampi(x + step, left, right)
		for sx in range(mini(x, to), maxi(x, to) + 1): # the bend: a little sideways stretch
			for w in RIVER_WIDTH:
				var cell := Vector2i(sx + w, y)
				if _island.has(cell):
					_river[cell] = true
		x = to
		if not _island.has(Vector2i(x + 1, y)):
			break # reached the sea
	for cell in _river:
		ground.set_cell(cell, SOURCE_ID, WATER_TILES[0])
		_blocked[cell] = true
		_sand.erase(cell)


## Wooden bridges where the roads cross the river (planks over the water, edges cleared).
func _make_bridges(shore: TileMapLayer, sides: TileMapLayer) -> void:
	for cell in bridge_cells:
		_set_tile(shore, cell, BRIDGE_PLANK)
		sides.erase_cell(cell)


## Grassy edges where the beach meets the grass (like the paths), and a few shells.
func _decorate_beaches(ground: TileMapLayer, edges_layer: TileMapLayer, shells_layer: TileMapLayer) -> void:
	var is_grass := func(c: Vector2i) -> bool:
		if _sand.has(c):
			return false
		var tile := ground.get_cell_atlas_coords(c)
		return ground.get_cell_source_id(c) == SOURCE_ID and (tile == GRASS or GRASS_VARIANTS.has(tile) or tile == CLIFF_SHADOW)
	for cell in _sand:
		if ground.get_cell_source_id(cell) != SOURCE_ID or not SAND_TILES.has(ground.get_cell_atlas_coords(cell)):
			continue # a road went over it
		var sides := 0
		for bit_dir in [[1, Vector2i(0, -1)], [2, Vector2i(1, 0)], [4, Vector2i(0, 1)], [8, Vector2i(-1, 0)]]:
			if is_grass.call(cell + bit_dir[1]):
				sides |= bit_dir[0]
		var corners := 0
		for bit_dir in [[1, Vector2i(1, -1)], [2, Vector2i(1, 1)], [4, Vector2i(-1, 1)], [8, Vector2i(-1, -1)]]:
			if is_grass.call(cell + bit_dir[1]):
				corners |= bit_dir[0]
		if sides != 0 or corners != 0:
			edges_layer.set_cell(cell, SAND_SOURCE, Vector2i(sides, corners))
		elif _rng.randf() < SHELL_CHANCE and shells_layer.get_cell_source_id(cell) == -1:
			shells_layer.set_cell(cell, SAND_SOURCE, Vector2i(_rng.randi() % 4, 16))


## Adds a tile sheet to the TileSet (once) as `source_id`, with every 16 x 16 tile in it.
## frames > 1: each row is one animated tile, its frames side by side.
func _setup_sheet_source(tile_set: TileSet, source_id: int, sheet: String, frames := 1) -> void:
	var source: TileSetAtlasSource
	if tile_set.has_source(source_id):
		source = tile_set.get_source(source_id)
	else:
		source = TileSetAtlasSource.new()
		source.texture = load(sheet)
		source.texture_region_size = Vector2i(16, 16)
		tile_set.add_source(source, source_id)
	if frames > 1:
		for y in source.texture.get_height() / 16:
			var tile := Vector2i(0, y)
			if not source.has_tile(tile):
				source.create_tile(tile)
			source.set_tile_animation_frames_count(tile, frames)
			source.set_tile_animation_speed(tile, 8.0)
		return
	for x in source.texture.get_width() / 16:
		for y in source.texture.get_height() / 16:
			if not source.has_tile(Vector2i(x, y)):
				source.create_tile(Vector2i(x, y))


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
		Vector2i(-20, -15), Vector2i(-12, -15), Vector2i(4, -15), Vector2i(12, -15),
		Vector2i(-9, 6), Vector2i(3, 6),
	]
	for i in spots.size():
		_build_house(layers, c + spots[i], 4, colours[(first + i) % colours.size()], _rng.randf() < CHIMNEY_CHANCE)
	# Isla's tavern in the middle of the upper street: bigger, its hall is built in _build_tavern
	var tavern := _build_house(layers, c + TAVERN_OFFSET, 6, HOUSE_COLOURS[2], true, 8, false)
	tavern["tavern"] = true
	tavern_rect = tavern["rect"]
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


# --- Levels: heights, cliffs, ladders, ramps and waterfalls -----------------------

## How many levels up a tile is: 0 at the bottom, then 1, 2, 3.
func height_at(cell: Vector2i) -> int:
	if level_heights.is_empty() or cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return 0
	return level_heights[cell.y * map_width + cell.x]


func _set_height(cell: Vector2i, h: int) -> void:
	if cell.x >= 0 and cell.y >= 0 and cell.x < map_width and cell.y < map_height:
		level_heights[cell.y * map_width + cell.x] = h


func is_high(cell: Vector2i) -> bool:
	return height_at(cell) > 0


## The two rows below the front of a higher level: rock (or a waterfall).
func _is_face(cell: Vector2i) -> bool:
	var h := height_at(cell)
	var up1 := height_at(cell + Vector2i(0, -1))
	return up1 > h or (height_at(cell + Vector2i(0, -2)) > h and up1 == h)


## A cliff face you can't get through (ladders and ramps cut through it).
func _is_cliff(cell: Vector2i) -> bool:
	return _is_face(cell) and not ladder_cells.has(cell) and not ramp_cells.has(cell)


## Draws every level from the heights: grass-and-rock edges around the top of each higher
## area, the 2-row rock face below its front (ladders, path cuts, waterfalls where water
## falls over it) and a shadow at the foot.
func _draw_levels(ground: TileMapLayer, overlay: TileMapLayer) -> void:
	var is_water := func(c: Vector2i) -> bool:
		return ground.get_cell_source_id(c) == SOURCE_ID and WATER_TILES.has(ground.get_cell_atlas_coords(c))
	var falls := func(c: Vector2i) -> bool: # water pouring over the cliff here
		var row := 0 if height_at(c + Vector2i(0, -1)) > height_at(c) else 1
		return is_water.call(c) and is_water.call(c + Vector2i(0, -1 - row))
	var rock := func(c: Vector2i) -> bool: # a face tile that is rock (for the rounded ends)
		return _is_face(c) and not ramp_cells.has(c) and not falls.call(c)
	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)
			var h := height_at(cell)
			if _is_face(cell):
				var row := 0 if height_at(cell + Vector2i(0, -1)) > h else 1
				if ramp_cells.has(cell):
					ground.set_cell(cell, SOURCE_ID, PATH_TILES[0]) # a path cut through the cliff
				elif is_water.call(cell) and is_water.call(cell + Vector2i(0, -1 - row)):
					overlay.set_cell(cell, WATERFALL_SOURCE, Vector2i(0, row)) # water above too: it falls
				else:
					if not is_water.call(cell):
						_set_tile(ground, cell, GRASS) # under the rock (its rounded corners show it)
					var column := x % CLIFF_VARIANTS
					if ladder_cells.has(cell):
						column = CLIFF_LADDER
					elif not rock.call(cell + Vector2i(-1, 0)):
						column = CLIFF_LEFT_END # also frames the right side of a path cut
					elif not rock.call(cell + Vector2i(1, 0)):
						column = CLIFF_RIGHT_END
					overlay.set_cell(cell, CLIFF_SOURCE, Vector2i(column, row))
				_blocked[cell] = true
				continue
			if is_water.call(cell):
				continue
			var above := cell + Vector2i(0, -1)
			if _is_face(above) and not ramp_cells.has(above) and not ladder_cells.has(above) and not is_water.call(above):
				_set_tile(ground, cell, CLIFF_SHADOW)
				_blocked[cell] = true
			if h == 0:
				continue
			# Edge pieces on higher ground: outlined back, rock strip down each side
			# (the front gets the cliff face's grass lip instead)
			var up_low := height_at(above) < h
			var left_low := height_at(cell + Vector2i(-1, 0)) < h and not ramp_cells.has(cell + Vector2i(-1, 0))
			var right_low := height_at(cell + Vector2i(1, 0)) < h and not ramp_cells.has(cell + Vector2i(1, 0))
			if ramp_cells.has(cell):
				left_low = false # a slope down the side
				right_low = false
			var piece := Vector2i(-1, -1)
			if up_low:
				piece = CLIFF_BACK_LEFT if left_low else (CLIFF_BACK_RIGHT if right_low else CLIFF_BACK)
			elif left_low:
				piece = CLIFF_SIDE_LEFT
			elif right_low:
				piece = CLIFF_SIDE_RIGHT
			if piece.x >= 0:
				_set_tile(ground, cell, GRASS)
				overlay.set_cell(cell, CLIFF_SOURCE, piece)
				_blocked[cell] = true


## Keeps roads, houses and trees off cliff faces, edges and shadows (before they're drawn).
func _block_levels() -> void:
	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)
			var h := height_at(cell)
			if _is_face(cell) or _is_face(cell + Vector2i(0, -1)) or (h > 0 and (height_at(cell + Vector2i(0, -1)) < h \
					or height_at(cell + Vector2i(-1, 0)) < h or height_at(cell + Vector2i(1, 0)) < h)):
				_blocked[cell] = true


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


## Raises a rectangle of ground one level (from a sketch: sets it to level 1, with the bottom
## level in front for its cliff). A ramp 1 tile wide is a ladder; wider ones are a path cut
## through the cliff. Drawn later by _draw_levels.
func _add_plateau(_ground: TileMapLayer, _overlay: TileMapLayer, rect: Rect2i, plateau_ramps: Array) -> void:
	plateaus.append(rect)
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var cell := Vector2i(x, y)
			_set_height(cell, 1 if _from_sketch else height_at(cell) + 1)
		if _from_sketch:
			for y in range(rect.end.y, rect.end.y + 3):
				_set_height(Vector2i(x, y), 0)
	for ramp in plateau_ramps:
		ramps.append(ramp)
		for x in range(ramp.position.x, ramp.end.x):
			for y in range(ramp.position.y, ramp.end.y):
				var ways: Dictionary = ladder_cells if ramp.size.x == 1 else ramp_cells
				ways[Vector2i(x, y)] = true
	# Keep everything else off its edges, its cliff and the cliff's shadow
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y + 3):
			if y == rect.position.y or x == rect.position.x or x == rect.end.x - 1 or y >= rect.end.y:
				_blocked[Vector2i(x, y)] = true


## Cottages and lookout towers around the island, on free ground (and some in the village).
func _place_small_buildings(layers: Dictionary) -> void:
	small_buildings.clear()
	var wanted := [[COTTAGE, COTTAGE_COUNT], [TOWER, TOWER_COUNT]]
	for entry in wanted:
		var obj: Dictionary = entry[0]
		var made := 0
		for attempt in 800:
			if made >= entry[1]:
				break
			var size: Vector2i = obj["size"]
			var corner := Vector2i(_rng.randi_range(SEA_MARGIN, map_width - size.x - SEA_MARGIN),
				_rng.randi_range(SEA_MARGIN, map_height - size.y - SEA_MARGIN))
			var ok := true
			for x in range(corner.x - 2, corner.x + size.x + 2):
				for y in range(corner.y - 1, corner.y + size.y + 2):
					var cell := Vector2i(x, y)
					if _blocked.has(cell) or not _island.has(cell) or height_at(cell) != height_at(corner) \
							or location_at(cell) in ["farm", "lake"]:
						ok = false
			if not ok:
				continue
			_build_small(layers, corner, obj, HOUSE_COLOURS[_rng.randi() % HOUSE_COLOURS.size()])
			made += 1


## One cottage or tower: the bottom row (walls, door) on Decor, the roof on the Canopy.
func _build_small(layers: Dictionary, corner: Vector2i, obj: Dictionary, colour: int) -> void:
	var size: Vector2i = obj["size"]
	for x in size.x:
		for y in size.y:
			var cell := corner + Vector2i(x, y)
			var tile: Vector2i = obj["origin"] + Vector2i(x, y + colour)
			_set_tile(layers["decor"] if y == size.y - 1 else layers["canopy"], cell, tile)
			_blocked[cell] = true
	small_buildings.append(Rect2i(corner, size))


## A few hills in the open countryside, each with a ladder up its front.
func _make_hills(ground: TileMapLayer, overlay: TileMapLayer) -> void:
	var made := 0
	for attempt in 600:
		if made >= HILL_COUNT:
			return
		var size := Vector2i(_rng.randi_range(HILL_SIZE_MIN.x, HILL_SIZE_MAX.x), _rng.randi_range(HILL_SIZE_MIN.y, HILL_SIZE_MAX.y))
		var corner := Vector2i(
			_rng.randi_range(SEA_MARGIN + 2, map_width - size.x - SEA_MARGIN - 2),
			_rng.randi_range(SEA_MARGIN + 2, map_height - size.y - SEA_MARGIN - 5))
		var ok := true
		for x in range(corner.x - 2, corner.x + size.x + 2):
			for y in range(corner.y - 2, corner.y + size.y + 4):
				var cell := Vector2i(x, y)
				if _blocked.has(cell) or not (location_at(cell) in ["", "forest"]):
					ok = false # only on free countryside or in the pines, away from roads and water
		if not ok:
			continue
		var ladder_x := corner.x + _rng.randi_range(1, size.x - 2)
		_add_plateau(ground, overlay, Rect2i(corner, size), [Rect2i(ladder_x, corner.y + size.y, 1, 2)])
		# A smaller level on top: inset from the sides, and far enough back that its cliff,
		# shadow and ladder all sit on the terrace
		if size.x >= 14 and size.y >= 9 and _rng.randf() < SECOND_LEVEL_CHANCE:
			var top := Rect2i(corner + Vector2i(_rng.randi_range(2, 4), 1),
				Vector2i(_rng.randi_range(6, size.x - 6), _rng.randi_range(3, size.y - 6)))
			var top_ladder := top.position.x + _rng.randi_range(1, top.size.x - 2)
			if absi(top_ladder - ladder_x) > 1:
				_add_plateau(ground, overlay, top, [Rect2i(top_ladder, top.end.y, 1, 2)])
		made += 1


## Cottages and towers are solid at the bottom (front wall and lower roof); you can walk
## behind their upper roof.
func _setup_small_building_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "SmallBuildingWalls"
	add_child(walls)
	for rect in small_buildings:
		var top_left := cell_to_world(rect.position + Vector2i(0, rect.size.y - 2)) - Vector2(8, 8)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(rect.size.x * 16 - 4, 28)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = top_left + Vector2(rect.size.x * 8, 16)
		walls.add_child(collision)


## Invisible walls along every cliff: over the rock faces (and waterfalls) except where a
## ladder or path goes through, and thin ones along the top and sides of every higher area.
## Built when the game starts, from the heights.
func _setup_cliff_walls() -> void:
	if level_heights.is_empty():
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
	for y in map_height:
		var face_from := -1 # runs of cliff face become one wall
		var back_from := -1 # runs of back edge too
		for x in map_width + 1:
			var cell := Vector2i(x, y)
			var h := height_at(cell)
			var face := x < map_width and _is_cliff(cell)
			var back := x < map_width and h > 0 and height_at(cell + Vector2i(0, -1)) < h and not _is_face(cell)
			if face and face_from < 0:
				face_from = x
			elif not face and face_from >= 0:
				add_wall.call(Rect2(cell_to_world(Vector2i(face_from, y)) - Vector2(8, 8), Vector2((x - face_from) * 16, 16)))
				face_from = -1
			if back and back_from < 0:
				back_from = x
			elif not back and back_from >= 0:
				add_wall.call(Rect2(cell_to_world(Vector2i(back_from, y)) - Vector2(8, 8), Vector2((x - back_from) * 16, 3)))
				back_from = -1
			if x >= map_width or h == 0 or ramp_cells.has(cell):
				continue
			var top_left := cell_to_world(cell) - Vector2(8, 8)
			if height_at(cell + Vector2i(-1, 0)) < h and not ramp_cells.has(cell + Vector2i(-1, 0)):
				add_wall.call(Rect2(top_left, Vector2(3, 16)))
			if height_at(cell + Vector2i(1, 0)) < h and not ramp_cells.has(cell + Vector2i(1, 0)):
				add_wall.call(Rect2(top_left + Vector2(13, 0), Vector2(3, 16)))


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


## Where a road squeezed past a corner (a house, a pond) two path tiles may only touch
## diagonally, and nobody can walk between them: pave one of the two corner tiles.
func _join_diagonal_paths(ground: TileMapLayer, decor: TileMapLayer) -> void:
	var is_path := func(c: Vector2i) -> bool: return PATH_TILES.has(ground.get_cell_atlas_coords(c)) or bridge_cells.has(c)
	for cell in ground.get_used_cells():
		if not is_path.call(cell):
			continue
		for d in [Vector2i(1, 1), Vector2i(1, -1)]:
			var side_a: Vector2i = cell + Vector2i(d.x, 0)
			var side_b: Vector2i = cell + Vector2i(0, d.y)
			if is_path.call(cell + d) and not is_path.call(side_a) and not is_path.call(side_b):
				_paint_path(ground, decor, side_a)
				if not is_path.call(side_a):
					_paint_path(ground, decor, side_b)


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
			if is_water.call(cell) and _is_face(cell):
				continue # a waterfall
			if not is_water.call(cell):
				# Land right above the water: the brown earth face of the drop
				if is_water.call(cell + Vector2i(0, 1)) and not _sand.has(cell) and not _is_face(cell + Vector2i(0, 1)) \
						and not _is_face(cell):
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
	var cell := ground.local_to_map(ground.to_local(world_pos))
	if hall_rect().has_point(cell):
		return "The Tavern"
	for i in houses.size():
		var rect: Rect2i = houses[i]["rect"]
		if Rect2i(rect.position + Vector2i(1, 1), rect.size - Vector2i(2, 1)).has_point(cell):
			if i == 0:
				return "Home"
			if _house_owners.has(i):
				return "%s's House" % _house_owners[i]
	return location_name(location_at(cell))


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
	_add_chimney_pipes()
	_add_chimney_smoke(shared)


## A chimney pipe on every house that has a chimney: it stands on the roof's top edge and
## sticks up over it (the smoke comes out of its top). It belongs to the house's roof, so
## it fades away with the roof when you walk in.
func _add_chimney_pipes() -> void:
	var source := (get_node("Ground") as TileMapLayer).tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	for i in houses.size():
		if not houses[i].has("chimney") or i >= _roofs.size():
			continue
		var roof := _roofs[i]
		var cell: Vector2i = houses[i]["chimney"]
		var shingles := roof.get_cell_atlas_coords(cell + Vector2i(-1, 0))
		if shingles != Vector2i(-1, -1):
			roof.set_cell(cell, SOURCE_ID, shingles) # plain roof under the pipe, not the old vent
		var pipe := Sprite2D.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = source.texture
		var kind: Vector2i = CHIMNEY_PIPES[absi(cell.x * 7 + cell.y * 3) % CHIMNEY_PIPES.size()]
		atlas.region = Rect2(Vector2(kind * 16), Vector2(16, 16))
		pipe.texture = atlas
		pipe.position = roof.map_to_local(cell + Vector2i(0, -1)) + Vector2(0, 4) # set into the roof's top edge
		roof.add_child(pipe)


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
	var chimneys: Array = houses.filter(func(h): return h.has("chimney")).map(func(h): return [h["chimney"], Vector2(0, CHIMNEY_TOP)])
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
	_check_doors(cell, player)
	if hall_rect().has_point(cell) != _in_hall:
		_update_camera_area(player) # e.g. a save loaded inside the tavern
	for i in _roofs.size():
		if houses[i].get("tavern", false):
			continue # you go through the tavern's door instead of under its roof
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
	return WATER_TILES.has(ground.get_cell_atlas_coords(cell)) and not dock_cells.has_point(cell) \
		and not bridge_cells.has(cell)


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
	clock.new_day.connect(func(_day): Story.new_day()) # chats and presents again
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


## The tavern's hall: the room you get to through its door, built past the map's right edge.
func hall_rect() -> Rect2i:
	return Rect2i(Vector2i(map_width + HALL_GAP, 10), HALL_SIZE)


func _hall_door() -> Vector2i:
	return hall_rect().position + Vector2i(HALL_DOOR_X, HALL_SIZE.y - 1)


func _tavern_door() -> Vector2i:
	for house in houses:
		if house.get("tavern", false):
			return house["door"]
	return Vector2i(-1, -1)


## Builds the tavern hall (floor, walls, furniture) and the sign over the tavern's front door.
func _build_tavern() -> void:
	if tavern_rect.size == Vector2i.ZERO:
		return
	var ground := get_node("Ground") as TileMapLayer
	var sheet: Texture2D = load(TAVERN_PROPS)
	var prop := func(col: int, row: int) -> AtlasTexture:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(col * 32, row * 32, 32, 32)
		return atlas
	var player := get_node_or_null("Player")

	var hall := Node2D.new()
	hall.name = "TavernHall"
	var rect := hall_rect()
	var corner := cell_to_world(rect.position) - Vector2(8, 8) # hall's top-left pixel
	var size := Vector2(rect.size * 16)

	# Floor and walls, from the same house tiles as the tavern outside (orange)
	var tiles := TileMapLayer.new()
	tiles.tile_set = ground.tile_set
	tiles.collision_enabled = false
	tiles.position = ground.position
	var shade := Vector2i(0, HOUSE_COLOURS[2])
	var last := rect.size.y - 1
	for x in rect.size.x:
		for y in rect.size.y:
			var c := rect.position + Vector2i(x, y)
			if x == 0 or x == rect.size.x - 1:
				var post_row := 0 if y == 0 else (5 if y == last else (4 if y == last - 1 else mini(y, 3)))
				tiles.set_cell(c, SOURCE_ID, (POST_LEFT if x == 0 else POST_RIGHT) + shade + Vector2i(0, post_row))
			elif y == last:
				tiles.set_cell(c, SOURCE_ID, (DOOR if x == HALL_DOOR_X else WALL_WINDOW) + shade)
			else:
				tiles.set_cell(c, SOURCE_ID, BACK_WALL if y < 2 else FLOOR)
	tiles.name = "TavernFloor"
	add_child(tiles)
	move_child(tiles, ground.get_index() + 1) # under everyone, Isla included

	var solid := StaticBody2D.new()
	hall.add_child(solid)
	var front := corner.y + last * 16
	var door_left := corner.x + HALL_DOOR_X * 16
	var walls: Array[Rect2] = [
		Rect2(corner.x, corner.y, 16, size.y), # left
		Rect2(corner.x + size.x - 16, corner.y, 16, size.y), # right
		Rect2(corner.x, corner.y, size.x, 28), # back wall
		Rect2(corner.x, front, door_left - corner.x, 12), # front, left of the door
		Rect2(door_left + 16, front, corner.x + size.x - door_left - 16, 12), # right of the door
	]
	var under := Node2D.new() # the floor's things: drawn under the people
	under.name = "TavernUnder"
	add_child(under)
	move_child(under, tiles.get_index() + 1)
	for item in HALL_LAYOUT:
		var sprite := Sprite2D.new()
		sprite.texture = prop.call(item[0], item[1])
		sprite.centered = false
		sprite.position = to_local(corner + item[2] * 16)
		(under if item[2].y <= 1 else hall).add_child(sprite)
	for piece in HALL_PIECES:
		var sprite := Sprite2D.new()
		sprite.texture = load(piece["texture"])
		sprite.centered = false
		sprite.position = to_local(corner + piece["position"])
		(under if piece.get("under", false) else hall).add_child(sprite) # the bar: in front of Isla
	for r in _hall_solid_rects():
		walls.append(Rect2(corner + r.position, r.size))
	for r in walls:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = to_local(r.get_center())
		solid.add_child(collision)
	for cell in HALL_STOOLS:
		var stool := Sprite2D.new()
		stool.texture = prop.call(7, 4)
		stool.scale = Vector2.ONE * 0.75 # the sheet's stools are a bit tall next to people
		stool.position = to_local(corner + cell * 16 + Vector2(8, 4))
		under.add_child(stool) # villagers sit in front of them
	add_child(hall)
	if player:
		move_child(hall, player.get_index()) # under the player, over Isla (she's behind the bar)

	# Darkness around the room, under everything so it never covers the map
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.position = to_local(corner) - Vector2.ONE * HALL_MARGIN
	backdrop.size = size + Vector2.ONE * HALL_MARGIN * 2
	add_child(backdrop)
	move_child(backdrop, 0)

	# The sign hangs on the front wall beside the door, over the roof's edge
	var outside := cell_to_world(tavern_rect.position) - Vector2(8, 8)
	var sign := Sprite2D.new()
	sign.texture = prop.call(TAVERN_SIGN.x, TAVERN_SIGN.y)
	sign.centered = false
	sign.position = to_local(outside + Vector2((tavern_rect.size.x - 3) * 16 + 4, (tavern_rect.size.y - 3) * 16 + 8))
	for i in houses.size():
		if houses[i].get("tavern", false) and i < _roofs.size():
			_roofs[i].add_child(sign)
	if sign.get_parent() == null:
		add_child(sign)


## What you bump into in the hall, in hall pixels: the lower part of the solid props, and the bar.
func _hall_solid_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for item in HALL_LAYOUT:
		if item[3] > 0:
			rects.append(Rect2(item[2] * 16 + Vector2(16 - item[3] / 2.0, 18), Vector2(item[3], 12)))
	for piece in HALL_PIECES:
		for r in piece["walls"]:
			rects.append(r)
	return rects


## A free seat right next to world_pos: {"position", "lift", "face"}, or {} if there's none.
## Seats are the tavern's stools and its sofa (anywhere a villager isn't already sitting).
func seat_near(world_pos: Vector2) -> Dictionary:
	if tavern_rect.size == Vector2i.ZERO:
		return {}
	var corner := cell_to_world(hall_rect().position) - Vector2(8, 8)
	var seats: Array[Dictionary] = []
	for stool in HALL_STOOLS:
		var spot: Vector2 = corner + stool * 16 + Vector2(8, 8)
		seats.append({"position": spot, "lift": -9.0, "face": _toward_table(spot)})
	for seat in HALL_SOFA_SEATS:
		seats.append({"position": cell_to_world(hall_rect().position + seat[0]), "lift": seat[1], "face": 1.0})
	var best := {}
	var best_distance := SEAT_REACH
	for seat in seats:
		var distance: float = world_pos.distance_to(seat["position"])
		if distance < best_distance and not _seat_taken(seat["position"]):
			best = seat
			best_distance = distance
	return best


## 1 or -1: which way someone on a stool at `spot` turns to face the nearest table.
func _toward_table(spot: Vector2) -> float:
	var corner := cell_to_world(hall_rect().position) - Vector2(8, 8)
	var nearest := INF
	var face := 1.0
	for item in HALL_LAYOUT:
		if item[1] != 5: # the tables row of the props sheet
			continue
		var center: Vector2 = corner + item[2] * 16 + Vector2(16, 16)
		if spot.distance_to(center) < nearest:
			nearest = spot.distance_to(center)
			face = signf(center.x - spot.x)
	return face if nearest < 48.0 else 1.0 # at the bar: face right


func _seat_taken(spot: Vector2) -> bool:
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.global_position.distance_to(spot) < 6.0:
			return true
	return false


## Doors that lead somewhere else: stepping into the tavern's door takes you into the hall,
## and the hall's door takes you back out to the street.
func _check_doors(cell: Vector2i, player: Node2D) -> void:
	if _fading:
		return
	if cell == _tavern_door():
		_go_through_door(player, _hall_door() + Vector2i(0, -1))
	elif cell == _hall_door():
		_go_through_door(player, _tavern_door() + Vector2i(0, 1))


func _go_through_door(player: Node2D, to_cell: Vector2i) -> void:
	_fading = true
	player.set_physics_process(false)
	var layer := CanvasLayer.new()
	layer.layer = 50
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	add_child(layer)
	var fade := create_tween()
	fade.tween_property(black, "color:a", 1.0, 0.25)
	fade.tween_callback(func():
		player.global_position = cell_to_world(to_cell)
		_update_camera_area(player))
	fade.tween_interval(0.1)
	fade.tween_property(black, "color:a", 0.0, 0.25)
	fade.tween_callback(func():
		player.set_physics_process(true)
		layer.queue_free()
		_fading = false)


# --- Villagers walking around --------------------------------------------------

## A villager's day: the schedule from story_text.gd and the cell of each stop.
func _make_routine(info: Dictionary) -> Dictionary:
	_build_walk_grids()
	var stops := {"home": {"cell": houses[info["home"]]["door"] + info.get("home_spot", Vector2i(0, -1))}}
	if info.has("work"):
		var work: Dictionary = info["work"]
		stops["work"] = {
			"cell": _nearest_free(_grid, _spot_cell(work["spot"]) + work.get("offset", Vector2i.ZERO)),
			"anim": work.get("anim", "IDLE"),
			"wander": work.get("wander", 0),
		}
	if info.has("seat"): # sitting down, on a stool unless "sit_lift" says otherwise
		stops["tavern"] = {
			"cell": hall_rect().position + info["seat"],
			"anim": "SITTING",
			"lift": info.get("sit_lift", -9.0),
			"face": info.get("seat_face", 1.0),
		}
	return {"schedule": info["routine"], "stops": stops}


## Named places villagers work at.
func _spot_cell(spot: String) -> Vector2i:
	var village := location_center("village")
	match spot:
		"lake_road": # where the road from the village reaches the lake
			return location_center("lake") - Vector2i(0, int(LOCATIONS["lake"]["radius"].y) - 1)
		"forest_road": # the end of the road north into the pines
			return Vector2i(village.x + 24, int(_forest_edge(village.x + 24)) + 1)
		"market":
			return market_cell
		"plaza":
			return village
	return location_center(spot)


## Walking grids: villagers stay on roads, the plaza and inside doorways; in the hall,
## anywhere on the floor that isn't furniture.
func _build_walk_grids() -> void:
	if _grid:
		return
	var ground := get_node("Ground") as TileMapLayer
	var decor := get_node("Decor") as TileMapLayer
	var doors := {}
	for house in houses:
		doors[house["door"]] = true
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, map_width, map_height)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_grid.update()
	for x in map_width:
		for y in map_height:
			var cell := Vector2i(x, y)
			_grid.set_point_solid(cell, not _villager_can_walk(ground, decor, cell, doors))
	# Bits of path you can't reach from the village (a dead-end scrap of road) don't count:
	# that way a villager's spot is always somewhere they can actually walk to
	var reached := {}
	var todo: Array[Vector2i] = [_nearest_free(_grid, location_center("village"))]
	reached[todo[0]] = true
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + d
			if _grid.region.has_point(next) and not _grid.is_point_solid(next) and not reached.has(next):
				reached[next] = true
				todo.append(next)
	for x in map_width:
		for y in map_height:
			if not reached.has(Vector2i(x, y)):
				_grid.set_point_solid(Vector2i(x, y), true)

	var hall := hall_rect()
	_hall_grid = AStarGrid2D.new()
	_hall_grid.region = hall
	_hall_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_hall_grid.update()
	_hall_grid.fill_solid_region(hall)
	_hall_grid.fill_solid_region(Rect2i(hall.position + Vector2i(1, 2), hall.size - Vector2i(2, 3)), false)
	_hall_grid.set_point_solid(_hall_door(), false)
	for r in _hall_solid_rects(): # the same footprints the furniture's collision has
		var first := Vector2i(r.position / 16)
		var last := Vector2i((r.end - Vector2.ONE) / 16)
		_hall_grid.fill_solid_region(Rect2i(hall.position + first, last - first + Vector2i.ONE))


func _villager_can_walk(ground: TileMapLayer, decor: TileMapLayer, cell: Vector2i, doors: Dictionary) -> bool:
	if bridge_cells.has(cell):
		return true
	if ground.get_cell_source_id(cell) != SOURCE_ID:
		return false
	var tile := ground.get_cell_atlas_coords(cell)
	if not (PATH_TILES.has(tile) or tile == FLOOR):
		return false
	if doors.has(cell) or decor.get_cell_source_id(cell) == -1:
		return true
	var thing := decor.get_cell_atlas_coords(cell) # rugs are fine to walk on
	return Rect2i(RUG["origin"], RUG["size"]).has_point(thing)


## World points to walk through from `from` to `to_cell`, going through the tavern's
## door if one end is in the hall (Vector2.INF in the list = step through the door).
func villager_route(from: Vector2, to_cell: Vector2i) -> PackedVector2Array:
	_build_walk_grids()
	var ground := get_node("Ground") as TileMapLayer
	var from_cell := ground.local_to_map(ground.to_local(from))
	var from_hall := hall_rect().has_point(from_cell)
	var to_hall := hall_rect().has_point(to_cell)
	var route := PackedVector2Array()
	if from_hall == to_hall:
		_add_path(route, _hall_grid if to_hall else _grid, from_cell, to_cell)
	elif from_hall:
		_add_path(route, _hall_grid, from_cell, _hall_door())
		route.append(Vector2.INF)
		_add_path(route, _grid, _tavern_door(), to_cell)
	else:
		_add_path(route, _grid, from_cell, _tavern_door())
		route.append(Vector2.INF)
		_add_path(route, _hall_grid, _hall_door(), to_cell)
	return route


func _add_path(route: PackedVector2Array, grid: AStarGrid2D, from: Vector2i, to: Vector2i) -> void:
	var path := grid.get_id_path(_nearest_free(grid, from), _nearest_free(grid, to), true)
	if path.is_empty():
		path = [to]
	for cell in path:
		route.append(cell_to_world(cell))


## The walkable cell closest to `cell` (itself if it's walkable).
func _nearest_free(grid: AStarGrid2D, cell: Vector2i) -> Vector2i:
	for radius in 12:
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue # just the ring at this distance
				var c := cell + Vector2i(x, y)
				if grid.region.has_point(c) and not grid.is_point_solid(c):
					return c
	return cell


## A random walkable cell within `radius` of `center` (for villagers who wander about).
func random_walkable_near(center: Vector2i, radius: int) -> Vector2i:
	_build_walk_grids()
	for attempt in 30:
		var c := center + Vector2i(randi_range(-radius, radius), randi_range(-radius, radius))
		if _grid.region.has_point(c) and not _grid.is_point_solid(c):
			return c
	return center


## Keeps the camera on the map, or on the hall while you're in it (also right after loading a save).
func _update_camera_area(player: Node2D) -> void:
	var ground := get_node("Ground") as TileMapLayer
	_in_hall = hall_rect().has_point(ground.local_to_map(ground.to_local(player.global_position)))
	if not player.has_method("set_camera_limits"):
		return
	if _in_hall:
		var top_left := cell_to_world(hall_rect().position) - Vector2(8, 8)
		player.set_camera_limits(Rect2(top_left, Vector2(HALL_SIZE * 16)).grow(HALL_MARGIN))
	else:
		player.set_camera_limits(_world_rect())


## Clouds drifting slowly over the sea around the island (drawn above everything).
func _spawn_clouds() -> void:
	var ground := get_node("Ground") as TileMapLayer
	var sheet: Texture2D = load(CLOUDS)
	var sky := Node2D.new()
	sky.name = "Clouds"
	sky.z_index = 50
	sky.set_script(load("res://scripts/clouds.gd"))
	sky.set("speed", CLOUD_SPEED)
	sky.set("area", _world_rect())
	add_child(sky)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var placed := 0
	for attempt in 600:
		if placed >= CLOUD_COUNT:
			break
		var cell := Vector2i(rng.randi_range(0, map_width - 1), rng.randi_range(0, map_height - 1))
		var open_sea := true # keep them off the island, so they frame it instead of hiding it
		for oy in range(-3, 4):
			for ox in range(-4, 5):
				if not WATER_TILES.has(ground.get_cell_atlas_coords(cell + Vector2i(ox, oy))) \
						and ground.get_cell_source_id(cell + Vector2i(ox, oy)) != -1:
					open_sea = false
		if not open_sea or location_at(cell) == "lake":
			continue
		var cloud := Sprite2D.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(Vector2(rng.randi() % (sheet.get_width() / CLOUD_SIZE.x) * CLOUD_SIZE.x, 0), Vector2(CLOUD_SIZE))
		cloud.texture = atlas
		cloud.flip_h = rng.randf() < 0.5
		cloud.position = to_local(cell_to_world(cell))
		sky.add_child(cloud)
		placed += 1


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
		atlas.region = Rect2(i * FIRE_FRAME_WIDTH, 0, FIRE_FRAME_WIDTH, strip.get_height())
		frames.add_frame("default", atlas)
	var fire := AnimatedSprite2D.new()
	fire.sprite_frames = frames
	fire.centered = false
	# The furnace's opening is pixels 6-11 across, 1-6 down: flames stand on its bottom edge
	fire.position = to_local(cell_to_world(forge_cell)) - Vector2(8, 8) + Vector2(7, -3)
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
		npc.set("frame_range", info.get("frames", Vector2i(-1, -1)))
		npc.set("shop", info.get("shop", ""))
		npc.set("talk_reach", info.get("reach", 28.0))
		npc.set("hair_color", info.get("hair_color", Color.WHITE))
		if info.has("home"):
			_house_owners[info["home"]] = info["name"]
		if info.has("routine"):
			npc.set("routine", _make_routine(info)) # it walks to the right spot by itself
		else:
			var origin := hall_rect().position if info["place"] == "tavern" else location_center(info["place"])
			npc.position = to_local(cell_to_world(origin + info["offset"]))
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


## New Game: you wake up on the lake shore next to Old Tom, and the intro plays.
func _start_intro() -> void:
	SaveGame.intro_requested = false
	var player := get_node_or_null("Player")
	var tom := get_node_or_null("Old Tom")
	if player == null:
		return
	if tom:
		var spot: Vector2i = tom.routine["stops"]["work"]["cell"]
		player.global_position = cell_to_world(_nearest_free(_grid, spot + Vector2i(-2, 0)))
		player.set_camera_limits(_world_rect())
	player._open_menu("res://scripts/story/intro.gd")


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
