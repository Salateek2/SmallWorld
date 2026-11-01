extends RefCounted
## Shared look for SmallWorld's UI: panels built from the pack's 9-slice box art.
## Use with: const UIStyle := preload("res://scripts/ui_style.gd")

const UI := "res://assets/Sunnyside_World_Assets/UI/"

static var _cache := {}


## A little pixel heart (7 x 6), full (red) or empty (just the outline), `scale` times bigger.
static func heart(full: bool, scale: int) -> ImageTexture:
	var key := "heart_%s_%d" % [full, scale]
	if not _cache.has(key):
		var rows := [ # o = outline, r = red, h = highlight
			".oo.oo.",
			"ohroRro",
			"orrrrro",
			".orrro.",
			"..oro..",
			"...o...",
		]
		var outline := Color(0.24, 0.16, 0.12)
		var red := Color(0.89, 0.27, 0.33) if full else Color(0.86, 0.78, 0.68)
		var light := Color(1.0, 0.7, 0.7) if full else red
		var image := Image.create(7, 6, false, Image.FORMAT_RGBA8)
		for y in rows.size():
			for x in 7:
				match rows[y][x]:
					"o": image.set_pixel(x, y, outline)
					"r", "R": image.set_pixel(x, y, red)
					"h": image.set_pixel(x, y, light)
		image.resize(7 * scale, 6 * scale, Image.INTERPOLATE_NEAREST)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


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
