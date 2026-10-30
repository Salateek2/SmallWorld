extends RefCounted
## Shared look for SmallWorld's UI: panels built from the pack's 9-slice box art.
## Use with: const UIStyle := preload("res://scripts/ui_style.gd")

const UI := "res://assets/Sunnyside_World_Assets/UI/"

static var _cache := {}


## A StyleBox from the 9-slice pieces in UI/9slice_box_white ("dt" dark brown,
## "lt" light brown, "w" white), blown up `scale` times with crisp pixels.
static func nine(prefix: String, scale: int, margin: int) -> StyleBoxTexture:
	var key := "%s_%d" % [prefix, scale]
	if not _cache.has(key):
		var image := Image.create(9, 9, false, Image.FORMAT_RGBA8)
		var parts := {"tl": Vector2i(0, 0), "tc": Vector2i(1, 0), "tr": Vector2i(2, 0),
			"lc": Vector2i(0, 1), "c": Vector2i(1, 1), "rc": Vector2i(2, 1),
			"bl": Vector2i(0, 2), "bc": Vector2i(1, 2), "br": Vector2i(2, 2)}
		for part in parts:
			var piece: Image = load(UI + "9slice_box_white/%s_box_9slice_%s.png" % [prefix, part]).get_image()
			piece.convert(Image.FORMAT_RGBA8)
			image.blit_rect(piece, Rect2i(0, 0, 3, 3), parts[part] * 3)
		image.resize(9 * scale, 9 * scale, Image.INTERPOLATE_NEAREST)
		_cache[key] = ImageTexture.create_from_image(image)
	var style := StyleBoxTexture.new()
	style.texture = _cache[key]
	style.set_texture_margin_all(3 * scale)
	style.set_content_margin_all(margin)
	return style
