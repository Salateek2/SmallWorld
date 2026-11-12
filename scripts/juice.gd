extends Node
## SmallWorld juice (autoload singleton "Juice"): the small effects that make things feel good.
## Anything in the game can call these in one line:
##   Juice.shake(2.0)                  camera shake
##   Juice.puff(pos, color)            a burst of little pixel particles
##   Juice.squash(node) / pop_in(node) squash-and-stretch / pop into view
##   Juice.flash(node)                 flash a sprite bright for a moment
##   Juice.gain(pos, 1, "wood")        floating "+1" (several quick pickups add up to "+3")
##   Juice.toss(texture, from, player) an item hops up and flies into the player
##   Juice.hit_stop()                  freeze for a split second on a big hit
##   Juice.sound("pop")                a sound effect
## The sounds are made from code when the game starts (see _make_sounds), so there are
## no sound files. Set SOUND_ON to false to play the game silent.

const SOUND_ON := true
const VOLUME_DB := -14.0 # overall loudness of the sound effects
const MIX_RATE := 22050 # samples per second of the generated sounds

# Handy particle colors
const DIRT := Color(0.42, 0.28, 0.18)
const DUST := Color(0.93, 0.88, 0.76, 0.7)
const WATER := Color(0.6, 0.85, 1.0)
const LEAF := Color(0.36, 0.62, 0.3)
const WOOD := Color(0.8, 0.62, 0.4)
const SPARKLE := Color(1.0, 0.96, 0.7)

var _shake := 0.0 # how hard the camera is shaking right now (pixels)
var _shaken_camera: Camera2D
var _sounds := {} # name -> AudioStreamWAV
var _speakers: Array[AudioStreamPlayer] = [] # a few, so sounds can overlap
var _next_speaker := 0
var _gains := {} # key -> {"label", "total", "tween"} for the floating "+1"s
var _combo := 0 # pickups collected in a row (each one sounds a bit higher)
var _combo_at := 0 # when the last one was (ms)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # menus that pause the game still click
	_make_sounds()
	for i in 8:
		var speaker := AudioStreamPlayer.new()
		add_child(speaker)
		_speakers.append(speaker)


func _process(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake = move_toward(_shake, 0.0, delta * 9.0) # dies down in a fraction of a second
	if not is_instance_valid(_shaken_camera):
		_shake = 0.0
		return
	_shaken_camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake


# --- Camera -------------------------------------------------------------------

## Shakes the camera. strength = how many (world) pixels: 0.5 is a nudge, 3 is a big hit.
func shake(strength: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	if is_instance_valid(_shaken_camera) and _shaken_camera != camera:
		_shaken_camera.offset = Vector2.ZERO
	_shaken_camera = camera
	_shake = maxf(_shake, strength)


## Freezes the game for a split second: makes a hit feel heavy.
func hit_stop(seconds := 0.05) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout # real time, not slowed
	Engine.time_scale = 1.0


# --- Particles ----------------------------------------------------------------

## A burst of little pixel squares at a world position. They fly up and out, then fall
## (use a negative gravity for dust or sparkles that float up instead).
func puff(at: Vector2, color: Color, count := 6, speed := 30.0, gravity := 110.0) -> void:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.9 # nearly all at once
	particles.amount = count
	particles.lifetime = 0.45
	particles.direction = Vector2.UP
	particles.spread = 70.0
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.gravity = Vector2(0, gravity)
	particles.scale_amount_min = 1.5 # chunky pixel squares
	particles.scale_amount_max = 3.0
	particles.color = color
	var fade := Gradient.new() # solid most of the way, then fades out
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.6, Color.WHITE)
	particles.color_ramp = fade
	if not _add_to_world(particles):
		return
	particles.global_position = at
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


# --- Squash, pop and flash ----------------------------------------------------

## Squash and stretch: the node goes wide and flat for a moment, then springs back.
## Works on sprites and on UI (a negative amount stretches it tall instead).
func squash(node: CanvasItem, amount := 0.25, seconds := 0.3) -> void:
	_spring(node, Vector2(1.0 + amount, 1.0 - amount), seconds)


## The node grows from nothing to full size with a little overshoot.
func pop_in(node: CanvasItem, seconds := 0.25) -> void:
	_spring(node, Vector2(0.2, 0.2), seconds)


func _spring(node: CanvasItem, from: Vector2, seconds: float) -> void:
	if node is Control:
		node.pivot_offset = node.size / 2.0 # scale from the middle
	if node.has_meta("juice_tween") and is_instance_valid(node.get_meta("juice_tween")):
		node.get_meta("juice_tween").kill() # a new bounce replaces the old one
	node.set("scale", from)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2.ONE, seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	node.set_meta("juice_tween", tween)


## Tints the node for a moment, then fades back to normal (e.g. red when hurt).
## Colors above 1 make it brighter: Color(3, 3, 3) is a white flash.
func flash(node: CanvasItem, color := Color(3, 3, 3), seconds := 0.2, back := Color.WHITE) -> void:
	node.modulate = color
	node.create_tween().tween_property(node, "modulate", back, seconds)


# --- Items --------------------------------------------------------------------

## Floating "+1" that rises and fades. Calls with the same key while it's still showing
## add up ("+1", "+2", "+3"...) instead of piling up on top of each other.
func gain(at: Vector2, amount: int, key := "item") -> void:
	var entry: Dictionary = _gains.get(key, {})
	if entry.is_empty() or not is_instance_valid(entry["label"]):
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
		label.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.05))
		label.add_theme_constant_override("outline_size", 3)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(48, 10)
		label.z_index = 100 # above tree tops and roofs
		if not _add_to_world(label):
			return
		entry = {"label": label, "total": 0, "tween": null}
		_gains[key] = entry
	else:
		entry["tween"].kill()
	entry["total"] += amount
	var text: Label = entry["label"]
	text.text = "+%d" % entry["total"]
	text.global_position = at - Vector2(24, 5)
	text.modulate.a = 1.0
	squash(text, -0.3, 0.2)
	var tween := text.create_tween()
	tween.tween_property(text, "position:y", -12.0, 0.7).as_relative() \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(text, "modulate:a", 0.0, 0.25)
	tween.tween_callback(text.queue_free)
	entry["tween"] = tween


## An item hops up from `from` (world position), hangs for a moment, then flies into
## `to` (the player) and disappears. Used when you pick a crop.
func toss(texture: Texture2D, from: Vector2, to: Node2D) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	if not _add_to_world(sprite):
		return
	sprite.global_position = from
	var top := from + Vector2(0, -16)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "global_position", top, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "scale", Vector2.ONE, 0.2).from(Vector2(0.4, 0.4))
	tween.tween_interval(0.12)
	tween.tween_method(_fly.bind(sprite, top, to), 0.0, 1.0, 0.2).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sprite, "scale", Vector2(0.5, 0.5), 0.2)
	tween.tween_callback(sprite.queue_free)


func _fly(weight: float, sprite: Node2D, from: Vector2, to: Node2D) -> void:
	if is_instance_valid(to): # follows the player even if they walk away
		sprite.global_position = from.lerp(to.global_position + Vector2(0, -4), weight)


## Adds an effect to the map, drawn just above the player (and under the tree tops).
## False (and the node is thrown away) when there's no map, e.g. on the title screen.
func _add_to_world(node: Node) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or player.get_parent() == null:
		node.free()
		return false
	var world := player.get_parent()
	world.add_child(node)
	world.move_child(node, player.get_index() + 1)
	return true


# --- Sound --------------------------------------------------------------------

## Plays a sound from _make_sounds. pitch 1 = normal, higher = higher; louder is in dB.
func sound(sound_name: String, pitch := 1.0, louder := 0.0) -> void:
	if not SOUND_ON or not _sounds.has(sound_name):
		return
	var speaker := _speakers[_next_speaker]
	_next_speaker = (_next_speaker + 1) % _speakers.size()
	speaker.stream = _sounds[sound_name]
	speaker.pitch_scale = pitch
	speaker.volume_db = VOLUME_DB + louder
	speaker.play()


## The pickup "pop". Collect several quickly and each one sounds a little higher.
func pickup_sound() -> void:
	var now := Time.get_ticks_msec()
	_combo = _combo + 1 if now - _combo_at < 700 else 0
	_combo_at = now
	sound("pop", 1.0 + minf(_combo, 8) * 0.07)


## Builds every sound effect out of beeps (_tone) and hisses (_noise).
func _make_sounds() -> void:
	_sounds = {
		# Interface
		"tick": _wav(_tone(880, 880, 0.03, 0.4)),
		"confirm": _wav(_tone(660, 660, 0.06, 0.6) + _tone(990, 990, 0.12, 0.6)),
		"talk": _wav(_tone(420, 470, 0.04, 0.35)),
		"coin": _wav(_tone(1320, 1320, 0.05, 0.5) + _tone(1760, 1760, 0.18, 0.5)),
		# Items and farming
		"pop": _wav(_tone(520, 880, 0.09, 0.7)),
		"harvest": _wav(_tone(523, 523, 0.07, 0.6) + _tone(659, 659, 0.07, 0.6) + _tone(784, 784, 0.16, 0.6)),
		"plant": _wav(_tone(330, 210, 0.09, 0.7)),
		"dig": _wav(_mix(_noise(0.13, 0.12, 0.6), _tone(120, 70, 0.1, 0.5))),
		"water": _wav(_noise(0.32, 0.45, 0.35)),
		# Axe and sword
		"chop": _wav(_mix(_noise(0.08, 0.3, 0.6), _tone(170, 90, 0.09, 0.7))),
		"fell": _wav(_mix(_noise(0.4, 0.15, 0.7), _tone(110, 45, 0.35, 0.8))),
		"swish": _wav(_noise(0.11, 0.6, 0.3)),
		"hit": _wav(_mix(_noise(0.07, 0.4, 0.6), _tone(240, 110, 0.1, 0.7))),
		"hurt": _wav(_tone(330, 110, 0.2, 0.7, true)),
	}


## A beep that slides from one pitch (Hz) to another and fades out. buzzy = harsher.
func _tone(from_hz: float, to_hz: float, seconds: float, volume := 0.8, buzzy := false) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(seconds * MIX_RATE)
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / count # 0..1 through the sound
		phase += TAU * lerpf(from_hz, to_hz, t) / MIX_RATE
		var wave := sin(phase)
		if buzzy:
			wave = wave * 0.6 + signf(wave) * 0.4
		samples[i] = wave * volume * _envelope(i, t)
	return samples


## A hiss that fades out. brightness: near 0 = a dull thud, near 1 = a sharp "tss".
func _noise(seconds: float, brightness: float, volume := 0.8) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(seconds * MIX_RATE)
	samples.resize(count)
	var smooth := 0.0
	var gain := sqrt((2.0 - brightness) / brightness) # smoothing makes it quieter: make up for it
	for i in count:
		smooth += brightness * (randf_range(-1.0, 1.0) - smooth)
		samples[i] = clampf(smooth * gain * volume * _envelope(i, float(i) / count), -1.0, 1.0)
	return samples


## Loudness over a sound's life: a very quick fade-in (no click), then dying away.
func _envelope(i: int, t: float) -> float:
	return minf(1.0, i / (0.004 * MIX_RATE)) * exp(-4.0 * t) * (1.0 - t)


## Two sounds on top of each other.
func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(maxi(a.size(), b.size()))
	for i in samples.size():
		var value := 0.0
		if i < a.size():
			value += a[i]
		if i < b.size():
			value += b[i]
		samples[i] = clampf(value, -1.0, 1.0)
	return samples


## Turns samples (-1..1) into a sound Godot can play.
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(samples[i] * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
