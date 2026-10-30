extends Control
## The pack's gold corner brackets (UI/selectbox_*.png) around a UI element,
## bouncing outward and back. Add it as a child of the thing to highlight
## (it fills its parent), or move it with reparent(). Used by the hotbar and inventory.

const UI := "res://assets/Sunnyside_World_Assets/UI/"

@export var pixel_scale := 3 ## how much bigger than the original 8x9 art
@export var outset := 6.0 ## how far the brackets sit outside the parent's edges
@export var bounce := 4.0 ## extra distance at the peak of the bounce

var _spread := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # always exactly the parent's size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for corner in ["tl", "tr", "bl", "br"]:
		var piece := TextureRect.new()
		piece.name = corner
		piece.texture = load(UI + "selectbox_%s.png" % corner)
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.size = piece.texture.get_size() * pixel_scale
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(piece)
	resized.connect(_place)
	# Bounce: out and back in, forever (whole-pixel steps keep the art crisp)
	var tween := create_tween().set_loops()
	tween.tween_property(self, "_spread", bounce, 0.45).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "_spread", 0.0, 0.45).set_trans(Tween.TRANS_SINE)


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	var d := outset + roundf(_spread)
	for piece: TextureRect in get_children():
		var p := Vector2(-d, -d)
		if piece.name.ends_with("r"):
			p.x = size.x - piece.size.x + d
		if piece.name.begins_with("b"):
			p.y = size.y - piece.size.y + d
		piece.position = p
