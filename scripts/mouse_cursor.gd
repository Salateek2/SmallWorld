extends Node
## SmallWorld mouse cursor (autoload singleton "MouseCursor").
## Uses the pack's pixel-art cursors, blown up 3x with crisp pixels:
## an arrow normally, an open glove over anything clickable, a closed glove while clicking.

const UI := "res://assets/Sunnyside_World_Assets/UI/"
const SCALE := 3
# file, hotspot (the pixel that does the clicking, in the original small image)
const ARROW := ["cursor_04.png", Vector2(1, 1)]
const HAND := ["hand_open_02.png", Vector2(6, 1)]
const GRAB := ["hand_closed_02.png", Vector2(6, 3)]


func _ready() -> void:
	_use(Input.CURSOR_ARROW, ARROW)
	_use(Input.CURSOR_POINTING_HAND, HAND)
	# Every button gets the glove when you hover it, including ones made later
	get_tree().node_added.connect(_on_node_added)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Grab while the button is held, back to normal when it's let go
		_use(Input.CURSOR_ARROW, GRAB if event.pressed else ARROW)
		_use(Input.CURSOR_POINTING_HAND, GRAB if event.pressed else HAND)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _use(shape: Input.CursorShape, cursor: Array) -> void:
	var image: Image = load(UI + cursor[0]).get_image()
	image.resize(image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	Input.set_custom_mouse_cursor(image, shape, cursor[1] * SCALE)
