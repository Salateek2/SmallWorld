extends Node2D
## SmallWorld foraging: wild things you can pick with E as you wander the island.
## Created at runtime by map_generator (named "Forage", drawn just below the Player).
##   Mushrooms: the blue mushrooms already growing on the map (mostly under the pines).
##   Berries and oranges: the fruit bushes. Picked, a bush stands bare until the fruit is back.
##   Seashells: a few wash up on the beaches every morning.
## Mushrooms and fruit grow back a few days after you pick them (REGROW_DAYS).
## The player asks target_near() what E would pick, and calls pick() when the hand gets there.

const SOURCE_ID := 0
const MUSHROOM := Vector2i(49, 7) # tile on the Decor layer
const BARE_BUSH := Vector2i(49, 1) # top-left tile of the round bush (2 x 2): a fruit bush, picked
const BUSHES := {"berry": Vector2i(49, 3), "orange": Vector2i(49, 5)} # item -> the bush's top-left tile
const SAND_TILES: Array[Vector2i] = [Vector2i(43, 7), Vector2i(43, 8)]
const SHELL_ICON := "res://assets/forage/shell.png"

const REGROW_DAYS := {"mushroom": 2, "berry": 3, "orange": 3}
const FRUIT_PER_BUSH := 3
const SHELLS_AT_START := 10
const SHELLS_PER_DAY := 4 # new ones each morning...
const MAX_SHELLS := 16 # ...until this many lie around
const PROMPTS := {"mushroom": "Pick mushroom", "berry": "Pick berries", "orange": "Pick oranges", "shell": "Pick up shell"}
## Spots checked around the player, nearest to the hands first (x flips with the way they face):
## the tile in front, under the feet, and a bush they stand below or beside.
const REACH: Array[Vector2] = [Vector2(16, 6), Vector2(0, 5), Vector2(8, 5), Vector2(0, -8), Vector2(10, -6)]

var _ground: TileMapLayer
var _decor: TileMapLayer
var _canopy: TileMapLayer # the top half of bushes
var _clock: Node
var _picked := {} # cell (a bush's top-left tile) -> {"kind", "day" it was picked}
var _shells := {} # cell -> Sprite2D
var _sand: Array[Vector2i] = [] # beach tiles a shell can land on


func _ready() -> void:
	var world := get_parent()
	_ground = world.get_node("Ground")
	_decor = world.get_node("Decor")
	_canopy = world.get_node_or_null("Canopy")
	if _canopy == null:
		_canopy = _decor
	transform = _ground.transform # same space as the tiles
	for tile in SAND_TILES:
		_sand.append_array(_ground.get_used_cells_by_id(SOURCE_ID, tile))
	_clock = world.get_node_or_null("DayNight")
	if _clock:
		_clock.new_day.connect(_on_new_day)
	_wash_up(SHELLS_AT_START)


## What the player could pick from where they stand: {"kind", "cell", "at" (world position),
## "text" (for the E prompt)}, or {} for nothing.
func target_near(world_pos: Vector2, facing: float) -> Dictionary:
	for offset in REACH:
		var spot := world_pos + Vector2(offset.x * facing, offset.y)
		var target := _target_at(_ground.local_to_map(_ground.to_local(spot)))
		if not target.is_empty():
			return target
	return {}


func _target_at(cell: Vector2i) -> Dictionary:
	if _shells.has(cell):
		return _target("shell", cell, _shells[cell].global_position)
	if _decor.get_cell_source_id(cell) == SOURCE_ID and _decor.get_cell_atlas_coords(cell) == MUSHROOM:
		return _target("mushroom", cell, _world(cell))
	for layer in [_decor, _canopy]:
		if layer.get_cell_source_id(cell) != SOURCE_ID:
			continue
		for kind in BUSHES:
			var part: Vector2i = layer.get_cell_atlas_coords(cell) - BUSHES[kind]
			if part.x >= 0 and part.x <= 1 and part.y >= 0 and part.y <= 1:
				var corner := cell - part
				return _target(kind, corner, _world(corner) + Vector2(8, 8)) # the middle of the bush
	return {}


func _target(kind: String, cell: Vector2i, at: Vector2) -> Dictionary:
	return {"kind": kind, "cell": cell, "at": at, "text": PROMPTS[kind]}


## Takes the thing off the map. Returns how many of target["kind"] that gives (0 = it's gone).
func pick(target: Dictionary) -> int:
	var kind: String = target["kind"]
	var cell: Vector2i = target["cell"]
	match kind:
		"shell":
			if not _shells.has(cell):
				return 0
			_shells[cell].queue_free()
			_shells.erase(cell)
			return 1
		"mushroom":
			if _decor.get_cell_atlas_coords(cell) != MUSHROOM:
				return 0
			_decor.erase_cell(cell)
			_picked[cell] = {"kind": kind, "day": _today()}
			return 1
	if not _swap_bush(cell, BUSHES[kind], BARE_BUSH):
		return 0
	_picked[cell] = {"kind": kind, "day": _today()}
	return FRUIT_PER_BUSH


## Redraws a 2 x 2 bush with another bush's tiles (fruit <-> bare). False if it isn't there.
func _swap_bush(corner: Vector2i, from: Vector2i, to: Vector2i) -> bool:
	var found := false
	for x in 2:
		for y in 2:
			var part := Vector2i(x, y)
			for layer in [_decor, _canopy]:
				if layer.get_cell_source_id(corner + part) == SOURCE_ID \
						and layer.get_cell_atlas_coords(corner + part) == from + part:
					layer.set_cell(corner + part, SOURCE_ID, to + part)
					found = true
	return found


## Every morning: what was picked long enough ago is back, and the tide leaves new shells.
func _on_new_day(day: int) -> void:
	var farm := get_parent().get_node_or_null("Farm")
	for cell in _picked.keys():
		var kind: String = _picked[cell]["kind"]
		if day - int(_picked[cell]["day"]) < REGROW_DAYS[kind]:
			continue
		if kind == "mushroom":
			if _decor.get_cell_source_id(cell) != -1 or (farm and farm.has_plot(cell)):
				continue # something else is there now (a crop, say): try again tomorrow
			_decor.set_cell(cell, SOURCE_ID, MUSHROOM)
		else:
			_swap_bush(cell, BARE_BUSH, BUSHES[kind])
		_picked.erase(cell)
	_wash_up(SHELLS_PER_DAY)


## Leaves up to `count` new shells on free beach tiles.
func _wash_up(count: int) -> void:
	if _sand.is_empty():
		return
	for attempt in count * 4:
		if count <= 0 or _shells.size() >= MAX_SHELLS:
			return
		var cell: Vector2i = _sand.pick_random()
		if _shells.has(cell) or _decor.get_cell_source_id(cell) != -1 or _canopy.get_cell_source_id(cell) != -1 \
				or _ground.get_cell_source_id(cell) != SOURCE_ID or not SAND_TILES.has(_ground.get_cell_atlas_coords(cell)):
			continue
		_add_shell(cell)
		count -= 1


func _add_shell(cell: Vector2i) -> void:
	var shell := Sprite2D.new()
	shell.texture = load(SHELL_ICON)
	shell.position = _ground.map_to_local(cell) + Vector2(randi_range(-3, 3), randi_range(-3, 3))
	shell.flip_h = randf() < 0.5
	add_child(shell)
	_shells[cell] = shell


func _world(cell: Vector2i) -> Vector2:
	return _ground.to_global(_ground.map_to_local(cell))


func _today() -> int:
	return _clock.day if _clock else 1


## What's been picked and where the shells lie, for the save file.
func get_state() -> Dictionary:
	var picked := []
	for cell in _picked:
		picked.append([cell.x, cell.y, _picked[cell]["kind"], _picked[cell]["day"]])
	var shells := []
	for cell in _shells:
		shells.append([cell.x, cell.y])
	return {"picked": picked, "shells": shells}


## Restores a save into a freshly loaded map. (JSON turns whole numbers into decimals, hence the int().)
func set_state(data: Dictionary) -> void:
	for cell in _shells:
		_shells[cell].queue_free()
	_shells.clear()
	_picked.clear()
	for entry in data.get("picked", []):
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		var kind: String = entry[2]
		if kind == "mushroom":
			_decor.erase_cell(cell)
		elif BUSHES.has(kind):
			_swap_bush(cell, BUSHES[kind], BARE_BUSH)
		else:
			continue
		_picked[cell] = {"kind": kind, "day": int(entry[3])}
	for entry in data.get("shells", []):
		_add_shell(Vector2i(int(entry[0]), int(entry[1])))
