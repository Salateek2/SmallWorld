@tool
extends Node2D
## SmallWorld map generator.
## Select the Main node and press "Generate Map" in the Inspector.
## The result is a normal tilemap, so you can fix anything by hand afterwards.
## Needs TileMapLayer children named Ground, Decor and (optional) Canopy.
## Canopy should be below Player in the Scene panel so tree tops draw over the player.

@export_tool_button("Generate Map") var generate_action = generate
@export_tool_button("Clear Map") var clear_action = clear

@export var map_width: int = 60
@export var map_height: int = 40
## 0 = a new random map every time. Any other number = the same map every time.
@export var seed_value: int = 0
@export var pond_count: int = 2
@export_range(0.0, 0.2) var tree_density: float = 0.03
@export_range(0.0, 0.3) var decor_density: float = 0.06

const SOURCE_ID := 0

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

# Multi-tile objects: top-left tile and size in tiles
const BIG_OBJECTS := [
	{"origin": Vector2i(49, 1), "size": Vector2i(2, 2)}, # round bush
	{"origin": Vector2i(49, 3), "size": Vector2i(2, 2)}, # apple bush
	{"origin": Vector2i(49, 5), "size": Vector2i(2, 2)}, # orange bush
	{"origin": Vector2i(52, 3), "size": Vector2i(1, 3)}, # small pine
	{"origin": Vector2i(51, 6), "size": Vector2i(2, 3)}, # tall pine
]

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
}

enum ChopResult { NOTHING, HIT, FELLED }
const CHOPPABLE := [3, 4] # indices in BIG_OBJECTS: the two pines
const STUMP := Vector2i(31, 5)
const HITS_TO_CHOP := 3

var _tree_hits := {} # tree cell -> hits so far

var _rng := RandomNumberGenerator.new()
var _blocked := {} # cells that already have a path, water or object


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

	for layer in [ground, decor]:
		_setup_collision(layer.tile_set)

	clear()
	_fill_grass(ground)
	_make_path(ground)
	for i in pond_count:
		_make_pond(ground)
	_scatter_objects(decor, canopy)
	print("SmallWorld map generated (seed %d)" % _rng.seed)


func clear() -> void:
	_blocked.clear()
	for layer_name in ["Ground", "Decor", "Canopy"]:
		var layer := get_node_or_null(layer_name) as TileMapLayer
		if layer:
			layer.clear()


func _fill_grass(ground: TileMapLayer) -> void:
	for x in map_width:
		for y in map_height:
			var tile := GRASS
			if _rng.randf() < 0.15:
				tile = GRASS_VARIANTS[_rng.randi() % GRASS_VARIANTS.size()]
			ground.set_cell(Vector2i(x, y), SOURCE_ID, tile)


func _make_path(ground: TileMapLayer) -> void:
	# A 2-tile-wide road wandering from the left edge to the right edge
	var y := map_height / 2
	for x in map_width:
		for dy in 2:
			var cell := Vector2i(x, y + dy)
			ground.set_cell(cell, SOURCE_ID, PATH_TILES[_rng.randi() % PATH_TILES.size()])
			_blocked[cell] = true
		if x % 4 == 0:
			y = clampi(y + _rng.randi_range(-1, 1), 3, map_height - 5)


func _make_pond(ground: TileMapLayer) -> void:
	for attempt in 20:
		var rx := _rng.randi_range(3, 6)
		var ry := _rng.randi_range(2, 4)
		var center := Vector2i(
			_rng.randi_range(rx + 2, map_width - rx - 3),
			_rng.randi_range(ry + 2, map_height - ry - 3))
		var cells: Array[Vector2i] = []
		var ok := true
		for x in range(-rx, rx + 1):
			for y in range(-ry, ry + 1):
				var d := pow(float(x) / rx, 2) + pow(float(y) / ry, 2)
				if d <= 1.0 + _rng.randf_range(-0.15, 0.15):
					var cell := center + Vector2i(x, y)
					if _near_blocked(cell, 2):
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
	for coords in COLLISION_RECTS:
		if not source.has_tile(coords):
			continue
		var data := source.get_tile_data(coords, 0)
		while data.get_collision_polygons_count(0) > 0:
			data.remove_collision_polygon(0, 0)
		# Polygon points are relative to the tile's center, so shift by -8
		var r: Rect2 = COLLISION_RECTS[coords]
		r.position -= Vector2(8, 8)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, PackedVector2Array([
			r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
		]))


func _scatter_objects(decor: TileMapLayer, canopy: TileMapLayer) -> void:
	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)
			if _blocked.has(cell):
				continue
			var roll := _rng.randf()
			if roll < tree_density:
				_try_place_big(decor, canopy, cell, BIG_OBJECTS[_rng.randi() % BIG_OBJECTS.size()])
			elif roll < tree_density + decor_density:
				if not _near_blocked(cell, 0):
					decor.set_cell(cell, SOURCE_ID, SMALL_DECOR[_rng.randi() % SMALL_DECOR.size()])
					_blocked[cell] = true


func _try_place_big(decor: TileMapLayer, canopy: TileMapLayer, cell: Vector2i, obj: Dictionary) -> void:
	var size: Vector2i = obj["size"]
	var origin: Vector2i = obj["origin"]
	if cell.x + size.x > map_width or cell.y + size.y > map_height:
		return
	for ox in size.x:
		for oy in size.y:
			if _near_blocked(cell + Vector2i(ox, oy), 1):
				return
	for ox in size.x:
		for oy in size.y:
			var offset := Vector2i(ox, oy)
			# Bottom row (trunk) goes on Decor, everything above on Canopy
			var layer: TileMapLayer = decor if oy == size.y - 1 else canopy
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
