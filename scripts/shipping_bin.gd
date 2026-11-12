extends StaticBody2D
## SmallWorld shipping bin: the crate outside your house.
## Created at runtime by map_generator (named "ShippingBin").
## Press E next to it to put crops, fish, eggs and milk inside (shipping_menu.gd).
## Everything in it is sold overnight for the same prices as the market, and you wake up
## to the coins. Until you sleep you can still take things back out.

const Farm := preload("res://scripts/farm.gd")
const CROPS := "res://assets/Sunnyside_World_Assets/Elements/Crops/"
const REACH := 26.0 # how close the player must be to use it

var contents := {} ## item -> how many are waiting to be shipped
var last_earned := 0 ## coins paid this morning (for the "Day 2" screen, see take_report)

var _peek: Sprite2D # one of the items, poking out of the crate


func _ready() -> void:
	var back := Sprite2D.new()
	back.texture = load(CROPS + "crate_base.png")
	add_child(back)
	_peek = Sprite2D.new()
	_peek.position = Vector2(0, -5)
	_peek.visible = false
	add_child(_peek)
	var front := Sprite2D.new() # the crate's front boards, drawn over what's inside
	front.texture = load(CROPS + "crate_top.png")
	front.position = Vector2(0, 1)
	add_child(front)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 8)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, 3)
	add_child(collision)


func is_near(world_pos: Vector2) -> bool:
	return world_pos.distance_to(global_position) < REACH


## What everything in the bin will sell for.
func value() -> int:
	var total := 0
	for item in contents:
		total += contents[item] * Farm.item_price(item)
	return total


func add(item: String, amount: int) -> void:
	contents[item] = contents.get(item, 0) + amount
	_update_look()
	for part in get_children():
		if part is Sprite2D:
			Juice.squash(part, 0.2) # the crate bounces as things drop in


func take(item: String, amount: int) -> void:
	contents[item] = contents.get(item, 0) - amount
	if contents[item] <= 0:
		contents.erase(item)
	_update_look()


## Called by the clock every morning: everything is sold and the player is paid.
func on_new_day(_day: int) -> void:
	last_earned = value()
	contents.clear()
	_update_look()
	var player := get_tree().get_first_node_in_group("player")
	if player and last_earned > 0:
		player.coins += last_earned


## The coins earned this morning, once (0 the second time you ask).
func take_report() -> int:
	var earned := last_earned
	last_earned = 0
	return earned


func get_state() -> Dictionary:
	return contents.duplicate()


func set_state(data: Dictionary) -> void:
	contents = {}
	for item in data:
		contents[item] = int(data[item])
	_update_look()


## Shows the most valuable thing inside, so you can see the bin isn't empty.
func _update_look() -> void:
	_peek.visible = not contents.is_empty()
	if contents.is_empty():
		return
	var best: String = contents.keys()[0]
	for item in contents:
		if Farm.item_price(item) > Farm.item_price(best):
			best = item
	_peek.texture = Farm.item_icon(best)
