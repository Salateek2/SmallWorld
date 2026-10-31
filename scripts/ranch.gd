extends Node2D
## SmallWorld ranch: the animals in the pen next to your house.
## Created at runtime by map_generator (named "Ranch").
## Buy animals at the market, put wheat in the trough to feed them (E at the trough),
## and every morning fed chickens lay an egg and fed cows can be milked (E on the cow).

const ANIMALS_DIR := "res://assets/Sunnyside_World_Assets/Elements/Animals/"
const ITEMS_DIR := "res://assets/Sunnyside_World_Assets/Elements/Crops/"
## Animals you can buy. price = market price, product = what a fed animal gives each morning
const TYPES := {
	"chicken": {"name": "Chicken", "price": 80, "strip": "spr_deco_chicken_01_strip4.png", "product": "egg", "speed": 14.0},
	"cow": {"name": "Cow", "price": 250, "strip": "spr_deco_cow_strip4.png", "product": "milk", "speed": 8.0},
}
const MAX_ANIMALS := 8
const FEED := "wheat" ## what goes in the trough, one per animal per day
const REACH := 26.0 # how close you need to be to the trough or a cow

var pen: Rect2 ## inside of the pen, world pixels (set by map_generator)
var trough: Vector2 ## middle of the trough, world pixels

var _animals: Array[Dictionary] = [] # {type, fed, has_milk, node}
var _feed_shown: Array[Sprite2D] = [] # wheat lying in the trough


## Adds a new animal to the pen. Returns false if the pen is full.
func add_animal(type: String) -> bool:
	if _animals.size() >= MAX_ANIMALS:
		return false
	var node := Node2D.new()
	node.set_script(load("res://scripts/animal.gd"))
	node.strip = load(ANIMALS_DIR + TYPES[type]["strip"])
	node.pen = pen
	node.speed = TYPES[type]["speed"]
	node.position = to_local(Vector2(randf_range(pen.position.x, pen.end.x), randf_range(pen.position.y, pen.end.y)))
	add_child(node)
	_animals.append({"type": type, "fed": false, "has_milk": false, "node": node})
	return true


func count(type := "") -> int:
	return _animals.filter(func(a): return type == "" or a["type"] == type).size()


func is_full() -> bool:
	return _animals.size() >= MAX_ANIMALS


## Called by the clock every morning: fed animals give their product, then they're hungry again.
func on_new_day(_day: int) -> void:
	var world := get_parent()
	for animal in _animals:
		if animal["fed"]:
			if animal["type"] == "chicken":
				# The egg is lying somewhere in the pen, waiting to be picked up
				var spot := Vector2(randf_range(pen.position.x, pen.end.x), randf_range(pen.position.y, pen.end.y))
				world.drop_items(spot, "egg", load(ITEMS_DIR + "egg.png"), 1, Vector2(0, 4))
			elif animal["type"] == "cow":
				animal["has_milk"] = true
				animal["node"].show_milk(true)
		animal["fed"] = false
	_update_trough()


## E near the trough or a cow. Returns true if it did something (so tools don't swing).
func interact(player: Node2D) -> bool:
	var at := player.global_position
	if at.distance_to(trough) < REACH:
		_fill_trough(player)
		return true
	for animal in _animals:
		var node: Node2D = animal["node"]
		if animal["has_milk"] and at.distance_to(node.global_position) < REACH:
			animal["has_milk"] = false
			node.show_milk(false)
			get_parent().drop_items(node.global_position, "milk", load(ITEMS_DIR + "milk.png"), 1, Vector2(10, 14))
			player.notify("You milked the cow!")
			return true
	return false


func _fill_trough(player: Node2D) -> void:
	var hungry := _animals.filter(func(a): return not a["fed"])
	if _animals.is_empty():
		player.notify("No animals yet - buy some at the market")
		return
	if hungry.is_empty():
		player.notify("Everyone has eaten today")
		return
	var wheat: int = player.crops.get(FEED, 0)
	if wheat <= 0:
		player.notify("Put wheat in the trough to feed your animals")
		return
	var fed := mini(wheat, hungry.size())
	for i in fed:
		hungry[i]["fed"] = true
	player.crops[FEED] = wheat - fed
	if player.crops[FEED] <= 0:
		player.crops.erase(FEED)
	player.refresh_ui()
	player.notify("Fed %d animal%s (-%d wheat)" % [fed, "" if fed == 1 else "s", fed])
	_update_trough()


## Wheat shows in the trough while any animal has been fed today.
func _update_trough() -> void:
	var fed := _animals.filter(func(a): return a["fed"]).size()
	var wanted := mini(fed, 3)
	while _feed_shown.size() < wanted:
		var straw := Sprite2D.new()
		straw.texture = load(ITEMS_DIR + "wheat_05.png")
		straw.position = to_local(trough) + Vector2((_feed_shown.size() - 1) * 7, -4)
		straw.rotation = randf_range(-0.4, 0.4)
		add_child(straw)
		_feed_shown.append(straw)
	while _feed_shown.size() > wanted:
		_feed_shown.pop_back().queue_free()


# --- Save / load -------------------------------------------------------------

func get_state() -> Array:
	return _animals.map(func(a): return {"type": a["type"], "fed": a["fed"], "has_milk": a["has_milk"]})


func set_state(list: Array) -> void:
	for data in list:
		if add_animal(data["type"]):
			var animal: Dictionary = _animals.back()
			animal["fed"] = data["fed"]
			animal["has_milk"] = data["has_milk"]
			animal["node"].show_milk(animal["has_milk"])
	_update_trough()
