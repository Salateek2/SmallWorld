extends Node2D
## Clouds drifting slowly east over the sea; one that leaves the map comes back in on
## the west side. Made by map_generator._spawn_clouds.

var speed := 4.0 ## pixels per second
var area := Rect2() ## the map, in world pixels


func _process(delta: float) -> void:
	for cloud in get_children():
		cloud.position.x += speed * delta
		if cloud.global_position.x > area.end.x + 48.0:
			cloud.global_position.x = area.position.x - 48.0
