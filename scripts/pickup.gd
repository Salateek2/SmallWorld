extends Node2D
## SmallWorld pickup: an item lying on the ground (e.g. wood from a felled tree).
## It pops out in a little arc, bounces, then waits. Walk close and it's pulled
## toward you and collected.

const MAGNET_RANGE := 16.0 # starts flying to the player inside this distance
const COLLECT_RANGE := 6.0
const POP_TIME := 0.45
const POP_HEIGHT := 14.0

var item := "wood" ## what the player gets (see player.add_item)
var texture: Texture2D

var _sprite: Sprite2D
var _can_collect := false


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.offset = Vector2(0, -4) # rests on its shadow
	add_child(_sprite)


## Flies from `from` to `to` (world positions) in an arc, then lands with a small bounce.
func launch(from: Vector2, to: Vector2) -> void:
	global_position = from
	var tween := create_tween()
	tween.tween_property(self, "global_position", to, POP_TIME)
	tween.parallel().tween_method(_set_height.bind(POP_HEIGHT), 0.0, 1.0, POP_TIME)
	tween.tween_method(_set_height.bind(4.0), 0.0, 1.0, 0.18) # little bounce
	tween.tween_callback(func(): _can_collect = true)


func _set_height(t: float, height: float) -> void:
	# Up and back down: highest in the middle of the jump
	_sprite.position.y = -sin(t * PI) * height


func _draw() -> void:
	draw_circle(Vector2(0, 1), 3.5, Color(0, 0, 0, 0.25)) # soft shadow


func _process(delta: float) -> void:
	if not _can_collect:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var target := player.global_position + Vector2(0, 4)
	var distance := global_position.distance_to(target)
	if distance > MAGNET_RANGE:
		return
	# Pulled in, faster the closer it gets
	var speed := 60.0 + (MAGNET_RANGE - distance) * 8.0
	global_position = global_position.move_toward(target, speed * delta)
	if distance < COLLECT_RANGE:
		player.add_item(item, 1)
		queue_free()
